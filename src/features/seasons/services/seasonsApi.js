import { supabase } from '../../../lib/supabaseClient'

// Todo o progresso mora no banco: aqui só chamamos as funções do Supabase
// (supabase/seasons/03_engine.sql). Nada é guardado no navegador.
async function unwrap(promise) {
  const { data, error } = await promise
  if (error) throw new Error(error.message || 'Erro inesperado. Tente novamente.')
  return data
}

// Tela principal: carreira, temporada, campeonatos, propostas e estatísticas.
export const fetchHub = () => unwrap(supabase.rpc('season_hub'))

// Simula a próxima partida do seu clube no campeonato (gasta 1 de energia).
export const playMatch = (competitionId) => unwrap(supabase.rpc('season_play', { p_competition: competitionId }))

export const startNextSeason = () => unwrap(supabase.rpc('season_start_next'))

export const respondOffer = (offerId, accept) =>
  unwrap(supabase.rpc('season_offer_respond', { p_offer: offerId, p_accept: accept }))

export const fetchStandings = (seasonId, competitionId, group = null) =>
  unwrap(supabase.rpc('season_standings', { p_season: seasonId, p_comp: competitionId, p_group: group }))

const FIXTURE_COLS =
  'id, stage, round_no, group_label, tie_no, leg, home_club, away_club, home_goals, away_goals, home_pens, away_pens, tie_winner, status, player_match, player_goals, player_assists, player_rating'

export const fetchFixtures = (seasonId, competitionId) =>
  unwrap(
    supabase
      .from('season_fixtures')
      .select(FIXTURE_COLS)
      .eq('season_id', seasonId)
      .eq('competition_id', competitionId)
      .order('round_no')
      .order('id'),
  )

export const fetchSeasonHistory = () =>
  unwrap(
    supabase
      .from('career_seasons')
      .select('id, season_no, year, club_id, status, matches, wins, draws, losses, goals, assists, xp_earned, coins_earned, summary')
      .order('season_no', { ascending: false }),
  )
