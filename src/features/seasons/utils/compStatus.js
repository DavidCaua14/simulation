import { COMPETITIONS, isSwiss, ordinal, phaseOf, stageLabel } from './seasonUtils'

// zona da tabela em que a posição está (configuração: rules.zones -> Libertadores, acesso, rebaixamento, playoff...)
function zoneOf(compId, pos) {
  return (COMPETITIONS[compId]?.rules?.zones || []).find((z) => pos >= z.from && pos <= z.to) || null
}
function bestZone(compId) {
  const zones = COMPETITIONS[compId]?.rules?.zones || []
  return zones.find((z) => z.kind === 'promotion') || zones.find((z) => z.kind === 'continental') || null
}

// Situação atual e próximo objetivo, sempre a partir dos dados reais da competição.
export function compStatus(c) {
  if (c.status === 'finished') return { line: `Campanha: ${c.player_result || 'encerrada'}`, goal: c.player_result === 'Campeão' ? 'Título conquistado!' : 'Encerrado nesta temporada' }
  if (c.status === 'out') return { line: 'Seu clube foi eliminado', goal: 'Volte na próxima temporada' }
  if (c.status === 'not_in') return { line: 'Seu clube não disputa', goal: 'Fora desta edição' }
  if (c.status === 'league_done') return { line: c.table ? `${ordinal(c.table.pos)} lugar na liga` : 'Liga encerrada', goal: `Playoff em andamento: ${stageLabel(c.id, c.stage)}` }
  const t = c.table
  const ph = phaseOf(c.id, c.stage)
  const swiss = isSwiss(c.id)
  const nextPhase = (() => {
    const list = COMPETITIONS[c.id]?.phases || []
    const i = list.findIndex((p) => p.id === c.stage)
    return i >= 0 ? list[i + 1] : null
  })()

  if ((c.stage === 'league' || c.stage === 'group') && t && !t.played) {
    return {
      line: c.stage === 'group' ? `Grupo ${t.group} · sem jogos ainda` : swiss ? 'Fase de liga · sem jogos ainda' : 'Sem jogos ainda',
      goal: c.stage === 'group' ? 'Buscar vaga no mata-mata' : 'Começar bem a campanha',
    }
  }
  if (c.stage === 'league' && t) {
    const z = zoneOf(c.id, t.pos)
    const best = bestZone(c.id)
    const goal = z
      ? z.kind === 'relegation'
        ? swiss ? 'Fora da zona de classificação' : 'Fugir da zona de rebaixamento'
        : `Na zona: ${z.label}`
      : best
        ? `Buscar: ${best.label}`
        : 'Subir na tabela'
    return { line: `${swiss ? 'Fase de liga · ' : ''}${ordinal(t.pos)} lugar · ${t.points} pts`, goal }
  }
  if (c.stage === 'group' && t) {
    return { line: `Grupo ${t.group} · ${ordinal(t.pos)} · ${t.points} pts`, goal: t.pos <= 2 ? 'Classificando ao mata-mata' : 'Buscar vaga no mata-mata' }
  }
  if (!ph) return { line: stageLabel(c.id, c.stage), goal: 'Seguir avançando' }
  if (!nextPhase) return { line: ph.label, goal: 'Vencer a final e levantar a taça' }
  return { line: ph.label, goal: `Avançar: ${nextPhase.label.toLowerCase()}` }
}
