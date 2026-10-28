import { supabase } from '../../../lib/supabaseClient'
import { isSessionError } from '../../../lib/sessionRecovery'

// Modo Carreira (treinador): tudo é calculado no banco (supabase/manager/*.sql).
// O app só chama as funções abaixo — nenhum resultado é decidido no navegador.
async function unwrap(promise) {
  const { data, error } = await promise
  if (isSessionError(error)) throw error
  if (error) throw new Error(error.message || 'Erro inesperado. Tente novamente.')
  return data
}

const rpc = (fn, args) => unwrap(supabase.rpc(fn, args))

// Tela principal: treinador, clube, temporada, próximo evento, objetivos, mensagens e propostas
export const fetchHub = () => rpc('mgr_hub')
// Resumo leve para a Home do jogo
export const fetchCoachStatus = () => rpc('mgr_status')

// Elenco (o seu, ou de outro clube para observar) + escalação e táticas salvas
export const fetchSquad = (clubId = null) => rpc('mgr_squad', { p_club: clubId })
export const saveLineup = ({ formation, slots, bench, tactics }) =>
  rpc('mgr_lineup_save', { p_formation: formation, p_slots: slots, p_bench: bench, p_tactics: tactics })
export const autoLineup = (formation = null) => rpc('mgr_lineup_auto', { p_formation: formation })

// Partida ao vivo: começa (1 energia) e avança em etapas. Mudanças valem do minuto atual em diante.
export const startMatch = () => rpc('mgr_match_start')
export const stepMatch = ({ fixtureId, from, to, changes = null, auto = false, afterSeq = 0 }) =>
  rpc('mgr_match_step', { p_fixture: fixtureId, p_from: from, p_to: to, p_changes: changes, p_auto: auto, p_after_seq: afterSeq })
export const fetchMatchReport = (fixtureId) => rpc('mgr_match_report', { p_fixture: fixtureId })

// Calendário: dias sem jogo do seu clube (e a espera por propostas quando está sem clube)
export const advanceDays = (untilOffer = false) => rpc('mgr_advance', { p_until_offer: untilOffer })

export const respondOffer = (offerId, accept) => rpc('mgr_offer_respond', { p_offer: offerId, p_accept: accept })
export const resign = () => rpc('mgr_resign')
export const startNextSeason = () => rpc('mgr_season_next')
export const fetchHistory = () => rpc('mgr_history')
export const fetchTopScorers = (comp = null) => rpc('mgr_top_scorers', { p_comp: comp, p_limit: 20 })
export const markMessagesRead = (ids = null) => rpc('mgr_messages_read', { p_ids: ids })

// Classificação com os critérios de desempate oficiais de cada competição (calculada no banco)
export const fetchStandings = (seasonId, competitionId, group = null) =>
  rpc('season_standings', { p_season: seasonId, p_comp: competitionId, p_group: group })

const FIXTURE_COLS =
  'id, competition_id, stage, round_no, group_label, tie_no, leg, home_club, away_club, home_goals, away_goals, home_pens, away_pens, tie_winner, status, player_match, coach_club, played_at, day_no, extra_time'

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

// Catálogo de competições (formato, fases, tema, calendário). Carregado uma vez por sessão.
let compsPromise = null
export function fetchCompetitions() {
  if (!compsPromise) {
    compsPromise = unwrap(
      supabase
        .from('sim_competitions')
        .select('id, name, short_name, kind, division, region, theme, sort_order, xp_mult, ref_season, rules')
        .eq('active', true)
        .order('sort_order'),
    ).catch((e) => {
      compsPromise = null
      throw e
    })
  }
  return compsPromise
}

