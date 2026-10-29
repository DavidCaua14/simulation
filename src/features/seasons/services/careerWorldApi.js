import { supabase } from '../../../lib/supabaseClient'
import { isSessionError } from '../../../lib/sessionRecovery'
export async function worldRpc(name, args = {}) {
  const { data, error } = await supabase.rpc(name, args)
  if (isSessionError(error)) throw error
  if (error) throw new Error(error.message || 'Não foi possível concluir a operação.')
  return data
}
export const requestId = () => crypto.randomUUID()
export const advanceWorld = (days, id = requestId()) => worldRpc('career_world_advance', { p_days: days, p_request: id })
export const searchPlayers = (filters) => worldRpc('career_player_search', filters)
export const negotiations = () => worldRpc('career_negotiations')
export const newsFeed = (before = null) => worldRpc('career_news', { p_before: before })
export const readNews = (ids) => worldRpc('career_news_read', { p_ids: ids })
export const financeHistory = () => worldRpc('career_finance_history')
export const money = (value) => Number(value || 0).toLocaleString('pt-BR')
export const dateLabel = (value) => value ? new Date(`${value}T12:00:00Z`).toLocaleDateString('pt-BR', { timeZone: 'UTC' }) : '—'
// Satisfação e contrato do SEU elenco pela busca do mercado (disponível desde a carreira completa, sem depender da evolução 32).
export async function fetchSquadContracts() {
  const out = []
  for (let page = 0; page < 4; page++) {
    const rows = (await searchPlayers({ p_query: '', p_country: '', p_position: '', p_region: '', p_club: 'mine', p_max_value: null, p_page: page })) || []
    out.push(...rows)
    if (rows.length < 30) break
  }
  return Object.fromEntries(out.map((p) => [p.id, p]))
}
