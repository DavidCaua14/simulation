import { supabase } from '../../lib/supabaseClient'

// Painel administrativo (supabase/evolution/42_admin_dashboard.sql). O servidor confere o administrador em cada chamada.
async function rpc(fn, args) {
  const { data, error } = await supabase.rpc(fn, args)
  if (error) throw new Error(error.message || 'Erro inesperado. Tente novamente.')
  return data
}

export const fetchOverview = () => rpc('admin_overview')
export const fetchPlayers = (query = '') => rpc('admin_players', { p_query: query, p_limit: 100 })
export const grantPlayer = (careerId, currency, amount, reason) =>
  rpc('admin_player_grant', { p_career: careerId, p_currency: currency, p_amount: amount, p_reason: reason })
export const broadcast = (title, body) => rpc('admin_broadcast', { p_title: title, p_body: body })
export const fetchActions = () => rpc('admin_actions_list', { p_limit: 200 })
