// Funções puras (sem Deno, sem rede): traduzem o formato da football-data.org (v4)
// para a linha da tabela public.matches e decidem se algo mudou.

export type FdTeam = { id?: number | null; name: string | null; shortName: string | null; crest: string | null }
export type FdScore = { home: number | null; away: number | null }

export type FdMatch = {
  id: number
  utcDate: string
  status: string
  matchday: number | null
  stage?: string | null
  season?: { startDate?: string | null } | null
  competition?: { id: number; emblem?: string | null } | null
  homeTeam: FdTeam
  awayTeam: FdTeam
  score: { duration?: string | null; fullTime: FdScore; regularTime?: FdScore | null }
}

export type MatchStatus = 'scheduled' | 'live' | 'finished' | 'void'

export type MatchRow = {
  api_fixture_id: number // aqui guardamos o id do jogo na football-data.org
  competition_id: number
  season: number
  round: string | null
  home_team: string
  away_team: string
  home_logo: string | null
  away_logo: string | null
  home_team_id: number | null
  away_team_id: number | null
  kickoff_at: string
  status: MatchStatus
  minute: number | null
  home_score: number | null
  away_score: number | null
  updated_at: string
}

const LIVE = new Set(['IN_PLAY', 'PAUSED', 'LIVE', 'SUSPENDED', 'EXTRA_TIME', 'PENALTY_SHOOTOUT'])
const FINISHED = new Set(['FINISHED'])
const VOID = new Set(['POSTPONED', 'CANCELLED', 'AWARDED'])

export function mapStatus(status: string): MatchStatus {
  if (LIVE.has(status)) return 'live'
  if (FINISHED.has(status)) return 'finished'
  if (VOID.has(status)) return 'void'
  return 'scheduled' // SCHEDULED, TIMED e qualquer valor desconhecido
}

export const isFinalStatus = (s: MatchStatus) => s === 'finished' || s === 'void'

const STAGES: Record<string, string> = {
  PLAYOFFS: 'Playoffs',
  LAST_16: 'Oitavas de final',
  ROUND_OF_16: 'Oitavas de final',
  QUARTER_FINALS: 'Quartas de final',
  SEMI_FINALS: 'Semifinal',
  FINAL: 'Final',
}

export function roundLabel(m: FdMatch): string | null {
  const stage = m.stage ?? ''
  if ((stage === 'REGULAR_SEASON' || stage === 'LEAGUE_STAGE' || !stage) && m.matchday) {
    return `Rodada ${m.matchday}`
  }
  return STAGES[stage] ?? (stage ? stage.replaceAll('_', ' ') : m.matchday ? `Rodada ${m.matchday}` : null)
}

// Jogos com times ainda indefinidos (mata-mata futuro) vêm sem nome: não dá para palpitar.
export const hasTeams = (m: FdMatch) => !!(m.homeTeam?.name && m.awayTeam?.name)

export function fixtureToRow(m: FdMatch, competitionId: number, nowMs = Date.now()): MatchRow {
  let status = mapStatus(m.status)
  // O plano gratuito entrega dados atrasados: se o horário do jogo já passou e a API
  // ainda diz "agendado", tratamos como "em andamento" (sem placar) até sair o resultado.
  if (status === 'scheduled' && Date.parse(m.utcDate) <= nowMs) status = 'live'

  // O palpite vale para os 90 minutos: se houver prorrogação, usa o tempo regulamentar.
  const regular = m.score.regularTime ?? m.score.fullTime
  const finished = status === 'finished'

  return {
    api_fixture_id: m.id,
    competition_id: competitionId,
    season: Number((m.season?.startDate ?? m.utcDate).slice(0, 4)),
    round: roundLabel(m),
    home_team: (m.homeTeam.shortName || m.homeTeam.name) as string,
    away_team: (m.awayTeam.shortName || m.awayTeam.name) as string,
    home_logo: m.homeTeam.crest,
    away_logo: m.awayTeam.crest,
    home_team_id: m.homeTeam.id ?? null,
    away_team_id: m.awayTeam.id ?? null,
    kickoff_at: m.utcDate,
    status,
    minute: null, // sem minuto/placar ao vivo no plano gratuito: só o resultado final
    home_score: finished ? (regular.home ?? 0) : null,
    away_score: finished ? (regular.away ?? 0) : null,
    updated_at: new Date(nowMs).toISOString(),
  }
}

type Current = {
  status: string
  minute: number | null
  home_score: number | null
  away_score: number | null
  kickoff_at: string
}

export function hasChanged(current: Current, row: MatchRow): boolean {
  return (
    current.status !== row.status ||
    current.minute !== row.minute ||
    current.home_score !== row.home_score ||
    current.away_score !== row.away_score ||
    new Date(current.kickoff_at).getTime() !== new Date(row.kickoff_at).getTime()
  )
}

// Datas "YYYY-MM-DD" em UTC (é o que a football-data.org espera em dateFrom/dateTo).
export function utcDate(offsetDays = 0, nowMs = Date.now()): string {
  return new Date(nowMs + offsetDays * 86400000).toISOString().slice(0, 10)
}

// Data "YYYY-MM-DD" no horário de Brasília.
export function brtDate(offsetDays = 0, now = Date.now()): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Sao_Paulo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date(now + offsetDays * 86400000))
}