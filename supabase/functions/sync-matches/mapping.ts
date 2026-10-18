// Funções puras (sem Deno, sem rede): traduzem o formato da API-Football
// para a linha da tabela public.matches e decidem se algo mudou.

export type ApiFixture = {
  fixture: { id: number; date: string; status: { short: string; elapsed: number | null } }
  league: { id: number; season: number; round: string }
  teams: { home: { name: string; logo: string | null }; away: { name: string; logo: string | null } }
  goals: { home: number | null; away: number | null }
  score?: { fulltime?: { home: number | null; away: number | null } }
}

export type MatchStatus = 'scheduled' | 'live' | 'finished' | 'void'

export type MatchRow = {
  api_fixture_id: number
  competition_id: number
  season: number
  round: string
  home_team: string
  away_team: string
  home_logo: string | null
  away_logo: string | null
  kickoff_at: string
  status: MatchStatus
  minute: number | null
  home_score: number | null
  away_score: number | null
  updated_at: string
}

const LIVE = new Set(['1H', 'HT', '2H', 'ET', 'BT', 'P', 'SUSP', 'INT', 'LIVE'])
const FINISHED = new Set(['FT', 'AET', 'PEN'])
const VOID = new Set(['PST', 'CANC', 'ABD', 'AWD', 'WO'])

export function mapStatus(short: string): MatchStatus {
  if (LIVE.has(short)) return 'live'
  if (FINISHED.has(short)) return 'finished'
  if (VOID.has(short)) return 'void'
  return 'scheduled' // NS, TBD e qualquer código desconhecido
}

export const isFinalStatus = (s: MatchStatus) => s === 'finished' || s === 'void'

export function fixtureToRow(f: ApiFixture, competitionId: number): MatchRow {
  const short = f.fixture.status.short
  const status = mapStatus(short)
  // Se um dia houver prorrogação/pênaltis, o palpite vale para os 90 minutos.
  const useFullTime = (short === 'AET' || short === 'PEN') && f.score?.fulltime
  const home = useFullTime ? f.score!.fulltime!.home : f.goals.home
  const away = useFullTime ? f.score!.fulltime!.away : f.goals.away
  const hasScore = status === 'live' || status === 'finished'

  return {
    api_fixture_id: f.fixture.id,
    competition_id: competitionId,
    season: f.league.season,
    round: f.league.round,
    home_team: f.teams.home.name,
    away_team: f.teams.away.name,
    home_logo: f.teams.home.logo,
    away_logo: f.teams.away.logo,
    kickoff_at: f.fixture.date,
    status,
    minute: status === 'live' ? f.fixture.status.elapsed : null,
    home_score: hasScore ? (home ?? 0) : null,
    away_score: hasScore ? (away ?? 0) : null,
    updated_at: new Date().toISOString(),
  }
}

type Current = {
  status: string
  minute: number | null
  home_score: number | null
  away_score: number | null
  kickoff_at: string
}

// Só grava no banco (e dispara Realtime) quando algo visível mudou.
export function hasChanged(current: Current, row: MatchRow): boolean {
  return (
    current.status !== row.status ||
    current.minute !== row.minute ||
    current.home_score !== row.home_score ||
    current.away_score !== row.away_score ||
    new Date(current.kickoff_at).getTime() !== new Date(row.kickoff_at).getTime()
  )
}

// Data "YYYY-MM-DD" no horário de Brasília, com deslocamento em dias.
export function brtDate(offsetDays = 0, now = Date.now()): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Sao_Paulo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date(now + offsetDays * 86400000))
}