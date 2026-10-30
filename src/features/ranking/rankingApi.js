import { supabase } from '../../lib/supabaseClient'

// Ranking geral dos treinadores (supabase/evolution/44_coach_ranking.sql): nível, Temporadas, reputação e eventos.
export async function fetchRanking(limit = 50) {
  const { data, error } = await supabase.rpc('ranking_overall', { p_limit: limit })
  if (error) throw new Error(error.message || 'Ranking indisponível no momento.')
  return data
}

export const CRITERIA = [
  ['Nível', '100 pontos por nível, mais 1 a cada 10 de XP'],
  ['Títulos', '500 pontos por título no modo Temporadas'],
  ['Vitórias e empates', '20 por vitória e 7 por empate'],
  ['Reputação', '15 por ponto de reputação de técnico (0 a 100)'],
  ['Eventos', '25 por evento concluído'],
  ['Demissões', '−150 por demissão'],
]
