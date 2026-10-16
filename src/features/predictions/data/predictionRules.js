// Espelha as regras do banco (place_ticket / settle_tickets).
// O servidor é quem manda: aqui serve só para MOSTRAR o prêmio potencial.
export const RESULT_MULTIPLIERS = { home: 1.8, draw: 2.2, away: 1.8 }
export const BTTS_MULTIPLIER = 1.5
export const MAX_MULTIPLIER = 100
export const MIN_STAKE = 10
export const MAX_STAKE = 1000
export const MAX_PICKS = 10
export const STAKE_CHIPS = [10, 50, 100, 500]

export function pickMultiplier({ result, btts }) {
  let m = 1
  if (result) m *= RESULT_MULTIPLIERS[result]
  if (btts !== null && btts !== undefined) m *= BTTS_MULTIPLIER
  return m
}

export function slipMultiplier(picks) {
  const total = picks.reduce((acc, p) => acc * pickMultiplier(p), 1)
  return Math.min(Math.round(total * 100) / 100, MAX_MULTIPLIER)
}

export const potentialCoins = (stake, mult) => Math.floor(stake * mult)
export const potentialXp = (stake, mult) => Math.max(5, Math.floor(stake * 0.2 * mult))
export const potentialEnergy = (picksCount) => 1 + (picksCount >= 3 ? 1 : 0)

export const formatMult = (m) => `${Number(m.toFixed(2)).toString().replace('.', ',')}x`
