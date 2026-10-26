import { supabase } from '../../lib/supabaseClient'

// Amigos (supabase/evolution/12_friends.sql): tudo pelo servidor (convites, aceite, perfis de amigos).
async function unwrap(promise) {
  const { data, error } = await promise
  if (error) throw new Error(error.message || 'Erro inesperado. Tente novamente.')
  return data
}
export const fetchFriends = () => unwrap(supabase.rpc('friends_overview'))
export const sendInvite = (username) => unwrap(supabase.rpc('friend_request', { p_username: username }))
export const respondInvite = (id, accept) => unwrap(supabase.rpc('friend_respond', { p_id: id, p_accept: accept }))
export const cancelInvite = (id) => unwrap(supabase.rpc('friend_cancel', { p_id: id }))
export const removeFriend = (id) => unwrap(supabase.rpc('friend_remove', { p_id: id }))
export const fetchFriendProfile = (username) => unwrap(supabase.rpc('friend_profile', { p_username: username }))
