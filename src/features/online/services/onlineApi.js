import { supabase } from '../../../lib/supabaseClient'
import { isSessionError } from '../../../lib/sessionRecovery'

// Modo Online: mundo compartilhado (supabase/online/*.sql). Tudo é decidido no banco; o app só chama as funções on_*.
async function unwrap(promise) {
  const { data, error } = await promise
  if (isSessionError(error)) throw error
  if (error) throw new Error(error.message || 'Erro inesperado. Tente novamente.')
  return data
}
const rpc = (fn, args) => unwrap(supabase.rpc(fn, args))

// Situação do usuário: 'playing' (tem clube), 'queued' (na fila), 'none' ou 'unavailable' (modo ainda não instalado no banco).
export async function fetchOnlineStatus() {
  const response = await supabase.rpc('on_status')
  if (response.error?.code === 'PGRST202') return { access: 'unavailable', season: null, club: null, next: null }
  return unwrap(Promise.resolve(response))
}
export const joinOnlineQueue = () => rpc('on_join_queue')

// Escolha dos três craques (defesa, meio-campo, ataque)
export const fetchDraft = () => rpc('on_draft_read')
export const pickDraft = (step, idx) => rpc('on_draft_pick', { p_step: step, p_idx: idx })

// Elenco, escalação e táticas
export const fetchOnlineSquad = () => rpc('on_squad')
export const saveOnlineLineup = ({ formation, slots, bench, tactics = null }) =>
  rpc('on_lineup_save', { p_formation: formation, p_slots: slots, p_bench: bench, p_tactics: tactics })
export const autoOnlineLineup = (formation = null) => rpc('on_lineup_auto', { p_formation: formation })
export const renameOnlineClub = (name) => rpc('on_club_rename', { p_name: name })

// Calendário e classificação da liga compartilhada
export const fetchOnlineCalendar = () => rpc('on_calendar')
export const fetchOnlineStandings = () => rpc('on_standings')

// Catálogo de formações (o mesmo do modo Temporadas)
export const fetchFormations = () => unwrap(supabase.from('sim_formations').select('id,name,slots').order('sort'))
