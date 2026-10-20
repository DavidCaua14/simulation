// Edge Function: sincroniza jogos (football-data.org, plano GRATUITO) com public.matches
// e liquida os bilhetes. O app NUNCA chama a API: ele só lê o banco (Supabase Realtime).
//
// Ciclo de vida de um jogo (plano gratuito: sem ao vivo, resultado chega atrasado):
//   scheduled -> live      : o horário do jogo passou (só banco, ZERO chamadas à API)
//   live      -> finished  : 105 min após o início, consulta a API (a cada 3 min; a cada 30 min
//                            se passar de 6h) até aparecer o resultado. Grava o placar e liquida.
//
// Modos (corpo JSON): { "mode": "live" | "schedule" | "settle" | "status" | "leagues", "force": true }
//   live      – chamado a cada minuto pelo pg_cron (quase sempre sem custo de API)
//   schedule  – 1x por dia; aceita "from" e "to" (YYYY-MM-DD, UTC)
//   settle    – força a liquidação dos bilhetes
//   status    – diagnóstico: jogos por status, jogos "presos" e última execução
//   leagues   – lista as competições liberadas no seu plano
//   force:true (modo live) ignora o intervalo entre consultas
import { createClient } from 'npm:@supabase/supabase-js@2'
import {
  fixtureToRow,
  hasTeams,
  isFinalStatus,
  pollIntervalMin,
  utcDate,
  type FdMatch,
  type MatchRow,
} from './mapping.ts'

const API_BASE = 'https://api.football-data.org/v4'
const API_KEY = Deno.env.get('FOOTBALL_DATA_KEY') ?? ''
const CRON_SECRET = Deno.env.get('CRON_SECRET') ?? ''

const EXPECTED_END_MIN = 105 // minutos após o início em que o jogo costuma acabar
const LOOKBACK_MS = 7 * 86400_000 // ignora jogos "presos" há mais de 7 dias
const MAX_RANGE_DAYS = 9 // a football-data.org aceita no máximo 10 dias entre dateFrom e dateTo

const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
  auth: { persistSession: false },
})

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body, null, 2), { status, headers: { 'Content-Type': 'application/json' } })

class ApiError extends Error {
  constructor(public status: number, detail: string) {
    super(`football-data.org HTTP ${status}: ${detail}`)
  }
}

async function apiGet(path: string, params: Record<string, string | number> = {}) {
  const url = new URL(API_BASE + path)
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, String(v))
  const res = await fetch(url, { headers: { 'X-Auth-Token': API_KEY } })
  if (!res.ok) throw new ApiError(res.status, (await res.text().catch(() => '')).slice(0, 300))
  return await res.json()
}

const errMsg = (e: unknown) => (e instanceof Error ? e.message : String(e))

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

// ---- Controle de frequência (tabela sync_state; se não existir, consulta sempre) ----
async function lastRunMs(key: string): Promise<number> {
  const { data } = await db.from('sync_state').select('last_run_at').eq('key', key).maybeSingle()
  return data?.last_run_at ? Date.parse(data.last_run_at) : 0
}
async function markRun(key: string, status: string, detail: unknown = null) {
  await db
    .from('sync_state')
    .upsert({ key, last_run_at: new Date().toISOString(), last_status: status, detail })
    .then(() => {}, () => {})
}

// ---- Agenda: 1 chamada por competição ativa ------------------------------
async function syncSchedule(fromDate?: string, toDate?: string) {
  const { data: comps, error } = await db.from('competitions').select('id, name, api_league_id').eq('active', true)
  if (error) throw new Error(error.message)

  const dateFrom = fromDate ?? utcDate(-1)
  const dateTo = toDate ?? utcDate(7)
  const now = Date.now()
  let upserted = 0
  const errors: string[] = []

  for (const c of comps ?? []) {
    try {
      const body = await apiGet(`/competitions/${c.api_league_id}/matches`, { dateFrom, dateTo })
      const matches = ((body.matches ?? []) as FdMatch[]).filter(hasTeams)
      let rows = matches.map((m) => fixtureToRow(m, c.id, now))

      // Nunca desfaz um jogo já encerrado (a API gratuita pode estar atrasada).
      const ids = rows.map((r) => r.api_fixture_id)
      if (ids.length) {
        const { data: done } = await db.from('matches').select('api_fixture_id').in('api_fixture_id', ids).eq('status', 'finished')
        const doneIds = new Set((done ?? []).map((d) => d.api_fixture_id))
        rows = rows.filter((r) => !doneIds.has(r.api_fixture_id))
      }
      await upsertMatches(rows)
      upserted += rows.length
    } catch (e) {
      // uma competição com problema (ex.: HTTP 403, fora do plano) não pode travar as outras
      errors.push(`${c.name} (${c.api_league_id}): ${errMsg(e)}`)
      if (e instanceof ApiError && e.status === 429) break
    }
  }
  const settled = await settle().catch((e) => `erro: ${errMsg(e)}`)
  return { dateFrom, dateTo, upserted, settled, errors }
}

