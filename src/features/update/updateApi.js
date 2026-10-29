import { supabase } from '../../lib/supabaseClient'

// Presente da atualização (só para quem já jogava antes dela). O banco decide quem pode receber e dá uma única vez.
export async function claimReleaseGift() {
  const { data, error } = await supabase.rpc('release_gift_claim')
  if (error) {
    // Banco ainda sem a evolução 35: não há presente para mostrar.
    if (error.code === 'PGRST202' || /release_gift_claim/.test(error.message || '')) return null
    throw error
  }
  return data
}
export async function markReleaseSeen() {
  const { error } = await supabase.rpc('release_gift_seen')
  if (error) throw error
}
