const TZ = 'America/Sao_Paulo' // Brasília (UTC-3, sem horário de verão)

export function dayKeyOf(date) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(date) // "2026-10-16"
}

export function addDays(key, n) {
  const base = new Date(`${key}T12:00:00-03:00`)
  return dayKeyOf(new Date(base.getTime() + n * 86400000))
}

export function dayRange(key) {
  const start = new Date(`${key}T00:00:00-03:00`)
  return { start: start.toISOString(), end: new Date(start.getTime() + 86400000).toISOString() }
}

export function formatTime(iso) {
  return new Intl.DateTimeFormat('pt-BR', { timeZone: TZ, hour: '2-digit', minute: '2-digit' }).format(new Date(iso))
}

export function formatDateTime(iso) {
  return new Intl.DateTimeFormat('pt-BR', {
    timeZone: TZ, day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit',
  }).format(new Date(iso))
}

export function formatDayChip(key) {
  const d = new Date(`${key}T12:00:00-03:00`)
  const weekday = new Intl.DateTimeFormat('pt-BR', { timeZone: TZ, weekday: 'short' }).format(d).replace('.', '')
  const date = new Intl.DateTimeFormat('pt-BR', { timeZone: TZ, day: '2-digit', month: '2-digit' }).format(d)
  return { weekday, date }
}

export function formatRound(round) {
  const n = round?.match(/(\d+)\s*$/)
  return n ? `Rodada ${n[1]}` : round || ''
}

export function isLocked(match, nowMs) {
  return match.status !== 'scheduled' || new Date(match.kickoff_at).getTime() <= nowMs
}

// ---- Status EFETIVO ----
// O banco só vira 'live' quando a sincronização roda (e o plano gratuito da API atrasa).
// Para o app nunca ficar "parado", um jogo 'scheduled' cujo horário já passou é tratado
// como 'live' na tela, com o cronômetro estimado. O banco continua sendo a fonte da verdade
// para placar e resultado final: quando ele atualizar, o dado real substitui este.
export const LIVE_LOOKBACK_MS = 6 * 3600000 // aba "Ao vivo": ignora jogos "agendados" há mais de 6h

export function isOverdue(match, nowMs) {
  return match.status === 'scheduled' && new Date(match.kickoff_at).getTime() <= nowMs
}

export function withLiveStatus(match, nowMs) {
  return isOverdue(match, nowMs) ? { ...match, status: 'live', derivedLive: true } : match
}

const ORDER = { live: 0, scheduled: 1, finished: 2, void: 3 }
export function sortMatches(list) {
  return [...list].sort(
    (a, b) =>
      (ORDER[a.status] ?? 9) - (ORDER[b.status] ?? 9) ||
      new Date(a.kickoff_at) - new Date(b.kickoff_at),
  )
}

// Aplica o status efetivo em uma lista e reordena (ao vivo primeiro)
export function applyLiveStatus(list, nowMs) {
  return sortMatches(list.map((m) => withLiveStatus(m, nowMs)))
}

export function resultLabel(result, match) {
  if (result === 'home') return `${match.home_team} vence`
  if (result === 'away') return `${match.away_team} vence`
  return 'Empate'
}

// ---- Cronômetro ESTIMADO (o plano gratuito da API não informa minuto nem intervalo) ----
// 1º tempo 0–45' (+3' de acréscimo), intervalo ~15', 2º tempo a partir de ~63' de relógio.
export function estimateClock(match, nowMs) {
  const el = (nowMs - new Date(match.kickoff_at).getTime()) / 60000
  if (el < 0) return null
  if (el < 45) return { phase: 'play', label: `${Math.floor(el) + 1}'` }
  if (el < 48) return { phase: 'play', label: "45+'" }
  if (el < 63) return { phase: 'break', label: 'Intervalo' }
  const minute = 46 + Math.floor(el - 63)
  if (minute <= 90) return { phase: 'play', label: `${minute}'` }
  if (el < 112) return { phase: 'play', label: "90+'" }
  return { phase: 'wait', label: 'Aguardando resultado' }
}

// "em 45 min", "em 3h 20min"; null quando falta mais de 24h.
export function formatCountdown(msUntil) {
  if (msUntil <= 0) return 'Começando agora'
  const mins = Math.ceil(msUntil / 60000)
  if (mins < 60) return `Começa em ${mins} min`
  const h = Math.floor(mins / 60)
  if (h >= 24) return null
  const rem = mins % 60
  return `Começa em ${h}h${rem ? ` ${rem}min` : ''}`
}
