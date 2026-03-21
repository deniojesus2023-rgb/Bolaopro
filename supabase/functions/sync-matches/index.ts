import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const sb = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
)

const AF_KEY   = Deno.env.get('API_FOOTBALL_KEY') ?? ''
const AF_URL   = 'https://v3.football.api-sports.io'
const ODDS_KEY = Deno.env.get('ODDS_API_KEY') ?? ''
const ODDS_URL = 'https://api.the-odds-api.com/v4'

// ─── API helpers ──────────────────────────────────────────────────
async function afFetch(endpoint: string) {
  const res = await fetch(`${AF_URL}${endpoint}`, {
    headers: { 'x-apisports-key': AF_KEY },
  })
  if (!res.ok) throw new Error(`AF HTTP ${res.status} ${endpoint}`)
  return res.json()
}

async function afSafe(endpoint: string): Promise<any[]> {
  try { return (await afFetch(endpoint)).response ?? [] } catch { return [] }
}

async function fetchOdds(sport: string): Promise<any[]> {
  try {
    const url = `${ODDS_URL}/sports/${sport}/odds/?apiKey=${ODDS_KEY}&regions=eu&markets=h2h&bookmakers=sportingbet,superbet`
    const res = await fetch(url)
    return res.ok ? res.json() : []
  } catch { return [] }
}

// ─── Normalização ─────────────────────────────────────────────────
function norm(s: string): string {
  return s.toLowerCase().normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]/g, '')
}

function matchOddsGame(odds: any[], home: string, away: string, date: string) {
  const h = norm(home), a = norm(away), day = date.substring(0, 10)
  for (const g of odds) {
    const gh = norm(g.home_team ?? ''), ga = norm(g.away_team ?? '')
    const gd = (g.commence_time ?? '').substring(0, 10)
    if (gd === day && (gh.includes(h) || h.includes(gh)) && (ga.includes(a) || a.includes(ga))) return g
  }
  return null
}

function bookmakerOdds(game: any, key: string) {
  const bm = game.bookmakers?.find((b: any) => b.key === key)
  const market = bm?.markets?.find((m: any) => m.key === 'h2h')
  if (!market) return null
  const outcomes: any[] = market.outcomes ?? []
  const draw = outcomes.find((o: any) => o.name === 'Draw')
  const home = outcomes.find((o: any) => o.name !== 'Draw' && norm(o.name) === norm(game.home_team))
  const away = outcomes.find((o: any) => o.name !== 'Draw' && norm(o.name) === norm(game.away_team))
  return { home: home?.price ?? null, draw: draw?.price ?? null, away: away?.price ?? null }
}

function mapStatus(short: string): string {
  if (['FT', 'AET', 'PEN'].includes(short))                    return 'finished'
  if (['1H', '2H', 'HT', 'ET', 'P', 'BT'].includes(short))    return 'live'
  if (['PST', 'CANC', 'ABD', 'WO', 'AWD'].includes(short))     return 'cancelled'
  return 'scheduled'
}

function topScorer(events: any[]): string | null {
  const map: Record<string, number> = {}
  for (const e of events) { const n = e.player?.name; if (n) map[n] = (map[n] ?? 0) + 1 }
  const keys = Object.keys(map)
  return keys.length ? keys.reduce((a, b) => map[a] >= map[b] ? a : b) : null
}

function toNum(v: any): number | null {
  if (v === null || v === undefined) return null
  if (typeof v === 'string') return parseInt(v.replace('%', '')) || 0
  return Number(v)
}

// ─── Salvar estatísticas ──────────────────────────────────────────
async function saveStats(matchId: string, fixtureId: number, homeTeam: string, debug: string[]) {
  const data = await afSafe(`/fixtures/statistics?fixture=${fixtureId}`)
  if (!data.length) return
  for (const ts of data) {
    const isHome = norm(ts.team?.name ?? '') === norm(homeTeam)
    const row: Record<string, any> = {
      match_id:  matchId,
      team_type: isHome ? 'home' : 'away',
      updated_at: new Date().toISOString(),
    }
    for (const s of ts.statistics ?? []) {
      const v = toNum(s.value)
      switch (s.type) {
        case 'Ball Possession':  row.possession        = toNum(s.value); break
        case 'Shots on Goal':    row.shots_on_goal     = v; break
        case 'Shots off Goal':   row.shots_off_goal    = v; break
        case 'Blocked Shots':    row.shots_blocked     = v; break
        case 'Total Shots':      row.shots_total       = v; break
        case 'Fouls':            row.fouls             = v; break
        case 'Corner Kicks':     row.corners           = v; break
        case 'Offsides':         row.offsides          = v; break
        case 'Yellow Cards':     row.yellow_cards      = v; break
        case 'Red Cards':        row.red_cards         = v; break
        case 'Goalkeeper Saves': row.goalkeeper_saves  = v; break
        case 'Total passes':     row.passes_total      = v; break
        case 'Passes accurate':  row.passes_accurate   = v; break
        case 'Passes %':         row.passes_percentage = toNum(s.value); break
      }
    }
    const { error } = await sb.from('match_statistics')
      .upsert(row, { onConflict: 'match_id,team_type' })
    if (error) debug.push(`Stats err ${fixtureId}: ${error.message}`)
  }
}

