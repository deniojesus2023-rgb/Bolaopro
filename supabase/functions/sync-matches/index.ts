import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const sb = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
)

// API Football (direto, não RapidAPI)
const AF_KEY  = Deno.env.get('API_FOOTBALL_KEY') ?? ''
const AF_URL  = 'https://v3.football.api-sports.io'

// The Odds API
const ODDS_KEY = Deno.env.get('ODDS_API_KEY') ?? ''
const ODDS_URL = 'https://api.the-odds-api.com/v4'

// ─── API Football ────────────────────────────────────────────────
async function afFetch(endpoint: string) {
  const res = await fetch(`${AF_URL}${endpoint}`, {
    headers: { 'x-apisports-key': AF_KEY },
  })
  if (!res.ok) throw new Error(`AF HTTP ${res.status} on ${endpoint}`)
  return res.json()
}

// ─── The Odds API ────────────────────────────────────────────────
async function fetchOdds(sport: string): Promise<any[]> {
  const url =
    `${ODDS_URL}/sports/${sport}/odds/` +
    `?apiKey=${ODDS_KEY}&regions=eu&markets=h2h&bookmakers=sportingbet,superbet`
  const res = await fetch(url)
  if (!res.ok) return []
  return res.json()
}

// ─── Helpers ─────────────────────────────────────────────────────
function norm(s: string): string {
  return s
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]/g, '')
}

function matchOddsGame(
  oddsData: any[],
  homeTeam: string,
  awayTeam: string,
  matchDate: string
) {
  const h    = norm(homeTeam)
  const a    = norm(awayTeam)
  const day  = matchDate.substring(0, 10)
  for (const g of oddsData) {
    const gh   = norm(g.home_team ?? '')
    const ga   = norm(g.away_team ?? '')
    const gday = (g.commence_time ?? '').substring(0, 10)
    if (
      gday === day &&
      (gh.includes(h) || h.includes(gh)) &&
      (ga.includes(a) || a.includes(ga))
    ) return g
  }
  return null
}

function bookmakerOdds(game: any, key: string) {
  const bm = game.bookmakers?.find((b: any) => b.key === key)
  if (!bm) return null
  const market = bm.markets?.find((m: any) => m.key === 'h2h')
  if (!market) return null
  const outcomes: any[] = market.outcomes ?? []
  const draw  = outcomes.find((o: any) => o.name === 'Draw')
  const home  = outcomes.find(
    (o: any) => o.name !== 'Draw' && norm(o.name) === norm(game.home_team)
  )
  const away  = outcomes.find(
    (o: any) => o.name !== 'Draw' && norm(o.name) === norm(game.away_team)
  )
  return {
    home: home?.price ?? null,
    draw: draw?.price ?? null,
    away: away?.price ?? null,
  }
}

function mapStatus(short: string): string {
  if (['FT', 'AET', 'PEN'].includes(short))             return 'finished'
  if (['1H', '2H', 'HT', 'ET', 'P', 'BT'].includes(short)) return 'live'
  if (['PST', 'CANC', 'ABD', 'WO', 'AWD'].includes(short)) return 'cancelled'
  return 'scheduled'
}

function topScorer(events: any[]): string | null {
  const map: Record<string, number> = {}
  for (const e of events) {
    const name = e.player?.name
    if (name) map[name] = (map[name] ?? 0) + 1
  }
  const keys = Object.keys(map)
  if (!keys.length) return null
  return keys.reduce((a, b) => (map[a] >= map[b] ? a : b))
}

// ─── Leagues config ───────────────────────────────────────────────
const LEAGUES = [
  { api_id: 71,  season: 2026, name: 'Brasileirao',    oddsKey: 'soccer_brazil_campeonato' },
  { api_id: 13,  season: 2026, name: 'Libertadores',   oddsKey: 'soccer_conmebol_libertadores' },
  { api_id: 73,  season: 2026, name: 'Copa do Brasil',  oddsKey: null },
  { api_id: 39,  season: 2025, name: 'Premier League', oddsKey: 'soccer_epl' },
]

