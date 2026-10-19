// Funções puras (sem Deno, sem rede) da The Odds API v4: mapa de campeonatos,
// URL, e consenso das odds 1X2 entre as casas de aposta.

// competitions.api_league_id (football-data.org) -> chave de esporte da The Odds API.
// Confira as chaves reais da sua conta (GRÁTIS, não gasta crédito):
//   https://api.the-odds-api.com/v4/sports/?apiKey=SUA_CHAVE
export const SPORT_BY_FD_LEAGUE: Record<number, string> = {
  2013: 'soccer_brazil_campeonato', // Brasileirão Série A
  72: 'soccer_brazil_serie_b', //      Série B (hoje inativa no seu banco)
  2001: 'soccer_uefa_champs_league',
  2014: 'soccer_spain_la_liga',
  2021: 'soccer_epl',
  2002: 'soccer_germany_bundesliga',
  2019: 'soccer_italy_serie_a',
  2015: 'soccer_france_ligue_one',
  2017: 'soccer_portugal_primeira_liga',
  2003: 'soccer_netherlands_eredivisie',
  2016: 'soccer_efl_champ',
  2152: 'soccer_conmebol_copa_libertadores',
  2018: 'soccer_uefa_european_championship',
  2000: 'soccer_fifa_world_cup',
}

export type OddsOutcome = { name: string; price: number }
export type OddsBookmaker = { key: string; markets: { key: string; outcomes: OddsOutcome[] }[] }
export type OddsEvent = {
  id: string
  commence_time: string
  home_team: string
  away_team: string
  bookmakers: OddsBookmaker[]
}

// 1 mercado (h2h) x 1 região (eu) = 1 crédito por chamada, devolvendo TODOS os jogos do campeonato.
export function buildOddsUrl(sportKey: string, apiKey: string): string {
  const q = new URLSearchParams({ apiKey, regions: 'eu', markets: 'h2h', oddsFormat: 'decimal', dateFormat: 'iso' })
  return `https://api.the-odds-api.com/v4/sports/${sportKey}/odds/?${q}`
}

export const MIN_ODD = 1.1 // mesmos limites do odds.ts
export const MAX_ODD = 15

const clamp = (n: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, n))
const round2 = (n: number) => Math.round(n * 100) / 100

export function median(values: number[]): number {
  const s = [...values].sort((a, b) => a - b)
  const mid = Math.floor(s.length / 2)
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2
}

// Mediana de cada resultado entre as casas: resiste a uma casa fora da curva.
export function consensus1x2(ev: OddsEvent): { home: number; draw: number; away: number; books: number } | null {
  const h: number[] = []
  const d: number[] = []
  const a: number[] = []
  for (const bk of ev.bookmakers ?? []) {
    const mk = bk.markets?.find((m) => m.key === 'h2h')
    if (!mk) continue
    const ph = mk.outcomes.find((o) => o.name === ev.home_team)?.price
    const pa = mk.outcomes.find((o) => o.name === ev.away_team)?.price
    const pd = mk.outcomes.find((o) => o.name.toLowerCase() === 'draw')?.price
    if ((ph ?? 0) > 1 && (pa ?? 0) > 1 && (pd ?? 0) > 1) {
      // (ph/pa/pd são números aqui)
      h.push(ph as number)
      d.push(pd as number)
      a.push(pa as number)
    }
  }
  if (!h.length) return null
  const fix = (arr: number[]) => round2(clamp(median(arr), MIN_ODD, MAX_ODD))
  return { home: fix(h), draw: fix(d), away: fix(a), books: h.length }
}
