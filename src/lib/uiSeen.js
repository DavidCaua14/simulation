// "JÁ VI" GUARDADO NA CONTA (tabela ui_seen no banco), para comemorações e animações aparecerem uma vez por conta,
// não uma vez por aparelho. seenBump(chave, valor) devolve o valor anterior (null na primeira vez) e só sobe.
// Sem banco configurado ou sem rede, devolve undefined: quem chama decide (em geral, segue a regra do aparelho).
import { isSupabaseConfigured, supabase } from './supabaseClient'

export async function seenBump(key, value = 1) {
  if (!isSupabaseConfigured) return undefined
  const { data, error } = await supabase.rpc('ui_seen_bump', { p_key: key, p_value: value })
  if (error) throw error
  return data ?? null
}
