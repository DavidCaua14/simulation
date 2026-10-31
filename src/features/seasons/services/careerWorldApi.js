import { supabase } from '../../../lib/supabaseClient'
import { isSessionError } from '../../../lib/sessionRecovery'
export async function worldRpc(name, args = {}) {
  const { data, error } = await supabase.rpc(name, args)
  if (isSessionError(error)) throw error
  if (error) throw new Error(error.message || 'Não foi possível concluir a operação.')
  return data
}
export const requestId = () => crypto.randomUUID()
export const advanceWorld = (days, id = requestId(), expectedVersion = null) => expectedVersion == null
  ? worldRpc('career_world_advance', { p_days: days, p_request: id })
  : worldRpc('career_world_prepare', { p_days: days, p_request: id, p_expected_version: expectedVersion })
export const acknowledgeAttention = (key) => worldRpc('career_attention_ack', { p_key: key })
export const searchPlayers = (filters) => worldRpc('career_player_search', filters)
export const negotiations = () => worldRpc('career_negotiations')
export const newsFeed = (before = null) => worldRpc('career_news', { p_before: before })
export const readNews = (ids) => worldRpc('career_news_read', { p_ids: ids })
export const financeHistory = () => worldRpc('career_finance_history')
export const money = (value) => Number(value || 0).toLocaleString('pt-BR')
export const dateLabel = (value) => value ? new Date(`${value}T12:00:00Z`).toLocaleDateString('pt-BR', { timeZone: 'UTC' }) : '—'
