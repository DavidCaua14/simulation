import { supabase } from '../../../lib/supabaseClient'

// Loja: tudo é decidido no banco (supabase/evolution/06_economy_shop.sql) — vitrine, preço, saldo e entrega.
// O app só pede a vitrine e envia "quero esta carta nesta moeda" com um identificador de pedido.
async function unwrap(promise) {
  const { data, error } = await promise
  if (error) throw new Error(error.message || 'Erro inesperado. Tente novamente.')
  return data
}

export const fetchWalletHistory = (limit = 50) => unwrap(supabase.rpc('wallet_history', { p_limit: limit }))

export function newRequestId() {
  if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID()
  // navegadores antigos: UUID v4 com getRandomValues
  const b = globalThis.crypto.getRandomValues(new Uint8Array(16))
  b[6] = (b[6] & 0x0f) | 0x40
  b[8] = (b[8] & 0x3f) | 0x80
  const h = [...b].map((x) => x.toString(16).padStart(2, '0')).join('')
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`
}

// Energia (supabase/evolution/10_energy_packs.sql)
export const fetchEnergy = () => unwrap(supabase.rpc('energy_catalog'))
export const buyEnergy = (packId, requestId) => unwrap(supabase.rpc('energy_buy', { p_pack: packId, p_request: requestId }))
