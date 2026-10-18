// Edge Function: sincroniza jogos (Brasileirão Série A, Champions League, La Liga...)
// da football-data.org (plano GRATUITO) com a tabela public.matches e liquida os bilhetes.
// O app NUNCA chama a API: ele só escuta a tabela via Supabase Realtime.
//
// Como funciona com o plano gratuito (placar atrasado, sem ao vivo):
//   pré-jogo  : agenda diária traz os jogos (modo "schedule")
//   começou   : quando o horário passa, o jogo vira "em andamento" SEM chamar a API
//   terminou  : ~105 min depois do início, consulta a API a cada 3 min até sair o resultado;
//               então grava o placar e liquida os bilhetes (modo "live")
//
// Modos (corpo JSON): { "mode": "live" | "schedule" | "settle" | "leagues" }
//   live      – chamado a cada minuto pelo pg_cron (quase sempre sem custo de API)
//   schedule  – 1x por dia; aceita também "from" e "to" (YYYY-MM-DD, UTC)
//   settle    – força a liquidação dos bilhetes
//   leagues   – lista as competições liberadas no seu plano (confere BSA, CL, PD)
import { createClient } from 'npm:@supabase/supabase-js@2'
import { fixtureToRow, hasTeams, isFinalStatus, utcDate, type FdMatch, type MatchRow } from './mapping.ts'

const API_BASE = 'https://api.football-data.org/v4'
const API_KEY = Deno.env.get('FOOTBALL_DATA_KEY') ?? ''
const CRON_SECRET = Deno.env.get('CRON_SECRET') ?? ''

const EXPECTED_END_MIN = 105 // minutos após o início em que o jogo costuma acabar
const POLL_EVERY_MIN = 3 // intervalo entre consultas à API enquanto espera o resultado
const LOOKBACK_MS = 3 * 86400_000 // ignora jogos "presos" há mais de 3 dias

const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
  auth: { persistSession: false },
})

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })

async function apiGet(path: string, params: Record<string, string | number> = {}) {
  const url = new URL(API_BASE + path)
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, String(v))
  const res = await fetch(url, { headers: { 'X-Auth-Token': API_KEY } })
  if (!res.ok) {
    const detail = (await res.text().catch(() => '')).slice(0, 300)
    throw new Error(`football-data.org HTTP ${res.status}: ${detail}`)
  }
  return await res.json()
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

// ---- Agenda: 1 chamada por competição ativa ------------------------------
async function syncSchedule(fromDate?: string, toDate?: string) {
  const { data: comps, error } = await db.from('competitions').select('id, api_league_id').eq('active', true)
  if (error) throw new Error(error.message)

  const dateFrom = fromDate ?? utcDate(-1)
  const dateTo = toDate ?? utcDate(7)
  const now = Date.now()
  let upserted = 0

  for (const c of comps ?? []) {
    const body = await apiGet(`/competitions/${c.api_league_id}/matches`, { dateFrom, dateTo })
    const matches = ((body.matches ?? []) as FdMatch[]).filter(hasTeams)
    let rows = matches.map((m) => fixtureToRow(m, c.id, now))

    // Nunca desfaz um jogo que já foi encerrado (a API gratuita pode estar atrasada).
    const ids = rows.map((r) => r.api_fixture_id)
    if (ids.length) {
      const { data: done } = await db.from('matches').select('api_fixture_id').in('api_fixture_id', ids).eq('status', 'finished')
      const doneIds = new Set((done ?? []).map((d) => d.api_fixture_id))
      rows = rows.filter((r) => !doneIds.has(r.api_fixture_id))
    }
    await upsertMatches(rows)
    upserted += rows.length
  }
  const settled = await settle() // rede de segurança
  return { dateFrom, dateTo, upserted, settled }
}

