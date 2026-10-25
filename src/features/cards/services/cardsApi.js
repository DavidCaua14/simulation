import { supabase } from '../../../lib/supabaseClient'

// Tudo o que as cartas fazem acontece no banco (supabase/cards/01_cards.sql).
// Aqui só chamamos as funções e lemos as tabelas — nada fica guardado no navegador.
async function unwrap(promise) {
  const { data, error } = await promise
  if (error) throw new Error(error.message || 'Erro inesperado. Tente novamente.')
  return data
}

// Colunas listadas de propósito: a coluna "weight" (chance de cada carta) não é pública.
const CARD_COLS = 'id, name, tier, overall, position, club_id, player_key, image, active, meta'

// Entrega as caixas de boas-vindas (1x na vida) e as diárias (1x por dia). Pode chamar sempre que entrar na Home.
export const claimDaily = () => unwrap(supabase.rpc('card_claim_daily'))

export const fetchPendingBoxes = () =>
  unwrap(
    supabase
      .from('reward_boxes')
      .select('id, tier, source, created_at')
      .eq('status', 'pending')
      .order('created_at', { ascending: true })
      .limit(200),
  )

// A caixa que acabou de ser ganha numa vitória (para mostrar na tela de pós-jogo).
export const fetchLatestWinBox = async () => {
  const rows = await unwrap(
    supabase
      .from('reward_boxes')
      .select('id, tier, source, created_at')
      .eq('status', 'pending')
      .eq('source', 'season_win')
      .order('created_at', { ascending: false })
      .limit(1),
  )
  return rows?.[0] || null
}

export const openBox = (boxId) => unwrap(supabase.rpc('box_open', { p_box: boxId }))

export const fetchTiers = () => unwrap(supabase.from('card_tiers').select('*').order('rank'))

export const fetchCatalog = () =>
  unwrap(supabase.from('cards').select(CARD_COLS).eq('active', true).order('overall', { ascending: false }))

// Cartas do jogador (com os dados da carta, inclusive de cartas que saíram de circulação).
export const fetchCollection = () =>
  unwrap(supabase.from('user_cards').select(`qty, first_obtained_at, card:cards(${CARD_COLS})`).gt('qty', 0))

export const discardCard = (cardId, qty) => unwrap(supabase.rpc('card_discard', { p_card: cardId, p_qty: qty }))

export const exchangeDiamonds = (n) => unwrap(supabase.rpc('diamonds_exchange_energy', { p_diamonds: n }))
