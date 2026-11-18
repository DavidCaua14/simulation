// Insígnias de campeão do modo Online (on_honors) e logos das competições.
import firstLeague from '../../assets/online/honor_first_league.webp'
import firstCup from '../../assets/online/honor_first_cup.webp'
import league from '../../assets/online/honor_league.webp'
import cup from '../../assets/online/honor_cup.webp'
import logoLiga from '../../assets/online/logo_liga.webp'
import logoCopa from '../../assets/online/logo_copa.webp'

export const HONOR_ART = { first_league: firstLeague, first_cup: firstCup, league, cup }
export const COMP_LOGO = { L: logoLiga, C: logoCopa }
// chave da premiação na caixa de entrada → insígnia
export const HONOR_REWARD = {
  honor_first_league: { id: 'first_league', comp: 'L', first: true, label: 'Primeiro Campeão da Liga Online' },
  honor_first_cup: { id: 'first_cup', comp: 'C', first: true, label: 'Primeiro Campeão da Copa Online' },
  honor_league: { id: 'league', comp: 'L', first: false, label: 'Campeão da Liga Online' },
  honor_cup: { id: 'cup', comp: 'C', first: false, label: 'Campeão da Copa Online' },
}
export const honorOf = (reward) => {
  const k = Object.keys(reward || {}).find((x) => HONOR_REWARD[x])
  return k ? { key: k, ...HONOR_REWARD[k] } : null
}
