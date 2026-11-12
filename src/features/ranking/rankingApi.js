import { supabase } from '../../lib/supabaseClient'

// Ranking geral dos treinadores: só o modo Online pontua (supabase/online/12_ranking_market_hours.sql).
export async function fetchRanking(limit = 50) {
  const { data, error } = await supabase.rpc('ranking_overall', { p_limit: limit })
  if (error) throw new Error(error.message || 'Ranking indisponível no momento.')
  return data
}

const DEFAULT_RULES = { win: 30, draw: 10, goal: 2, goal_cap: 5, clean: 5, human: 10, prep: 5, league: [1000, 600, 400, 250, 150, 100, 50, 50], cup: { champion: 400, final: 200, sf: 80 } }

// Critérios do ranking: só o modo Online pontua. Os valores vêm do servidor (on_config.rank_rules).
export function criteria(rules) {
  const r = { ...DEFAULT_RULES, ...(rules || {}) }
  return [
    ['Vitória', `${r.win} pontos; +${r.human} contra outro técnico`],
    ['Empate', `${r.draw} pontos`],
    ['Gols', `${r.goal} por gol marcado (até ${r.goal_cap} por jogo)`],
    ['Defesa', `${r.clean} por jogo sem sofrer gol`],
    ['Preparação', `${r.prep} por jogo com 100% de preparação`],
    ['Liga', `1º ${r.league[0]} · 2º ${r.league[1]} · 3º ${r.league[2]} · 4º ${r.league[3]} · 5º ${r.league[4]} · 6º ${r.league[5]}`],
    ['Copa', `Campeão ${r.cup.champion} · vice ${r.cup.final} · semifinal ${r.cup.sf}`],
  ]
}

// Fotos enviadas pelos jogadores do topo ({ posição: dataURL }), carregadas depois da lista.
export async function fetchRankingPhotos(limit = 50) {
  const { data, error } = await supabase.rpc('ranking_photos', { p_limit: limit })
  if (error) return {}
  return data || {}
}

// Pontos de cada parcela (somados pelo servidor a cada partida e no fim da temporada).
export function breakdown(me) {
  return [
    ['Resultados', `${me.wins} vitórias · ${me.draws} empates`, me.pts_match ?? 0],
    ['Gols e defesa', `${me.gf ?? 0} gols · ${me.clean ?? 0} sem sofrer`, me.pts_goals ?? 0],
    ['Preparação', `${me.prep ?? 0} jogos com 100%`, me.pts_prep ?? 0],
    ['Liga e copa', `${me.league_titles ?? 0} liga · ${me.cups ?? 0} copa`, me.pts_season ?? 0],
  ]
}