// ─── Salvar escalações ────────────────────────────────────────────
async function saveLineups(matchId: string, fixtureId: number, homeTeam: string, debug: string[]) {
  const data = await afSafe(`/fixtures/lineups?fixture=${fixtureId}`)
  if (!data.length) return
  for (const tl of data) {
    const isHome = norm(tl.team?.name ?? '') === norm(homeTeam)
    const players = [
      ...(tl.startXI     ?? []).map((p: any) => ({ ...p.player, substitute: false })),
      ...(tl.substitutes ?? []).map((p: any) => ({ ...p.player, substitute: true })),
    ]
    const { error } = await sb.from('match_lineups').upsert({
      match_id:   matchId,
      team_type:  isHome ? 'home' : 'away',
      team_name:  tl.team?.name,
      formation:  tl.formation,
      coach_name: tl.coach?.name,
      players:    JSON.stringify(players),
      updated_at: new Date().toISOString(),
    }, { onConflict: 'match_id,team_type' })
    if (error) debug.push(`Lineup err ${fixtureId}: ${error.message}`)
  }
}

// ─── Salvar eventos (gols, cartões, subs) ─────────────────────────
async function saveEvents(matchId: string, fixtureId: number, homeTeam: string, debug: string[]) {
  const data = await afSafe(`/fixtures/events?fixture=${fixtureId}`)
  if (!data.length) return
  await sb.from('match_events').delete().eq('match_id', matchId)
  const rows = data.map((e: any) => ({
    match_id:     matchId,
    minute:       e.time?.elapsed,
    minute_extra: e.time?.extra,
    team_type:    norm(e.team?.name ?? '') === norm(homeTeam) ? 'home' : 'away',
    team_name:    e.team?.name,
    player_name:  e.player?.name,
    assist_name:  e.assist?.name,
    event_type:   e.type,
    event_detail: e.detail,
    comments:     e.comments,
  }))
  const { error } = await sb.from('match_events').insert(rows)
  if (error) debug.push(`Events err ${fixtureId}: ${error.message}`)
}

// ─── Configuração das ligas ───────────────────────────────────────
const LEAGUES = [
  { api_id: 71,  season: 2026, name: 'Brasileirao',   oddsKey: 'soccer_brazil_campeonato' },
  { api_id: 13,  season: 2026, name: 'Libertadores',  oddsKey: 'soccer_conmebol_libertadores' },
  { api_id: 73,  season: 2026, name: 'Copa do Brasil', oddsKey: null },
  { api_id: 39,  season: 2025, name: 'Premier League', oddsKey: 'soccer_epl' },
]

