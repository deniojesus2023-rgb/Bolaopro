import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const sb = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
)

const API_KEY  = Deno.env.get('API_FOOTBALL_KEY') ?? ''
const BASE_URL = 'https://api-football-v1.p.rapidapi.com/v3'

async function apiFetch(endpoint: string) {
  const res = await fetch(`${BASE_URL}${endpoint}`, {
    headers: {
      'x-rapidapi-key':  API_KEY,
      'x-rapidapi-host': 'api-football-v1.p.rapidapi.com',
    },
  })
  const json = await res.json()
  return json
}

function mapStatus(short: string): string {
  if (short === 'FT' || short === 'AET' || short === 'PEN') return 'finished'
  if (short === '1H' || short === '2H' || short === 'HT' || short === 'ET' || short === 'P') return 'live'
  if (short === 'PST' || short === 'CANC' || short === 'ABD') return 'cancelled'
  return 'scheduled'
}

function getTopScorer(events: any[]): string | null {
  const map: { [key: string]: number } = {}
  for (const e of events) {
    const name = e.player?.name
    if (name) map[name] = (map[name] ?? 0) + 1
  }
  const keys = Object.keys(map)
  if (keys.length === 0) return null
  let top = keys[0]
  for (const k of keys) {
    if (map[k] > map[top]) top = k
  }
  return top
}

Deno.serve(async () => {
  const debug: string[] = []
  let synced = 0
  let updated = 0

  const LEAGUES = [
    { api_id: 71,  season: 2026, name: 'Brasileirao' },
    { api_id: 13,  season: 2026, name: 'Libertadores' },
    { api_id: 73,  season: 2026, name: 'Copa do Brasil' },
    { api_id: 39,  season: 2025, name: 'Premier League' },
  ]

  for (const league of LEAGUES) {
    try {
      debug.push(`Buscando ${league.name}...`)

      const nextJson = await apiFetch(
        `/fixtures?league=${league.api_id}&season=${league.season}&next=20`
      )
      const lastJson = await apiFetch(
        `/fixtures?league=${league.api_id}&season=${league.season}&last=10`
      )

      debug.push(`next keys: ${Object.keys(nextJson).join(',')} | errors: ${JSON.stringify(nextJson.errors)} | results: ${nextJson.results}`)

      if (nextJson.errors && Object.keys(nextJson.errors).length > 0) {
        debug.push(`API error: ${JSON.stringify(nextJson.errors)}`)
        continue
      }

      const allFixtures = [
        ...(nextJson.response ?? []),
        ...(lastJson.response ?? []),
      ]
      debug.push(`${allFixtures.length} jogos encontrados (next:${nextJson.results ?? 0} last:${lastJson.results ?? 0})`)

      const { data: comp } = await sb
        .from('competitions')
        .select('id')
        .eq('api_id', league.api_id)
        .single()

      for (const f of allFixtures) {
        const fixture = f.fixture
        const teams   = f.teams
        const goals   = f.goals
        const ld      = f.league

        const { error } = await sb.from('matches').upsert(
          {
            api_fixture_id: fixture.id,
            competition_id: comp?.id ?? null,
            home_team:      teams.home.name,
            away_team:      teams.away.name,
            home_team_logo: teams.home.logo,
            away_team_logo: teams.away.logo,
            round_name:     ld.round ?? null,
            match_date:     new Date(fixture.date).toISOString(),
            status:         mapStatus(fixture.status.short),
            home_score:     goals.home ?? null,
            away_score:     goals.away ?? null,
            updated_at:     new Date().toISOString(),
          },
          { onConflict: 'api_fixture_id' }
        )

        if (error) debug.push(`DB erro: ${error.message}`)
        else synced++
      }

      await new Promise((r) => setTimeout(r, 700))
    } catch (err) {
      debug.push(`ERRO ${league.name}: ${String(err)}`)
    }
  }

  const { data: liveMatches } = await sb
    .from('matches')
    .select('id, api_fixture_id')
    .in('status', ['scheduled', 'live'])
    .lt('match_date', new Date().toISOString())
    .not('api_fixture_id', 'is', null)
    .limit(20)

  debug.push(`Pendentes: ${liveMatches?.length ?? 0}`)

  for (const match of liveMatches ?? []) {
    try {
      const json     = await apiFetch(`/fixtures?id=${match.api_fixture_id}`)
      const fixtures = json.response ?? []
      if (!fixtures.length) continue

      const fixture = fixtures[0].fixture
      const goals   = fixtures[0].goals
      const status  = mapStatus(fixture.status.short)

      let topScorer = null
      if (status === 'finished') {
        const evJson = await apiFetch(
          `/fixtures/events?fixture=${match.api_fixture_id}&type=Goal`
        )
        topScorer = getTopScorer(evJson.response ?? [])
      }

      await sb.from('matches').update({
        status,
        home_score: goals.home ?? null,
        away_score: goals.away ?? null,
        top_scorer: topScorer,
        updated_at: new Date().toISOString(),
      }).eq('id', match.id)

      if (status === 'finished') {
        await sb.rpc('calculate_prediction_points', { p_match_id: match.id })
        const { data: bms } = await sb
          .from('bolao_matches').select('bolao_id').eq('match_id', match.id)
        for (const bm of bms ?? []) {
          await sb.rpc('finalize_bolao', { p_bolao_id: bm.bolao_id })
        }
      }

      updated++
      await new Promise((r) => setTimeout(r, 300))
    } catch (err) {
      debug.push(`Erro match: ${String(err)}`)
    }
  }

  return new Response(
    JSON.stringify({ success: true, synced, updated, debug, at: new Date().toISOString() }),
    { headers: { 'Content-Type': 'application/json' } }
  )
})
