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

// Avisos com período (aparecem em modal na tela inicial) e controle do modo Temporadas.
export const fetchAnnouncements = () => rpc('admin_announcements')
export const saveAnnouncement = (a) => rpc('admin_announcement_save', { p: a })
export const cancelAnnouncement = (id) => rpc('admin_announcement_cancel', { p_id: id })
export const fetchCareer = (careerId) => rpc('admin_career', { p_career: careerId })
export const setCareerClub = (careerId, clubId, reason) => rpc('admin_career_set_club', { p_career: careerId, p_club: clubId, p_reason: reason })
export const adjustCareer = (careerId, field, amount, reason) => rpc('admin_career_adjust', { p_career: careerId, p_field: field, p_amount: amount, p_reason: reason })

// Big Time e caixas da loja (supabase/online/46_big_time.sql). Fotos no Storage, bucket "bigtime".
export const fetchBigTime = () => rpc('admin_bt_list')
export const saveBigTime = (card) => rpc('admin_bt_save', { p: card })
export const savePack = (pack) => rpc('admin_pack_save', { p: pack })
export async function uploadBigTimePhoto(file) {
  const ext = (file.type.split('/')[1] || 'jpg').replace('jpeg', 'jpg')
  const path = `cards/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`
  const { error } = await supabase.storage.from('bigtime').upload(path, file, { contentType: file.type, upsert: false, cacheControl: '31536000' })
  if (error) throw new Error(error.message || 'Falha ao enviar a foto')
  return supabase.storage.from('bigtime').getPublicUrl(path).data.publicUrl
}