// ---- Começou / terminou ---------------------------------------------------
async function syncLive() {
  const now = Date.now()
  const nowIso = new Date(now).toISOString()

  // 1) COMEÇOU: horário passou -> "em andamento". Só banco, sem API.
  const { data: started, error: e1 } = await db
    .from('matches')
    .update({ status: 'live', updated_at: nowIso })
    .eq('status', 'scheduled')
    .lte('kickoff_at', nowIso)
    .gte('kickoff_at', new Date(now - LOOKBACK_MS).toISOString())
    .select('id')
  if (e1) throw new Error(e1.message)

  // 2) TERMINOU: jogos "em andamento" que já passaram do tempo esperado de duração.
  const { data: pending, error: e2 } = await db
    .from('matches')
    .select('api_fixture_id, competition_id, kickoff_at')
    .eq('status', 'live')
    .lte('kickoff_at', new Date(now - EXPECTED_END_MIN * 60_000).toISOString())
    .gte('kickoff_at', new Date(now - LOOKBACK_MS).toISOString())
  if (e2) throw new Error(e2.message)

  const base = { started: started?.length ?? 0, pending: pending?.length ?? 0 }
  if (!pending?.length) return base

  // Evita muitas requisições: só consulta a API a cada POLL_EVERY_MIN minutos.
  if (new Date(now).getUTCMinutes() % POLL_EVERY_MIN !== 0) return { ...base, api: 'aguardando próxima janela' }

  const { data: comps, error: e3 } = await db.from('competitions').select('id, api_league_id')
  if (e3) throw new Error(e3.message)
  const apiIdByComp = new Map((comps ?? []).map((c) => [c.id as number, c.api_league_id as number]))

  const byComp = new Map<number, typeof pending>()
  for (const p of pending) byComp.set(p.competition_id, [...(byComp.get(p.competition_id) ?? []), p])

  let apiCalls = 0
  const finals: MatchRow[] = []
  for (const [compId, list] of byComp) {
    const apiId = apiIdByComp.get(compId)
    if (!apiId) continue
    const times = list.map((p) => Date.parse(p.kickoff_at))
    const dateFrom = utcDate(0, Math.min(...times))
    const dateTo = utcDate(1, Math.max(...times))
    const body = await apiGet(`/competitions/${apiId}/matches`, { dateFrom, dateTo })
    apiCalls++
    const wanted = new Set(list.map((p) => p.api_fixture_id as number))
    for (const m of (body.matches ?? []) as FdMatch[]) {
      if (!wanted.has(m.id) || !hasTeams(m)) continue
      const row = fixtureToRow(m, compId, now)
      if (isFinalStatus(row.status)) finals.push(row) // só grava quando terminou (ou foi anulado)
    }
  }

  await upsertMatches(finals)
  const settled = finals.length ? await settle() : null
  return { ...base, apiCalls, finished: finals.length, settled }
}

async function listCompetitions() {
  const body = await apiGet('/competitions')
  return (body.competitions ?? []).map((c: any) => ({ id: c.id, code: c.code, name: c.name }))
}

Deno.serve(async (req) => {
  if (!CRON_SECRET || req.headers.get('x-cron-secret') !== CRON_SECRET) {
    return json({ error: 'unauthorized' }, 401)
  }
  if (!API_KEY) return json({ error: 'FOOTBALL_DATA_KEY não configurada' }, 500)

  let body: { mode?: string; from?: string; to?: string } = {}
  try {
    body = await req.json()
  } catch {
    /* corpo vazio = modo live */
  }
  const mode = body.mode ?? 'live'

  try {
    if (mode === 'live') return json(await syncLive())
    if (mode === 'schedule') {
      const isDate = (d?: string) => !!d && /^\d{4}-\d{2}-\d{2}$/.test(d)
      return json(await syncSchedule(isDate(body.from) ? body.from : undefined, isDate(body.to) ? body.to : undefined))
    }
    if (mode === 'settle') return json({ settled: await settle() })
    if (mode === 'leagues') return json(await listCompetitions())
    return json({ error: `modo inválido: ${mode}` }, 400)
  } catch (e) {
    console.error(e)
    return json({ error: e instanceof Error ? e.message : String(e) }, 500)
  }
})