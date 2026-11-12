import { supabase } from '../../../lib/supabaseClient'
import { isSessionError } from '../../../lib/sessionRecovery'

// Modo Online: mundo compartilhado (supabase/online/*.sql). Tudo é decidido no banco; o app só chama as funções on_*.
async function unwrap(promise) {
  const { data, error } = await promise
  if (isSessionError(error)) throw error
  if (error) throw new Error(error.message || 'Erro inesperado. Tente novamente.')
  return data
}
const rpc = (fn, args) => unwrap(supabase.rpc(fn, args))

// Situação do usuário: 'playing' (tem clube), 'queued' (na fila), 'none' ou 'unavailable' (modo ainda não instalado no banco).
export async function fetchOnlineStatus() {
  const response = await supabase.rpc('on_status')
  if (response.error?.code === 'PGRST202') return { access: 'unavailable', season: null, club: null, next: null }
  return unwrap(Promise.resolve(response))
}
export const joinOnlineQueue = () => rpc('on_join_queue')

// Escolha dos três craques (defesa, meio-campo, ataque)
export const fetchDraft = () => rpc('on_draft_read')
export const pickDraft = (step, idx) => rpc('on_draft_pick', { p_step: step, p_idx: idx })

// Elenco, escalação e táticas
export const fetchOnlineSquad = () => rpc('on_squad')
export const saveOnlineLineup = ({ formation, slots, bench, tactics = null }) =>
  rpc('on_lineup_save', { p_formation: formation, p_slots: slots, p_bench: bench, p_tactics: tactics })
export const autoOnlineLineup = (formation = null) => rpc('on_lineup_auto', { p_formation: formation })
export const renameOnlineClub = (name) => rpc('on_club_rename', { p_name: name })
// Identidade do clube: nome, sigla, cores, desenho e formato do escudo, estádio. Só as chaves enviadas mudam.
export const saveOnlineIdentity = (identity) => rpc('on_club_identity', { p: identity })

// Calendário e classificação da liga compartilhada
export const fetchOnlineCalendar = () => rpc('on_calendar')
export const fetchOnlineStandings = () => rpc('on_standings')

// Catálogo de formações (o mesmo do modo Temporadas)
export const fetchFormations = () => unwrap(supabase.from('sim_formations').select('id,name,slots').order('sort'))

// Partida ao vivo (Fase 2). A tela consulta a cada 20 s; cada mudança leva um identificador único (p_req)
// para que um duplo clique não seja aplicado duas vezes.
export const pollOnlineMatch = (fixtureId = null, afterSeq = 0) => rpc('on_match_poll', { p_fixture: fixtureId, p_after_seq: afterSeq })
export const actOnlineMatch = (fixtureId, changes) =>
  rpc('on_match_act', { p_fixture: fixtureId, p_req: crypto.randomUUID?.() || `${Date.now()}-${Math.random().toString(36).slice(2)}`, p_changes: changes })
export const saveOnlineRoles = (roles) => rpc('on_roles_save', { p_roles: roles })

// Mercado de leilões (Fase 3)
export const fetchOnlineMarket = () => rpc('on_market')
export const bidOnline = (lotId, amount, coins = false) => rpc('on_bid', { p_lot: lotId, p_amount: amount, p_coins: coins })
export const markOnlineNewsSeen = (ids) => rpc('on_news_seen', { p_ids: ids })
// Venda direta ao mercado (60% do valor, na hora).
export const sellOnlinePlayer = (playerId) => rpc('on_sell', { p_player: playerId })
// Leilão de jogador do próprio elenco: uma hora no mercado, lance inicial entre o mínimo e o máximo de on_lot_range.
export const fetchOnlineLotRange = (playerId) => rpc('on_lot_range', { p_player: playerId })
export const createOnlineLot = (playerId, price) => rpc('on_lot_create', { p_player: playerId, p_price: price })
export const cancelOnlineLot = (lotId) => rpc('on_lot_cancel', { p_lot: lotId })
export const fetchOnlineFinance = () => rpc('on_finance')

// Clube: treino, estrutura, contratos e moedas (Fase 4)
export const fetchOnlineClub = () => rpc('on_club')
export const buildOnline = (kind) => rpc('on_build', { p_kind: kind })
export const startOnlineTraining = (game, players) => rpc('on_train_start', { p_game: game, p_players: players })
export const finishOnlineTraining = (session, score) => rpc('on_train_finish', { p_session: session, p_score: score })
export const renewOnlinePlayer = (playerId, years) => rpc('on_renew', { p_player: playerId, p_years: years })
// Sem prefixo on_: o cache do app trata como escrita e atualiza a carteira de moedas nas outras telas.
export const convertOnlineCoins = (coins) => rpc('online_coins_convert', { p_coins: coins })
// Energia de treino: um treino extra hoje, pago com moedas da conta.
export const buyOnlineTrainEnergy = (pack = 'coin') => rpc('online_train_energy_buy', { p_pack: pack })

// Preparação para o jogo (Fase 8): relatório do adversário e preleção
export const fetchOnlineScout = (mark = true) => rpc('on_scout', { p_mark: mark })
// Preleção do intervalo: praise, focus, demand, encourage, calm ou angry
export const sendOnlineHalftimeTalk = (fixtureId, talk) => rpc('on_match_talk', { p_fixture: fixtureId, p_talk: talk })
export const sendOnlineTeamTalk = (talk) => rpc('on_team_talk', { p_talk: talk })

// Escalações dos dois times de um jogo (vestiário e partida)
export const fetchOnlineFixtureLineups = (fixtureId) => rpc('on_fixture_lineups', { p_fixture: fixtureId })

// Copa e histórico (Fase 5)
export const fetchOnlineCup = () => rpc('on_cup')
