import { STAGE_LABEL, ordinal } from './seasonUtils'

// Situação atual e próximo objetivo, sempre a partir dos dados reais da competição.
export function compStatus(c) {
  if (c.status === 'finished') return { line: `Campanha: ${c.player_result || 'encerrada'}`, goal: c.player_result === 'Campeão' ? 'Título conquistado!' : 'Encerrado nesta temporada' }
  if (c.status === 'out') return { line: 'Seu clube foi eliminado', goal: 'Volte na próxima temporada' }
  if (c.status === 'not_in') return { line: 'Seu clube não disputa', goal: 'Fora desta edição' }
  const t = c.table
  const stage = STAGE_LABEL[c.stage] || ''
  if ((c.stage === 'league' || c.stage === 'group') && t && !t.played) return { line: c.stage === 'group' ? `Grupo ${t.group} · sem jogos ainda` : 'Sem jogos ainda', goal: c.stage === 'group' ? 'Buscar vaga nas oitavas' : 'Começar bem a campanha' }
  if (c.stage === 'league' && t) {
    const goal = t.pos <= 4 ? 'Na zona da Libertadores (G4)' : t.pos > 16 ? 'Fugir da zona de rebaixamento' : 'Buscar o G4'
    return { line: `${ordinal(t.pos)} lugar · ${t.points} pts`, goal }
  }
  if (c.stage === 'group' && t) {
    return { line: `Grupo ${t.group} · ${ordinal(t.pos)} · ${t.points} pts`, goal: t.pos <= 2 ? 'Classificando às oitavas' : 'Buscar vaga nas oitavas' }
  }
  if (c.stage === 'final') return { line: 'Final', goal: 'Vencer a final e levantar a taça' }
  const NEXT = { r16: 'Avançar às quartas de final', qf: 'Avançar à semifinal', sf: 'Chegar à final' }
  return { line: stage, goal: NEXT[c.stage] || 'Seguir avançando' }
}

