// Regras de EXIBIÇÃO. Quem manda de verdade é o banco (place_ticket / settle_tickets):
// aqui só calculamos o mesmo valor para mostrar o retorno potencial antes de confirmar.
export const MAX_MULTIPLIER = 100
export const MIN_STAKE = 10
export const MAX_STAKE = 1000
export const MAX_PICKS = 10
export const STAKE_CHIPS = [10, 50, 100, 500]

// ODDS FIXAS para todos os jogos (nenhuma API de odds é usada).
// IMPORTANTE: precisam ser iguais às constantes da função place_ticket no banco
// (supabase/fix_palpites.sql). O banco é quem vale; aqui é só para exibir.
export const FIXED_ODDS = { home: 1.5, draw: 2.0, away: 1.5, bttsYes: 1.85, bttsNo: 1.95 }

// Mantém a assinatura antiga (recebe o jogo), mas ignora as colunas odds_* da tabela.
// eslint-disable-next-line no-unused-vars
export const matchOdds = (_match) => FIXED_ODDS

export const resultOdd = (match, result) => matchOdds(match)[result]
export const bttsOdd = (match, value) => (value ? matchOdds(match).bttsYes : matchOdds(match).bttsNo)

// Favorito = lado com odd claramente menor (pelo menos 10% abaixo do outro).
export function favoriteOf(match) {
  const { home, away } = matchOdds(match)
  if (home < away * 0.9) return 'home'
  if (away < home * 0.9) return 'away'
  return null
}

const round2 = (n) => Math.round(n * 100) / 100

export function pickMultiplier({ match, result, btts }) {
  let m = 1
  if (result) m *= round2(resultOdd(match, result))
  if (btts !== null && btts !== undefined) m *= round2(bttsOdd(match, btts))
  return round2(m)
}

export function slipMultiplier(picks) {
  const total = picks.reduce((acc, p) => acc * pickMultiplier(p), 1)
  return Math.min(round2(total), MAX_MULTIPLIER)
}

export const potentialCoins = (stake, mult) => Math.floor(stake * mult)
// XP baixo: cresce devagar com o valor apostado e com o número de jogos acertados.
export const potentialXp = (stake, picksCount) => Math.min(60, Math.ceil(stake / 25) + picksCount - 1)
// Energia generosa: 2 + um por jogo acertado.
export const potentialEnergy = (picksCount) => Math.min(12, 2 + picksCount)

export const formatOdd = (o) => Number(o).toFixed(2).replace('.', ',')
export const formatMult = (m) => `${formatOdd(m)}x`
