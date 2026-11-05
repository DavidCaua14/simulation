// Fixed club accounting denomination. Personal coins keep their original scale.
export const CLUB_MONEY_SCALE = 1000
const reais = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 })
export const clubMoney = (units) => reais.format(Number(units || 0) * CLUB_MONEY_SCALE)
export const toClubReais = (units) => units === '' ? '' : Number(units || 0) * CLUB_MONEY_SCALE
export const fromClubReais = (value) => value === '' ? '' : Number(value) / CLUB_MONEY_SCALE
export const personalCoins = (value) => Number(value || 0).toLocaleString('pt-BR')
// Versão curta para placares e cabeçalhos: "R$ 86,8 mi", "R$ 950 mil".
export const clubMoneyShort = (units) => {
  const v = Number(units || 0) * CLUB_MONEY_SCALE
  const abs = Math.abs(v)
  const sign = v < 0 ? '-' : ''
  if (abs >= 1e9) return `${sign}R$ ${(abs / 1e9).toLocaleString('pt-BR', { maximumFractionDigits: 2 })} bi`
  if (abs >= 1e6) return `${sign}R$ ${(abs / 1e6).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} mi`
  if (abs >= 1e3) return `${sign}R$ ${Math.round(abs / 1e3).toLocaleString('pt-BR')} mil`
  return reais.format(v)
}
