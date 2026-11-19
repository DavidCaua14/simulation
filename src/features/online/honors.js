// Insígnias de campeão do modo Online (on_honors) e logos das competições.
import firstLeague from '../../assets/online/honor_first_league.webp'
import firstCup from '../../assets/online/honor_first_cup.webp'
import league from '../../assets/online/honor_league.webp'
import cup from '../../assets/online/honor_cup.webp'
import logoLiga from '../../assets/online/logo_liga.webp'
import logoCopa from '../../assets/online/logo_copa.webp'
import serieA from '../../assets/online/serie_a.webp'
import serieB from '../../assets/online/serie_b.webp'
import serieC from '../../assets/online/serie_c.webp'
import serieD from '../../assets/online/serie_d.webp'

const SERIES_ART = { a: serieA, b: serieB, c: serieC, d: serieD }
export const HONOR_ART = {
  first_league: firstLeague, first_cup: firstCup, league, cup,
  ...Object.fromEntries(Object.entries(SERIES_ART).flatMap(([k, v]) => [[`league_${k}`, v], [`first_league_${k}`, v]])),
}
export const COMP_LOGO = { L: logoLiga, C: logoCopa, LA: serieA, LB: serieB, LC: serieC, LD: serieD }
// nome da competição de uma insígnia (comp: L, C, LA, LB, LC, LD)
export const compName = (comp) => (comp === 'C' ? 'Copa Online' : comp?.length === 2 ? `Liga Online ${comp[1]}` : 'Liga Online')
// chave da premiação na caixa de entrada → insígnia
export const HONOR_REWARD = {
  honor_first_league: { id: 'first_league', comp: 'L', first: true, label: 'Primeiro Campeão da Liga Online' },
  honor_first_cup: { id: 'first_cup', comp: 'C', first: true, label: 'Primeiro Campeão da Copa Online' },
  honor_league: { id: 'league', comp: 'L', first: false, label: 'Campeão da Liga Online' },
  honor_cup: { id: 'cup', comp: 'C', first: false, label: 'Campeão da Copa Online' },
  ...Object.fromEntries(['a', 'b', 'c', 'd'].flatMap((k) => [
    [`honor_league_${k}`, { id: `league_${k}`, comp: `L${k.toUpperCase()}`, first: false, label: `Campeão da Liga Online ${k.toUpperCase()}` }],
    [`honor_first_league_${k}`, { id: `first_league_${k}`, comp: `L${k.toUpperCase()}`, first: true, label: `Primeiro Campeão da Liga Online ${k.toUpperCase()}` }],
  ])),
}
export const honorOf = (reward) => {
  const k = Object.keys(reward || {}).find((x) => HONOR_REWARD[x])
  return k ? { key: k, ...HONOR_REWARD[k] } : null
}
