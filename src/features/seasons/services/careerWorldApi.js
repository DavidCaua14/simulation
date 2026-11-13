import { supabase } from '../../../lib/supabaseClient'
import { isSessionError } from '../../../lib/sessionRecovery'
export async function worldRpc(name, args = {}) {
  const { data, error } = await supabase.rpc(name, args)
  if (isSessionError(error)) throw error
  if (error) throw new Error(error.message || 'Não foi possível concluir a operação.')
  return data
}
export const requestId = () => crypto.randomUUID()
export const advanceWorld = (days, id = requestId(), expectedVersion = null) => expectedVersion == null
  ? worldRpc('career_world_advance', { p_days: days, p_request: id })
  : worldRpc('career_world_prepare', { p_days: days, p_request: id, p_expected_version: expectedVersion })
export const acknowledgeAttention = (key) => worldRpc('career_attention_ack', { p_key: key })
export const searchPlayers = (filters) => worldRpc('career_player_search', filters)
// Mercado (2026-11-06): habilidade, idade, valor, situação contratual e ordenação.
export const marketSearch = (filters) => worldRpc('career_market_search', filters)
export const negotiations = () => worldRpc('career_negotiations')
export const newsFeed = (before = null) => worldRpc('career_news', { p_before: before })
export const readNews = (ids) => worldRpc('career_news_read', { p_ids: ids })
export const financeHistory = () => worldRpc('career_finance_history')
export { clubMoney as money } from '../utils/clubMoney'
export const dateLabel = (value) => value ? new Date(`${value}T12:00:00Z`).toLocaleDateString('pt-BR', { timeZone: 'UTC' }) : '—'
// Negociação CM17 (evolução 66): oferta só de valor; contrato com salário mensal e anos.
export const transferOffer = (player, fee) => worldRpc('career_transfer_offer', { p_player: player, p_fee: fee, p_request: requestId() })
export const contractOffer = (negotiation, weekly, years) => worldRpc('career_contract_offer', { p_negotiation: negotiation, p_weekly_wage: weekly, p_years: years, p_request: requestId() })
export const renewOffer = (player, weekly, years) => worldRpc('career_contract_renew_offer', { p_player: player, p_weekly_wage: weekly, p_years: years, p_request: requestId() })
export const wageDemand = (player) => worldRpc('career_wage_demand', { p_player: player })
export const respondNegotiation = (id, action, fee) => worldRpc('career_transfer_respond', { p_id: id, p_action: action, p_fee: fee, p_request: requestId() })
export const listPlayer = (player, listed) => worldRpc('career_player_list', { p_player: player, p_listed: listed })
// Pré-seleção (evolução 67)
export const shortlist = () => worldRpc('career_shortlist')
export const toggleShortlist = (player) => worldRpc('career_shortlist_toggle', { p_player: player })
// O jogo trabalha só com salário MENSAL (folha, teto e contratos). A função mantém o nome antigo e devolve o próprio valor.
export const weekly = (monthly) => Math.round(Number(monthly) || 0)
// Confirmação final (evolução 68): o atleta aceitou; o treinador confirma ou desiste.
export const confirmTransfer = (id, accept) => worldRpc('career_transfer_confirm', { p_id: id, p_accept: accept, p_request: requestId() })
