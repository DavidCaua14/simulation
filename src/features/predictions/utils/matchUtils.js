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

const ORDER = { live: 0, scheduled: 1, finished: 2, void: 3 }
export function sortMatches(list) {
  return [...list].sort(
    (a, b) =>
      (ORDER[a.status] ?? 9) - (ORDER[b.status] ?? 9) ||
      new Date(a.kickoff_at) - new Date(b.kickoff_at),
  )
}

export function resultLabel(result, match) {
  if (result === 'home') return `${match.home_team} vence`
  if (result === 'away') return `${match.away_team} vence`
  return 'Empate'
}
