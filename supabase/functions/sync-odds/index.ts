// Edge Function: busca odds REAIS na The Odds API e grava nos jogos que ainda estão
// sem odds reais. Roda a cada poucas horas (pg_cron), mas só gasta crédito quando há jogo
// nos próximos dias sem odd real E o campeonato não foi consultado há pouco.
//
// Segredos (supabase secrets set): ODDS_API_KEY, CRON_SECRET
// Opcionais: ODDS_HORIZON_DAYS (4), ODDS_MIN_INTERVAL_HOURS (12), ODDS_CREDIT_RESERVE (40)
import { createClient } from 'npm:@supabase/supabase-js@2'
import { SPORT_BY_FD_LEAGUE, buildOddsUrl, consensus1x2, type OddsEvent } from './oddsApi.ts'
import { matchEvents, type DbMatch } from './matching.ts'

const HORIZON_DAYS = Number(Deno.env.get('ODDS_HORIZON_DAYS') ?? 4)
const MIN_INTERVAL_H = Number(Deno.env.get('ODDS_MIN_INTERVAL_HOURS') ?? 12)
const RESERVE = Number(Deno.env.get('ODDS_CREDIT_RESERVE') ?? 40)

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body, null, 2), { status, headers: { 'Content-Type': 'application/json' } })

Deno.serve(async (req) => {
  const secret = Deno.env.get('CRON_SECRET')
  if (!secret || req.headers.get('x-cron-secret') !== secret) return json({ error: 'unauthorized' }, 401)
  const apiKey = Deno.env.get('ODDS_API_KEY')
  if (!apiKey) return json({ error: 'ODDS_API_KEY não configurada' }, 500)

  const force = new URL(req.url).searchParams.get('force') === '1' // ignora o intervalo (gasta crédito)
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)

  const now = new Date()
  const until = new Date(now.getTime() + HORIZON_DAYS * 86400000)

  // Jogos futuros, ainda sem odds reais travadas
  const { data: rows, error } = await db
    .from('matches')
    .select('id, home_team, away_team, kickoff_at, competitions!inner(api_league_id)')
    .eq('status', 'scheduled')
    .gt('kickoff_at', now.toISOString())
    .lte('kickoff_at', until.toISOString())
    .is('odds_locked_at', null)
  if (error) return json({ error: error.message }, 500)

  const bySport = new Map<string, DbMatch[]>()
  const skippedLeagues = new Set<number>()
  for (const r of rows ?? []) {
    const comp = Array.isArray(r.competitions) ? r.competitions[0] : r.competitions
    const sport = SPORT_BY_FD_LEAGUE[comp?.api_league_id as number]
    if (!sport) {
      skippedLeagues.add(comp?.api_league_id)
      continue
    }
    bySport.set(sport, [...(bySport.get(sport) ?? []), r as DbMatch])
  }

  const { data: logs } = await db.from('odds_fetch_log').select('sport_key, last_fetched_at')
  const lastFetch = new Map((logs ?? []).map((l) => [l.sport_key, new Date(l.last_fetched_at).getTime()]))

  const report: Record<string, unknown>[] = []
  let remaining: number | null = null

  for (const [sport, matches] of bySport) {
    const last = lastFetch.get(sport) ?? 0
    if (!force && now.getTime() - last < MIN_INTERVAL_H * 3600000) {
      report.push({ sport, skipped: 'consultado há pouco', pending: matches.length })
      continue
    }
    if (remaining != null && remaining <= RESERVE) {
      report.push({ sport, skipped: `reserva de créditos (${remaining} restantes)` })
      continue
    }

    const res = await fetch(buildOddsUrl(sport, apiKey))
    const hdr = res.headers.get('x-requests-remaining')
    remaining = hdr != null ? Number(hdr) : remaining
    const status = String(res.status)

    if (res.status === 401 || res.status === 429) {
      report.push({ sport, stopped: `HTTP ${res.status} (chave inválida, sem créditos ou limite de taxa)` })
      break
    }
    if (!res.ok) {
      await db.from('odds_fetch_log').upsert({ sport_key: sport, last_fetched_at: now.toISOString(), last_status: status, credits_remaining: remaining })
      report.push({ sport, error: `HTTP ${res.status}` }) // 404/422: chave de esporte inexistente na sua conta
      continue
    }

    const events = (await res.json()) as OddsEvent[]
    const pairs = matchEvents(matches, events)
    let updated = 0
    for (const { match, event } of pairs) {
      const o = consensus1x2(event)
      if (!o) continue
      const { error: upErr } = await db
        .from('matches')
        .update({
          odds_home: o.home,
          odds_draw: o.draw,
          odds_away: o.away,
          odds_source: 'api',
          odds_locked_at: new Date().toISOString(),
          odds_event_id: event.id,
        })
        .eq('id', match.id)
        .is('odds_locked_at', null)
      if (!upErr) updated++
    }
    await db.from('odds_fetch_log').upsert({ sport_key: sport, last_fetched_at: now.toISOString(), last_status: status, credits_remaining: remaining })

    const unmatched = matches.filter((m) => !pairs.some((p) => p.match.id === m.id)).map((m) => `${m.home_team} x ${m.away_team}`)
    report.push({ sport, events: events.length, candidates: matches.length, updated, unmatched })
  }

  return json({ ok: true, creditsRemaining: remaining, leaguesWithoutMapping: [...skippedLeagues], report })
})
