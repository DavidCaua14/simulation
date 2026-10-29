import { supabase } from '../../../lib/supabaseClient'

// Perfil no servidor (supabase/evolution/11_profile.sql). O app só pede; o banco confere propriedade,
// preço, privacidade e concede as insígnias.
async function unwrap(promise) {
  const { data, error } = await promise
  if (error) throw new Error(error.message || 'Erro inesperado. Tente novamente.')
  return data
}

export const fetchMyProfile = () => unwrap(supabase.rpc('profile_me'))
export const setAvatar = (data) => unwrap(supabase.rpc('profile_set_avatar', { p_data: data }))
export const setPrivacy = (privacy) => unwrap(supabase.rpc('profile_set_privacy', { p_privacy: privacy }))
export const migrateLocalPrefs = (avatar, background) =>
  unwrap(supabase.rpc('profile_migrate_local', { p_avatar: avatar, p_background: background }))
export const fetchCosmetics = () => unwrap(supabase.rpc('cosmetics_catalog'))
export const buyCosmetic = (id, requestId) => unwrap(supabase.rpc('cosmetic_buy', { p_cosmetic: id, p_request: requestId }))
export const equipCosmetic = (kind, id) => unwrap(supabase.rpc('cosmetic_equip', { p_kind: kind, p_cosmetic: id }))
