import { supabase } from '../../lib/supabaseClient'
import { isSessionError } from '../../lib/sessionRecovery'

// Desenvolvimento do clube (evolução 58). Tudo é decidido no banco; o app só envia as escolhas do treinador.
// Enquanto a migração não estiver instalada, a leitura devolve { unavailable: true } e a tela explica isso.
async function call(fn, args = {}) {
  const { data, error } = await supabase.rpc(fn, args)
  if (isSessionError(error)) throw error
  if (error?.code === 'PGRST202') {
    const e = new Error('Recurso disponível após a atualização do servidor.')
    e.unavailable = true
    throw e
  }
  if (error) throw new Error(error.message || 'Não foi possível concluir a operação.')
  return data
}

const rid = () => crypto.randomUUID()

export async function fetchClubDev() {
  try {
    return await call('career_club_dev_read')
  } catch (e) {
    if (e.unavailable) return { unavailable: true }
    throw e
  }
}
export const setTraining = (focus, intensity) => call('career_training_set', { p_focus: focus, p_intensity: intensity })
export const setLearning = (playerId, pos) => call('career_player_learn', { p_player: playerId, p_pos: pos })
// Capitão chegou na evolução 64; antes dela o servidor só conhece os três batedores.
export async function setSetPieces({ penalty, freeKick, corner, captain }) {
  const base = { p_penalty: penalty || null, p_free_kick: freeKick || null, p_corner: corner || null }
  try {
    return await call('career_set_pieces_set', { ...base, p_captain: captain || null })
  } catch (e) {
    if (!e.unavailable) throw e
    return call('career_set_pieces_set', base)
  }
}
export const upgradeFacility = (kind) => call('career_facility_upgrade', { p_kind: kind, p_request: rid() })
export const hireStaff = (role, level) => call('career_staff_hire', { p_role: role, p_level: level, p_request: rid() })
export const requestScout = (playerId) => call('career_scout_request', { p_player: playerId })
export const requestLoan = (playerId, wageShare, role) => call('career_loan_request', { p_player: playerId, p_wage_share: wageShare, p_role: role, p_request: rid() })
export const listForLoan = (playerId, listed) => call('career_loan_list', { p_player: playerId, p_listed: listed })
export const respondLoan = (loanId, accept) => call('career_loan_respond', { p_loan: loanId, p_accept: accept })
export const setDifficulty = (id) => call('career_difficulty_set', { p_difficulty: id })
// Exercícios pré-jogo (evolução 64): cobrados em moedas, valem por alguns jogos.
export const fetchDrills = () => call('career_drills')
export const buyDrill = (kind) => call('career_drill_buy', { p_kind: kind, p_request: rid() })
// Treino livre (2026-11-06): 1 energia, aumenta o entrosamento com a formação. quality = aproveitamento do minijogo (0–1).
export const freeTraining = (formation, quality) => call('career_free_training', { p_formation: formation, p_quality: quality })
// Olheiros por missão: posição + perfil ('prospect' | 'starter' | 'bargain').
export const scoutMission = (position, profile) => call('career_scout_mission', { p_position: position || '', p_profile: profile })
