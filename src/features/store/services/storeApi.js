import { supabase } from '../../../lib/supabaseClient'

// Loja: tudo é decidido no banco (supabase/evolution/06_economy_shop.sql) — vitrine, preço, saldo e entrega.
// O app só pede a vitrine e envia "quero esta carta nesta moeda" com um identificador de pedido.
async function unwrap(promise) {
  const { data, error } = await promise
  if (error) throw new Error(error.message || 'Erro inesperado. Tente novamente.')
  return data
}

export const fetchShop = () => unwrap(supabase.rpc('shop_catalog'))

// requestId: gerado UMA vez quando a confirmação abre e reaproveitado se o usuário tentar de novo
// (queda de rede, clique duplo): o banco devolve o mesmo resultado sem cobrar outra vez.
export const buyCard = (cardId, currency, requestId) =>
  unwrap(supabase.rpc('shop_buy_card', { p_card: cardId, p_currency: currency, p_request: requestId }))

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

// Roleta (supabase/evolution/08_wheel.sql): o sorteio é do servidor; a animação só mostra o resultado.
export const fetchWheel = () => unwrap(supabase.rpc('wheel_catalog'))
export const spinWheel = (requestId) => unwrap(supabase.rpc('wheel_spin', { p_request: requestId }))

// Mercado entre jogadores (supabase/evolution/09_market.sql): dono, preço, saldo e taxa são decididos no servidor.
export const fetchMarket = ({ q, tier, min, max, sort } = {}) =>
  unwrap(supabase.rpc('market_browse', {
    p_q: q || null, p_tier: tier || null, p_min: min ? Number(min) : null, p_max: max ? Number(max) : null, p_sort: sort || 'newest',
  }))
export const fetchMyMarket = () => unwrap(supabase.rpc('market_mine'))
export const fetchSellable = () => unwrap(supabase.rpc('market_sellable'))
export const fetchMarketRules = () => unwrap(supabase.rpc('market_rules'))
export const listCard = (cardId, price, requestId) =>
  unwrap(supabase.rpc('market_list_card', { p_card: cardId, p_price: Number(price), p_request: requestId }))
export const cancelListing = (listingId) => unwrap(supabase.rpc('market_cancel', { p_listing: listingId }))
export const buyListing = (listingId, requestId) => unwrap(supabase.rpc('market_buy', { p_listing: listingId, p_request: requestId }))

// taxa como o servidor calcula (arredonda para cima) — só para mostrar ANTES; o valor real vem da resposta
export const feeOf = (price, pct) => Math.min(price, Math.ceil((price * pct) / 100))

// Energia (supabase/evolution/10_energy_packs.sql)
export const fetchEnergy = () => unwrap(supabase.rpc('energy_catalog'))
export const buyEnergy = (packId, requestId) => unwrap(supabase.rpc('energy_buy', { p_pack: packId, p_request: requestId }))
