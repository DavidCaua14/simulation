import { isMaintenanceAdmin } from '../../maintenance/policy'

// Modos em teste (`testerOnly`) ficam travados para todos, menos para o dono do jogo.
// O banco confere de novo (on_gate): destravar aqui não dá acesso a mais ninguém.
export const canTestModes = (user) => isMaintenanceAdmin(user)
export const isLockedFor = (item, user) => Boolean(item.locked) && !(item.testerOnly && canTestModes(user))
