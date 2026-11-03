// Fixed club accounting denomination. Personal coins keep their original scale.
export const CLUB_MONEY_SCALE = 1000
const reais = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 })
export const clubMoney = (units) => reais.format(Number(units || 0) * CLUB_MONEY_SCALE)
export const toClubReais = (units) => units === '' ? '' : Number(units || 0) * CLUB_MONEY_SCALE
export const fromClubReais = (value) => value === '' ? '' : Number(value) / CLUB_MONEY_SCALE
export const personalCoins = (value) => Number(value || 0).toLocaleString('pt-BR')
