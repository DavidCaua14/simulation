// Gera odds "de mercado" a partir da tabela do campeonato (gols pró/contra de cada time).
// Modelo: Poisson com força de ataque/defesa + vantagem de jogar em casa, margem da casa de ~6%.
// Resultado: favoritos pagam pouco, azarões pagam muito, e o empate fica entre os dois.
// Funções puras (sem rede), fáceis de testar.

export type StandingRow = { teamId: number; played: number; gf: number; ga: number }
export type Ratings = { mu: number; teams: Map<number, { att: number; def: number }> }
export type Odds = { home: number; draw: number; away: number; bttsYes: number; bttsNo: number }

const PRIOR_GAMES = 4 // "jogos fictícios" na média: evita times com poucas rodadas virarem extremos
const HOME_ADVANTAGE = 1.15
const DRAW_BOOST = 1.08 // Poisson puro subestima empates
const MARGIN_1X2 = 1.06
const MARGIN_BTTS = 1.05
const MIN_ODD = 1.1
const MAX_ODD = 15
const DEFAULT_MU = 1.3 // média de gols por time por jogo quando não há tabela

const clamp = (n: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, n))
const round2 = (n: number) => Math.round(n * 100) / 100

export function buildRatings(rows: StandingRow[]): Ratings | null {
  const games = rows.reduce((a, r) => a + r.played, 0)
  if (games < 20) return null // início de temporada: sem dados suficientes
  const mu = rows.reduce((a, r) => a + r.gf, 0) / games
  if (!(mu > 0)) return null
  const teams = new Map<number, { att: number; def: number }>()
  for (const r of rows) {
    teams.set(r.teamId, {
      // limites evitam que um time com campanha atípica gere odds absurdas
      att: clamp((r.gf + PRIOR_GAMES * mu) / (r.played + PRIOR_GAMES) / mu, 0.55, 1.8),
      def: clamp((r.ga + PRIOR_GAMES * mu) / (r.played + PRIOR_GAMES) / mu, 0.55, 1.8),
    })
  }
  return { mu, teams }
}

function pmf(lambda: number, max = 10): number[] {
  const out: number[] = []
  let p = Math.exp(-lambda)
  for (let k = 0; k <= max; k++) {
    out.push(p)
    p = (p * lambda) / (k + 1)
  }
  return out
}

const toOdd = (p: number, margin: number) => round2(clamp(1 / (Math.max(p, 0.001) * margin), MIN_ODD, MAX_ODD))

export function computeOdds(ratings: Ratings | null, homeId: number | null, awayId: number | null): Odds {
  const mu = ratings?.mu ?? DEFAULT_MU
  const neutral = { att: 1, def: 1 }
  const home = (homeId != null && ratings?.teams.get(homeId)) || neutral
  const away = (awayId != null && ratings?.teams.get(awayId)) || neutral

  const lh = clamp(mu * HOME_ADVANTAGE * home.att * away.def, 0.3, 3.6)
  const la = clamp((mu / HOME_ADVANTAGE) * away.att * home.def, 0.3, 3.6)

  const ph = pmf(lh)
  const pa = pmf(la)
  let pH = 0
  let pD = 0
  let pA = 0
  for (let i = 0; i < ph.length; i++) {
    for (let j = 0; j < pa.length; j++) {
      const p = ph[i] * pa[j]
      if (i > j) pH += p
      else if (i === j) pD += p
      else pA += p
    }
  }
  pD *= DRAW_BOOST
  const total = pH + pD + pA
  pH /= total
  pD /= total
  pA /= total

  const pBtts = (1 - Math.exp(-lh)) * (1 - Math.exp(-la))
  return {
    home: toOdd(pH, MARGIN_1X2),
    draw: toOdd(pD, MARGIN_1X2),
    away: toOdd(pA, MARGIN_1X2),
    bttsYes: toOdd(pBtts, MARGIN_BTTS),
    bttsNo: toOdd(1 - pBtts, MARGIN_BTTS),
  }
}
