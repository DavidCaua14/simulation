import { supabase } from '../../lib/supabaseClient'

// Eventos (supabase/evolution/13_events.sql): progresso, conclusão e entrega são decididos no servidor.
async function unwrap(promise) {
  const { data, error } = await promise
  if (error) throw new Error(error.message || 'Erro inesperado. Tente novamente.')
  return data
}
export const fetchEvents = () => unwrap(supabase.rpc('events_overview'))
export const claimEvent = (completionId) => unwrap(supabase.rpc('event_claim', { p_completion: completionId }))
export const claimStreak = () => unwrap(supabase.rpc('streak_claim'))

// administração (o servidor recusa quem não está em `admins`)
export const adminList = () => unwrap(supabase.rpc('admin_events_list'))
export const adminSave = (event) => unwrap(supabase.rpc('admin_event_save', { p_event: event }))
export const adminSetStatus = (id, status) => unwrap(supabase.rpc('admin_event_set_status', { p_id: id, p_status: status }))
