import { supabase } from '../../../lib/supabaseClient' // ← ajuste para o caminho do seu client
import { dayRange, LIVE_LOOKBACK_MS } from '../utils/matchUtils'

const MATCH_COLS =
  'id, competition_id, round, home_team, away_team, home_logo, away_logo, kickoff_at, status, minute, home_score, away_score, odds_home, odds_draw, odds_away, odds_btts_yes, odds_btts_no'

async function unwrap(promise) {
  const { data, error } = await promise
  if (error) throw new Error(error.message)
  return data
}

export const fetchCompetitions = () =>
  unwrap(supabase.from('competitions').select('id, name, tier, emblem, sort_order').order('sort_order').order('id'))

// Jogos 'live' + jogos ainda 'scheduled' no banco cujo horário já passou (a sincronização pode atrasar).
export function fetchLiveMatches() {
  const now = new Date()
  const since = new Date(now.getTime() - LIVE_LOOKBACK_MS).toISOString()
  return unwrap(
    supabase
      .from('matches')
      .select(MATCH_COLS)
      .or(`status.eq.live,and(status.eq.scheduled,kickoff_at.lte.${now.toISOString()},kickoff_at.gte.${since})`)
      .order('kickoff_at'),
  )
}

export function fetchMatchesForDay(dayKey) {
  const { start, end } = dayRange(dayKey)
  return unwrap(
    supabase.from('matches').select(MATCH_COLS).gte('kickoff_at', start).lt('kickoff_at', end).order('kickoff_at'),
  )
}

export const fetchWallet = () =>
  unwrap(supabase.from('careers').select('coins, energy').eq('status', 'active').maybeSingle())

export function placeTicket(stake, picks) {
  return unwrap(
    supabase.rpc('place_ticket', {
      p_stake: stake,
      p_picks: picks.map((p) => ({ match_id: p.match.id, result: p.result, btts: p.btts })),
    }),
  )
}

export const fetchTickets = () =>
  unwrap(
    supabase
      .from('tickets')
      .select(
        `id, stake, multiplier, potential_coins, status, reward_coins, reward_xp, reward_energy, created_at,
         ticket_picks(id, pick_result, pick_btts, multiplier, status,
           matches(id, home_team, away_team, home_score, away_score, status, minute, kickoff_at))`,
      )
      .order('created_at', { ascending: false })
      .limit(40),
  )

export const fetchLeaderboard = () => unwrap(supabase.rpc('get_prediction_leaderboard', { p_limit: 50 }))

export const fetchMyStats = () =>
  unwrap(supabase.from('prediction_stats').select('points, tickets_won, tickets_lost, best_multiplier').maybeSingle())

export async function fetchMyRank() {
  const rows = await unwrap(supabase.rpc('get_my_prediction_rank'))
  return rows?.[0] ?? null
}
