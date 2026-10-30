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

// Fotos enviadas pelos jogadores do topo ({ posição: dataURL }), carregadas depois da lista.
export async function fetchRankingPhotos(limit = 50) {
  const { data, error } = await supabase.rpc('ranking_photos', { p_limit: limit })
  if (error) return {}
  return data || {}
}

// Pontos de cada critério (mesma conta do servidor).
export function breakdown(me) {
  return [
    ['Nível', `Nível ${me.level} + ${me.xp ?? 0} XP`, me.level * 100 + Math.floor((me.xp ?? 0) / 10)],
    ['Títulos', `${me.titles} × 500`, me.titles * 500],
    ['Vitórias e empates', `${me.wins} × 20 + ${me.draws} × 7`, me.wins * 20 + me.draws * 7],
    ['Reputação', `${String(me.reputation).replace('.', ',')} × 15`, Math.round(me.reputation * 15)],
    ['Eventos', `${me.events} × 25`, me.events * 25],
    ['Demissões', `${me.fired ?? 0} × −150`, -(me.fired ?? 0) * 150],
  ]
}
