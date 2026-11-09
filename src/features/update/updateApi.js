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

// versão das novidades dos eventos (tela EventsNews); trocar o id mostra a tela de novo para todos
export const EVENTS_NEWS_RELEASE = '2026-11-eventos'
// versão das novidades dos campeonatos (tela CompetitionsNews)
export const COMPETITIONS_NEWS_RELEASE = '2026-11-campeonatos'
// versão da dica de moral e elenco (tela MoraleNews)
export const MORALE_NEWS_RELEASE = '2026-11-moral-elenco'

// Novidades dos eventos (sem presente): o banco guarda se esta carreira já viu a versão.
export async function fetchNewsStatus(release) {
  const { data, error } = await supabase.rpc('release_news_status', { p_release: release })
  if (error) {
    if (error.code === 'PGRST202' || /release_news_status/.test(error.message || '')) return null
    throw error
  }
  return data
}
export async function markNewsSeen(release) {
  const { error } = await supabase.rpc('release_news_seen', { p_release: release })
  if (error) throw error
}
