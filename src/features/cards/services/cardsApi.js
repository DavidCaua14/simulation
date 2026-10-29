import { supabase } from '../../../lib/supabaseClient'

export async function exchangeDiamonds(diamonds) {
  const { data, error } = await supabase.rpc('diamonds_exchange_energy', { p_diamonds: diamonds })
  if (error) throw new Error(error.message || 'Não foi possível trocar diamantes.')
  return data
}