// ─── Main handler ─────────────────────────────────────────────────
Deno.serve(async () => {
  const debug: string[] = []
  let synced  = 0
  let updated = 0

  // Pre-load odds per sport (avoid repeated requests)
  const oddsCache: Record<string, any[]> = {}
  for (const lg of LEAGUES) {
    if (lg.oddsKey && !oddsCache[lg.oddsKey]) {
      try {
        oddsCache[lg.oddsKey] = await fetchOdds(lg.oddsKey)
        debug.push(`Odds ${lg.oddsKey}: ${oddsCache[lg.oddsKey].length} jogos`)
      } catch (e) {
        debug.push(`Odds erro ${lg.oddsKey}: ${String(e)}`)
        oddsCache[lg.oddsKey] = []
      }
    }
  }

  // ── Sync fixtures per league ────────────────────────────────────
  for (const league of LEAGUES) {
    try {
      debug.push(`Buscando ${league.name}…`)

      const [nextJson, lastJson] = await Promise.all([
        afFetch(`/fixtures?league=${league.api_id}&season=${league.season}&next=20`),
        afFetch(`/fixtures?league=${league.api_id}&season=${league.season}&last=10`),
      ])

      if (nextJson.errors && Object.keys(nextJson.errors).length > 0) {
        debug.push(`Erro API ${league.name}: ${JSON.stringify(nextJson.errors)}`)
        continue
      }

      const all = [...(nextJson.response ?? []), ...(lastJson.response ?? [])]
      debug.push(`${league.name}: ${all.length} jogos`)

      const { data: comp } = await sb
        .from('competitions')
        .select('id')
        .eq('api_id', league.api_id)
        .single()

      const leagueOdds = league.oddsKey ? (oddsCache[league.oddsKey] ?? []) : []

      for (const f of all) {
        const fixture = f.fixture
        const teams   = f.teams
        const goals   = f.goals
        const ld      = f.league

        const matchDateISO = new Date(fixture.date).toISOString()

        // Look for odds
        const oddsGame = matchOddsGame(leagueOdds, teams.home.name, teams.away.name, matchDateISO)
        const spOdds   = oddsGame ? bookmakerOdds(oddsGame, 'sportingbet') : null
        const sbOdds   = oddsGame ? bookmakerOdds(oddsGame, 'superbet')    : null

        const { error } = await sb.from('matches').upsert(
          {
            api_fixture_id:        fixture.id,
            competition_id:        comp?.id ?? null,
            home_team:             teams.home.name,
            away_team:             teams.away.name,
            home_team_logo:        teams.home.logo,
            away_team_logo:        teams.away.logo,
            round_name:            ld.round ?? null,
            match_date:            matchDateISO,
            status:                mapStatus(fixture.status.short),
            home_score:            goals.home ?? null,
            away_score:            goals.away ?? null,
            // Sportingbet odds
            odd_home_sportingbet:  spOdds?.home ?? null,
            odd_draw_sportingbet:  spOdds?.draw ?? null,
            odd_away_sportingbet:  spOdds?.away ?? null,
            // Superbet odds
            odd_home_superbet:     sbOdds?.home ?? null,
            odd_draw_superbet:     sbOdds?.draw ?? null,
            odd_away_superbet:     sbOdds?.away ?? null,
            updated_at:            new Date().toISOString(),
          },
          { onConflict: 'api_fixture_id' }
        )

        if (error) debug.push(`DB erro fixture ${fixture.id}: ${error.message}`)
        else synced++
      }

      await new Promise((r) => setTimeout(r, 500))
    } catch (err) {
      debug.push(`ERRO ${league.name}: ${String(err)}`)
    }
  }

  // ── Update live/pending matches ─────────────────────────────────
  const { data: pending } = await sb
    .from('matches')
    .select('id, api_fixture_id')
    .in('status', ['scheduled', 'live'])
    .lt('match_date', new Date().toISOString())
    .not('api_fixture_id', 'is', null)
    .limit(20)

  debug.push(`Pendentes: ${pending?.length ?? 0}`)

  for (const match of pending ?? []) {
    try {
      const json     = await afFetch(`/fixtures?id=${match.api_fixture_id}`)
      const fixtures = json.response ?? []
      if (!fixtures.length) continue

      const f      = fixtures[0]
      const status = mapStatus(f.fixture.status.short)

      let scorer = null
      if (status === 'finished') {
        const evJson = await afFetch(
          `/fixtures/events?fixture=${match.api_fixture_id}&type=Goal`
        )
        scorer = topScorer(evJson.response ?? [])
      }

      await sb.from('matches').update({
        status,
        home_score: f.goals.home ?? null,
        away_score: f.goals.away ?? null,
        top_scorer: scorer,
        updated_at: new Date().toISOString(),
      }).eq('id', match.id)

      if (status === 'finished') {
        await sb.rpc('calculate_prediction_points', { p_match_id: match.id })
        const { data: bms } = await sb
          .from('bolao_matches')
          .select('bolao_id')
          .eq('match_id', match.id)
        for (const bm of bms ?? []) {
          await sb.rpc('finalize_bolao', { p_bolao_id: bm.bolao_id })
        }
      }

      updated++
      await new Promise((r) => setTimeout(r, 300))
    } catch (err) {
      debug.push(`Erro match ${match.id}: ${String(err)}`)
    }
  }

  return new Response(
    JSON.stringify({ success: true, synced, updated, debug, at: new Date().toISOString() }),
    { headers: { 'Content-Type': 'application/json' } }
  )
})
