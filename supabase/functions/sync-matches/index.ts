// Edge Function: sincroniza jogos do Brasileirão (A, B, C) da API-Football
// com a tabela public.matches e liquida os bilhetes quando jogos terminam.
// O app NUNCA chama a API: ele só escuta a tabela via Supabase Realtime.
//
// Modos (corpo JSON): { "mode": "live" | "schedule" | "settle" | "leagues" }
//   live      – chamado a cada minuto pelo pg_cron; só gasta API se houver jogo na janela
//   schedule  – chamado 1x por dia; traz a agenda dos próximos dias (ontem → +14 dias).
//               Aceita também "season", "from" e "to" (YYYY-MM-DD) para testes.
//   settle    – força a liquidação dos bilhetes
//   leagues   – lista as ligas do Brasil na API (para conferir os IDs 71/72/75)
import { createClient } from 'npm:@supabase/supabase-js@2'
import { brtDate, fixtureToRow, hasChanged, isFinalStatus, type ApiFixture, type MatchRow } from './mapping.ts'

const API_BASE = 'https://v3.football.api-sports.io'
const API_KEY = Deno.env.get('API_FOOTBALL_KEY') ?? ''
const CRON_SECRET = Deno.env.get('CRON_SECRET') ?? ''

const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
  auth: { persistSession: false },
})

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })

const currentSeason = () => Number(brtDate(0).slice(0, 4)) // Brasileirão é ano-calendário

async function apiGet(path: string, params: Record<string, string | number>) {
  const url = new URL(API_BASE + path)
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, String(v))
  const res = await fetch(url, { headers: { 'x-apisports-key': API_KEY } })
  if (!res.ok) {
    const detail = (await res.text().catch(() => '')).slice(0, 300)
    throw new Error(`API-Football HTTP ${res.status}: ${detail}`)
  }
  const body = await res.json()
  const errors = body.errors
  const hasErrors = Array.isArray(errors) ? errors.length > 0 : errors && Object.keys(errors).length > 0
  if (hasErrors) throw new Error(`API-Football: ${JSON.stringify(errors)}`)
  return (body.response ?? []) as any[]
}

async function upsertMatches(rows: MatchRow[]) {
  if (!rows.length) return
  const { error } = await db.from('matches').upsert(rows, { onConflict: 'api_fixture_id' })
  if (error) throw new Error(`upsert matches: ${error.message}`)
}

async function settle() {
  const { data, error } = await db.rpc('settle_tickets')
  if (error) throw new Error(`settle_tickets: ${error.message}`)
  return data as number
}

// ---- Agenda: 1 chamada por liga ----------------------------------------
async function syncSchedule(season: number, fromDate?: string, toDate?: string) {
  const { data: comps, error } = await db.from('competitions').select('id, api_league_id')
  if (error) throw new Error(error.message)

  const from = fromDate ?? brtDate(-1)
  const to = toDate ?? brtDate(14)
  let upserted = 0
  for (const c of comps ?? []) {
    const fixtures = (await apiGet('/fixtures', { league: c.api_league_id, season, from, to })) as ApiFixture[]
    const rows = fixtures.map((f) => fixtureToRow(f, c.id))
    await upsertMatches(rows)
    upserted += rows.length
  }
  // Rede de segurança: liquida qualquer bilhete que tenha ficado pendente.
  const settled = await settle()
  return { season, from, to, upserted, settled }
}

// ---- Ao vivo: 1 chamada (até 20 jogos por chamada) ----------------------
async function syncLive() {
  const now = Date.now()
  const { data: open, error } = await db
    .from('matches')
    .select('api_fixture_id, competition_id, status, minute, home_score, away_score, kickoff_at')
    .in('status', ['scheduled', 'live'])
    .gte('kickoff_at', new Date(now - 5 * 3600_000).toISOString()) // jogos que começaram há até 5h
    .lte('kickoff_at', new Date(now + 5 * 60_000).toISOString()) // ou começam em até 5 min
  if (error) throw new Error(error.message)
  if (!open?.length) return { skipped: 'nenhum jogo na janela, sem custo de API' }

  const byFixture = new Map(open.map((m) => [m.api_fixture_id as number, m]))
  const ids = [...byFixture.keys()]
  let apiCalls = 0
  let changed = 0
  let finished = 0

  for (let i = 0; i < ids.length; i += 20) {
    const fixtures = (await apiGet('/fixtures', { ids: ids.slice(i, i + 20).join('-') })) as ApiFixture[]
    apiCalls++
    const rows: MatchRow[] = []
    for (const f of fixtures) {
      const current = byFixture.get(f.fixture.id)
      if (!current) continue
      const row = fixtureToRow(f, current.competition_id)
      if (!hasChanged(current, row)) continue
      rows.push(row)
      if (isFinalStatus(row.status)) finished++
    }
    await upsertMatches(rows)
    changed += rows.length
  }

  const settled = finished > 0 ? await settle() : null
  return { watching: ids.length, apiCalls, changed, finished, settled }
}

async function listLeagues(season: number) {
  const leagues = await apiGet('/leagues', { country: 'Brazil', season })
  return leagues.map((l) => ({ id: l.league.id, name: l.league.name, type: l.league.type }))
}

Deno.serve(async (req) => {
  if (!CRON_SECRET || req.headers.get('x-cron-secret') !== CRON_SECRET) {
    return json({ error: 'unauthorized' }, 401)
  }
  if (!API_KEY) return json({ error: 'API_FOOTBALL_KEY não configurada' }, 500)

  let body: { mode?: string; season?: number; from?: string; to?: string } = {}
  try {
    body = await req.json()
  } catch {
    /* corpo vazio = modo live */
  }
  const mode = body.mode ?? 'live'
  const season = Number(body.season) || currentSeason()

  try {
    if (mode === 'live') return json(await syncLive())
    if (mode === 'schedule') {
      // from/to opcionais (YYYY-MM-DD): úteis para testar com temporadas antigas
      const isDate = (d?: string) => !!d && /^\d{4}-\d{2}-\d{2}$/.test(d)
      return json(await syncSchedule(season, isDate(body.from) ? body.from : undefined, isDate(body.to) ? body.to : undefined))
    }
    if (mode === 'settle') return json({ settled: await settle() })
    if (mode === 'leagues') return json(await listLeagues(season))
    return json({ error: `modo inválido: ${mode}` }, 400)
  } catch (e) {
    console.error(e)
    return json({ error: e instanceof Error ? e.message : String(e) }, 500)
  }
})