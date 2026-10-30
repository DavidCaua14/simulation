import { supabase } from '../../lib/supabaseClient'

// Caixa de entrada (supabase/evolution/43_inbox_announcements_admin.sql): avisos do jogo e comunicados/premiações.
async function rpc(fn, args) {
  const { data, error } = await supabase.rpc(fn, args)
  if (error) throw new Error(error.message || 'Erro inesperado. Tente novamente.')
  return data
}

export const fetchInbox = () => rpc('inbox_list')
export const fetchPending = () => rpc('inbox_pending')
export const markSeen = (items) => rpc('inbox_seen', { p_items: items.map((i) => ({ type: i.type, id: i.id })) })
export const claimItem = (item) => rpc('inbox_claim', { p_type: item.type, p_id: item.id })

export const REWARD_LABEL = { coins: 'moedas', diamonds: 'diamantes', bonus_energy: 'de energia' }
export const REWARD_ICON = { coins: 'coins', diamonds: 'diamond', bonus_energy: 'energy' }
export const rewardEntries = (reward) => Object.entries(reward || {}).filter(([, v]) => Number(v) > 0)

// Avisa as telas (Home, carteira) que a caixa mudou: item visto ou premiação resgatada.
export const notifyInboxChanged = () => window.dispatchEvent(new Event('game:inbox'))
