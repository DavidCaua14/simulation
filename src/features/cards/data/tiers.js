import basicaClosed from '../assets/box-basica-closed.webp'
import basicaOpen from '../assets/box-basica-open.webp'
import destaqueClosed from '../assets/box-destaque-closed.webp'
import destaqueOpen from '../assets/box-destaque-open.webp'
import lendaClosed from '../assets/box-lenda-closed.webp'
import lendaOpen from '../assets/box-lenda-open.webp'
import epicaClosed from '../assets/box-epica-closed.webp'
import epicaOpen from '../assets/box-epica-open.webp'

// Visual das 4 raridades (cores e imagens das caixas). Os NÚMEROS (prêmios, chances, valor de descarte)
// ficam no banco (tabelas card_tiers / box_sources) — aqui é só aparência.
export const TIER_ORDER = ['basica', 'destaque', 'lenda', 'epica'] // do mais comum ao mais raro

export const TIERS = {
  basica:   { id: 'basica',   label: 'Básica',   rank: 1, color: '#cfd6e2', glow: 'rgba(207,214,226,.55)', closed: basicaClosed,   open: basicaOpen },
  destaque: { id: 'destaque', label: 'Destaque', rank: 2, color: '#38bdf8', glow: 'rgba(56,189,248,.65)',  closed: destaqueClosed, open: destaqueOpen },
  lenda:    { id: 'lenda',    label: 'Lenda',    rank: 3, color: '#fbbf24', glow: 'rgba(251,191,36,.70)',  closed: lendaClosed,    open: lendaOpen },
  epica:    { id: 'epica',    label: 'Épica',    rank: 4, color: '#c084fc', glow: 'rgba(192,132,252,.75)', closed: epicaClosed,    open: epicaOpen },
}

export const tierOf = (id) => TIERS[id] || TIERS.basica
export const isRare = (id) => (TIERS[id]?.rank ?? 1) >= 3

export const SOURCE_LABEL = {
  welcome: 'Boas-vindas',
  daily: 'Diária',
  season_win: 'Vitória',
}
export const sourceLabel = (s) => SOURCE_LABEL[s] || 'Prêmio'

// Taxa de troca mostrada na tela. O valor que vale é o do banco (diamonds_exchange_energy).
export const DIAMOND_TO_ENERGY = 2