// ─── Handler principal ────────────────────────────────────────────
Deno.serve(async () => {
  const debug: string[] = []
  let synced = 0, updated = 0
  const now = new Date()

  // Pré-carregar odds
  const oddsCache: Record<string, any[]> = {}
  for (const lg of LEAGUES) {
    if (lg.oddsKey && !oddsCache[lg.oddsKey]) {
      oddsCache[lg.oddsKey] = await fetchOdds(lg.oddsKey)
      debug.push(`Odds ${lg.oddsKey}: ${oddsCache[lg.oddsKey].length}`)
    }
  }

  // ── Sync por liga ────────────────────────────────────────────────
  for (const league of LEAGUES) {
    try {
      debug.push(`Buscando ${league.name}…`)
      const [nextJson, lastJson] = await Promise.all([
        afFetch(`/fixtures?league=${league.api_id}&season=${league.season}&next=20`),
        afFetch(`/fixtures?league=${league.api_id}&season=${league.season}&last=10`),
      ])
      if (nextJson.errors && Object.keys(nextJson.errors).length > 0) {
        debug.push(`Erro API ${league.name}: ${JSON.stringify(nextJson.errors)}`); continue
      }

      const all = [...(nextJson.response ?? []), ...(lastJson.response ?? [])]
      debug.push(`${league.name}: ${all.length} fixtures`)

      const { data: comp } = await sb.from('competitions').select('id').eq('api_id', league.api_id).single()
      const leagueOdds = league.oddsKey ? (oddsCache[league.oddsKey] ?? []) : []

      for (const f of all) {
        const { fixture, teams, goals, score, league: ld } = f
        const matchDateISO = new Date(fixture.date).toISOString()
        const status       = mapStatus(fixture.status.short)

        const oddsGame = matchOddsGame(leagueOdds, teams.home.name, teams.away.name, matchDateISO)
        const spOdds   = oddsGame ? bookmakerOdds(oddsGame, 'sportingbet') : null
        const sbOdds   = oddsGame ? bookmakerOdds(oddsGame, 'superbet')    : null

        const { data: matchRow, error } = await sb.from('matches').upsert({
          api_fixture_id:       fixture.id,
          competition_id:       comp?.id ?? null,
          home_team:            teams.home.name,
          away_team:            teams.away.name,
          home_team_logo:       teams.home.logo,
          away_team_logo:       teams.away.logo,
          round_name:           ld.round ?? null,
          match_date:           matchDateISO,
          status,
          home_score:           goals.home ?? null,
          away_score:           goals.away ?? null,
          // Dados extra do jogo
          referee:              fixture.referee ?? null,
          venue_name:           fixture.venue?.name ?? null,
          venue_city:           fixture.venue?.city ?? null,
          minute:               fixture.status?.elapsed ?? null,
          halftime_home:        score?.halftime?.home ?? null,
          halftime_away:        score?.halftime?.away ?? null,
          extratime_home:       score?.extratime?.home ?? null,
          extratime_away:       score?.extratime?.away ?? null,
          penalty_home:         score?.penalty?.home ?? null,
          penalty_away:         score?.penalty?.away ?? null,
          // Odds
          odd_home_sportingbet: spOdds?.home ?? null,
          odd_draw_sportingbet: spOdds?.draw ?? null,
          odd_away_sportingbet: spOdds?.away ?? null,
          odd_home_superbet:    sbOdds?.home ?? null,
          odd_draw_superbet:    sbOdds?.draw ?? null,
          odd_away_superbet:    sbOdds?.away ?? null,
          updated_at:           now.toISOString(),
        }, { onConflict: 'api_fixture_id' }).select('id').single()

        if (error || !matchRow) { debug.push(`DB err ${fixture.id}: ${error?.message}`); continue }
        synced++

        const hoursToMatch = (new Date(matchDateISO).getTime() - now.getTime()) / 3600000
        const hoursSince   = (now.getTime() - new Date(matchDateISO).getTime()) / 3600000

        if (status === 'live') {
          await saveStats(matchRow.id, fixture.id, teams.home.name, debug)
          await saveEvents(matchRow.id, fixture.id, teams.home.name, debug)
          await saveLineups(matchRow.id, fixture.id, teams.home.name, debug)
        } else if (status === 'finished' && hoursSince < 72) {
          await saveStats(matchRow.id, fixture.id, teams.home.name, debug)
          await saveEvents(matchRow.id, fixture.id, teams.home.name, debug)
          await saveLineups(matchRow.id, fixture.id, teams.home.name, debug)
        } else if (status === 'scheduled' && hoursToMatch < 24) {
          await saveLineups(matchRow.id, fixture.id, teams.home.name, debug)
        }

        await new Promise(r => setTimeout(r, 300))
      }
      await new Promise(r => setTimeout(r, 500))
    } catch (err) { debug.push(`ERRO ${league.name}: ${String(err)}`) }
  }

  // ── Atualizar partidas ao vivo / pendentes ────────────────────────
  const { data: pending } = await sb.from('matches')
    .select('id, api_fixture_id, home_team')
    .in('status', ['scheduled', 'live'])
    .lt('match_date', now.toISOString())
    .not('api_fixture_id', 'is', null)
    .limit(20)

  debug.push(`Pendentes: ${pending?.length ?? 0}`)

  for (const match of pending ?? []) {
    try {
      const json = await afFetch(`/fixtures?id=${match.api_fixture_id}`)
      const fixtures = json.response ?? []
      if (!fixtures.length) continue

      const f      = fixtures[0]
      const status = mapStatus(f.fixture.status.short)
      const score  = f.score

      let scorer = null
      if (status === 'finished') {
        const evJson = await afFetch(`/fixtures/events?fixture=${match.api_fixture_id}&type=Goal`)
        scorer = topScorer(evJson.response ?? [])
      }

      await sb.from('matches').update({
        status,
        home_score:     f.goals.home ?? null,
        away_score:     f.goals.away ?? null,
        minute:         f.fixture.status?.elapsed ?? null,
        halftime_home:  score?.halftime?.home ?? null,
        halftime_away:  score?.halftime?.away ?? null,
        extratime_home: score?.extratime?.home ?? null,
        extratime_away: score?.extratime?.away ?? null,
        penalty_home:   score?.penalty?.home ?? null,
        penalty_away:   score?.penalty?.away ?? null,
        top_scorer:     scorer,
        updated_at:     now.toISOString(),
      }).eq('id', match.id)

      await saveStats(match.id, match.api_fixture_id, match.home_team, debug)
      await saveEvents(match.id, match.api_fixture_id, match.home_team, debug)

      if (status === 'finished') {
        await sb.rpc('calculate_prediction_points', { p_match_id: match.id })
        const { data: bms } = await sb.from('bolao_matches').select('bolao_id').eq('match_id', match.id)
        for (const bm of bms ?? []) await sb.rpc('finalize_bolao', { p_bolao_id: bm.bolao_id })
      }

      updated++
      await new Promise(r => setTimeout(r, 300))
    } catch (err) { debug.push(`Err match ${match.id}: ${String(err)}`) }
  }

  return new Response(
    JSON.stringify({ success: true, synced, updated, debug, at: now.toISOString() }),
    { headers: { 'Content-Type': 'application/json' } }
  )
})