// ---- Começou / terminou ---------------------------------------------------
async function syncLive(force: boolean) {
  const now = Date.now()
  const nowIso = new Date(now).toISOString()
  const since = new Date(now - LOOKBACK_MS).toISOString()

  // 1) COMEÇOU: horário passou -> "em andamento". Só banco, sem API.
  const { data: started, error: e1 } = await db
    .from('matches')
    .update({ status: 'live', updated_at: nowIso })
    .eq('status', 'scheduled')
    .lte('kickoff_at', nowIso)
    .gte('kickoff_at', since)
    .select('id')
  if (e1) throw new Error(e1.message)

  // 2) TERMINOU?: jogos "em andamento" que já passaram do tempo esperado de duração.
  const { data: pending, error: e2 } = await db
    .from('matches')
    .select('api_fixture_id, competition_id, kickoff_at')
    .eq('status', 'live')
    .lte('kickoff_at', new Date(now - EXPECTED_END_MIN * 60_000).toISOString())
    .gte('kickoff_at', since)
  if (e2) throw new Error(e2.message)

  const report: Record<string, unknown> = { started: started?.length ?? 0, pending: pending?.length ?? 0 }
  const perComp: Record<string, unknown>[] = []

  if (pending?.length) {
    const { data: comps, error: e3 } = await db.from('competitions').select('id, name, api_league_id')
    if (e3) throw new Error(e3.message)
    const compById = new Map((comps ?? []).map((c) => [c.id as number, c]))

    const byComp = new Map<number, typeof pending>()
    for (const p of pending) byComp.set(p.competition_id, [...(byComp.get(p.competition_id) ?? []), p])

    for (const [compId, list] of byComp) {
      const comp = compById.get(compId)
      const label = comp ? `${comp.name}` : `competição ${compId}`
      if (!comp?.api_league_id) {
        perComp.push({ comp: label, skipped: 'competição sem api_league_id' })
        continue
      }

      const times = list.map((p) => Date.parse(p.kickoff_at))
      const key = `live:${compId}`
      const every = pollIntervalMin(Math.max(...times), now)
      const waitedMin = (now - (await lastRunMs(key))) / 60_000
      if (!force && waitedMin < every - 0.5) {
        perComp.push({ comp: label, pending: list.length, skipped: `próxima consulta em ~${Math.ceil(every - waitedMin)} min` })
        continue
      }

      // intervalo de datas em UTC que cobre todos os jogos pendentes (máx. 10 dias)
      const dateTo = utcDate(1, Math.max(...times))
      const minFrom = utcDate(0, Math.min(...times))
      const lowest = utcDate(-MAX_RANGE_DAYS, Date.parse(`${dateTo}T00:00:00Z`))
      const dateFrom = minFrom < lowest ? lowest : minFrom

      try {
        const body = await apiGet(`/competitions/${comp.api_league_id}/matches`, { dateFrom, dateTo })
        const wanted = new Set(list.map((p) => p.api_fixture_id as number))
        const rows: MatchRow[] = []
        let stillPlaying = 0
        for (const m of (body.matches ?? []) as FdMatch[]) {
          if (!wanted.has(m.id) || !hasTeams(m)) continue
          const row = fixtureToRow(m, compId, now)
          // grava só quando terminou (ou foi anulado) ou quando o jogo foi REMARCADO para o futuro
          if (isFinalStatus(row.status) || row.status === 'scheduled') rows.push(row)
          else stillPlaying++
        }
        await upsertMatches(rows)
        await markRun(key, 'ok')
        perComp.push({
          comp: label,
          pending: list.length,
          apiReturned: (body.matches ?? []).length,
          saved: rows.length,
          stillWaiting: list.length - rows.length,
          apiStillPlaying: stillPlaying,
        })
      } catch (e) {
        await markRun(key, `erro: ${errMsg(e)}`)
        perComp.push({ comp: label, error: errMsg(e) }) // só esta competição falha; as outras seguem
        if (e instanceof ApiError && e.status === 429) {
          perComp.push({ stopped: 'limite de requisições da API atingido (429); tenta de novo no próximo ciclo' })
          break
        }
      }
    }
  }
  report.competitions = perComp

  // 3) Liquida bilhetes SEMPRE (só banco, barato): cobre também resultados gravados pelo "schedule".
  report.settled = await settle().catch((e) => `erro: ${errMsg(e)}`)
  await markRun('live:last', 'ok', report)
  return report
}

// Diagnóstico rápido, sem gastar a API.
async function status() {
  const now = Date.now()
  const { data: all } = await db.from('matches').select('status, kickoff_at').gte('kickoff_at', new Date(now - LOOKBACK_MS).toISOString())
  const counts: Record<string, number> = {}
  for (const m of all ?? []) counts[m.status] = (counts[m.status] ?? 0) + 1
  const { data: stuck } = await db
    .from('matches')
    .select('id, api_fixture_id, home_team, away_team, kickoff_at, status, competition_id')
    .in('status', ['scheduled', 'live'])
    .lte('kickoff_at', new Date(now - EXPECTED_END_MIN * 60_000).toISOString())
    .gte('kickoff_at', new Date(now - LOOKBACK_MS).toISOString())
    .order('kickoff_at')
  const { data: state } = await db.from('sync_state').select('*').order('key')
  return { now: new Date(now).toISOString(), last7days: counts, waitingForResult: stuck ?? [], syncState: state ?? [] }
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

  let body: { mode?: string; from?: string; to?: string; force?: boolean } = {}
  try {
    body = await req.json()
  } catch {
    /* corpo vazio = modo live */
  }
  const mode = body.mode ?? 'live'

  try {
    if (mode === 'live') return json(await syncLive(body.force === true))
    if (mode === 'schedule') {
      const isDate = (d?: string) => !!d && /^\d{4}-\d{2}-\d{2}$/.test(d)
      return json(await syncSchedule(isDate(body.from) ? body.from : undefined, isDate(body.to) ? body.to : undefined))
    }
    if (mode === 'settle') return json({ settled: await settle() })
    if (mode === 'status') return json(await status())
    if (mode === 'leagues') return json(await listCompetitions())
    return json({ error: `modo inválido: ${mode}` }, 400)
  } catch (e) {
    console.error(e)
    return json({ error: errMsg(e) }, 500)
  }
})
