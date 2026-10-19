// Funções puras: casam os jogos do SEU banco (nomes da football-data.org) com os eventos da
// The Odds API (nomes diferentes: "Man City" x "Manchester City", "Atlético MG" x "Atletico Mineiro").
// Critério: horário de início próximo + nomes parecidos nos DOIS times.

import type { OddsEvent } from './oddsApi.ts'

export type DbMatch = { id: number; home_team: string; away_team: string; kickoff_at: string }

const NOISE = new Set([
  'fc', 'cf', 'sc', 'ac', 'afc', 'as', 'ss', 'us', 'ud', 'cd', 'rc', 'rcd', 'ca', 'ec', 'cr', 'sk', 'fk', 'sv',
  'de', 'da', 'do', 'the', 'club', 'clube', 'calcio', 'football',
  'mg', 'pr', 'rj', 'sp', 'rs', 'ba', 'go', 'ce', 'pe', // sufixos de estado nos clubes brasileiros
])

// Apelidos que nenhuma regra genérica resolve.
const ALIASES: Record<string, string> = {
  psg: 'paris saint germain',
  'man city': 'manchester city',
  'man united': 'manchester united',
  'man utd': 'manchester united',
  spurs: 'tottenham hotspur',
  wolves: 'wolverhampton wanderers',
  inter: 'internazionale',
  athletico: 'atletico',
  bayern: 'bayern munich',
  'bayern munchen': 'bayern munich',
  gladbach: 'borussia monchengladbach',
  leverkusen: 'bayer leverkusen',
  sporting: 'sporting cp',
  'sporting lisbon': 'sporting cp',
  'atletico madrid': 'atletico madrid',
  'vasco da gama': 'vasco',
  bragantino: 'rb bragantino',
}

export function normalize(name: string): string {
  const base = name
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9 ]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
  const aliased = ALIASES[base] ?? base
  const tokens = aliased.split(' ').filter((t) => t && !NOISE.has(t))
  return (tokens.length ? tokens : aliased.split(' ')).join(' ')
}

function bigrams(s: string): string[] {
  const t = s.replace(/ /g, '')
  const out: string[] = []
  for (let i = 0; i < t.length - 1; i++) out.push(t.slice(i, i + 2))
  return out
}

function dice(a: string, b: string): number {
  const A = bigrams(a)
  const B = bigrams(b)
  if (!A.length || !B.length) return a === b ? 1 : 0
  const pool = [...B]
  let hit = 0
  for (const g of A) {
    const i = pool.indexOf(g)
    if (i >= 0) {
      hit++
      pool.splice(i, 1)
    }
  }
  return (2 * hit) / (A.length + B.length)
}

// fração de palavras do lado menor que aparecem no outro (igual ou como prefixo: "man" ~ "manchester")
function tokenCover(a: string, b: string): number {
  const ta = a.split(' ')
  const tb = b.split(' ')
  const [small, big] = ta.length <= tb.length ? [ta, tb] : [tb, ta]
  const ok = (x: string, y: string) => x === y || (x.length >= 3 && y.startsWith(x)) || (y.length >= 3 && x.startsWith(y))
  const matched = small.filter((w) => big.some((v) => ok(w, v))).length
  return matched / small.length
}

export function similarity(a: string, b: string): number {
  const na = normalize(a)
  const nb = normalize(b)
  if (na === nb) return 1
  return Math.max(dice(na, nb), tokenCover(na, nb) * 0.9)
}

const MAX_KICKOFF_DIFF_MS = 4 * 3600000
const MIN_TEAM_SIM = 0.45
const MIN_SUM_SIM = 1.0

export type Pair = { match: DbMatch; event: OddsEvent; score: number }

// Cada evento e cada jogo são usados no máximo uma vez (guloso, do melhor par para o pior).
export function matchEvents(matches: DbMatch[], events: OddsEvent[]): Pair[] {
  const cands: Pair[] = []
  for (const m of matches) {
    const mt = new Date(m.kickoff_at).getTime()
    for (const ev of events) {
      if (Math.abs(new Date(ev.commence_time).getTime() - mt) > MAX_KICKOFF_DIFF_MS) continue
      const sh = similarity(m.home_team, ev.home_team)
      const sa = similarity(m.away_team, ev.away_team)
      if (sh < MIN_TEAM_SIM || sa < MIN_TEAM_SIM || sh + sa < MIN_SUM_SIM) continue
      cands.push({ match: m, event: ev, score: sh + sa })
    }
  }
  cands.sort((x, y) => y.score - x.score)
  const usedM = new Set<number>()
  const usedE = new Set<string>()
  const out: Pair[] = []
  for (const c of cands) {
    if (usedM.has(c.match.id) || usedE.has(c.event.id)) continue
    usedM.add(c.match.id)
    usedE.add(c.event.id)
    out.push(c)
  }
  return out
}
