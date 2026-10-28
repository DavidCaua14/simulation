import { COMPETITIONS } from './seasonUtils'
// Textos e regras de EXIBIÇÃO do modo Carreira (treinador).
// Os números de verdade (motor de partidas, diretoria, demissão) ficam no banco:
// supabase/manager/03_engine.sql e 04_career.sql. Se mudar lá, ajuste os textos aqui.

export const POS_ORDER = ['GOL', 'LD', 'ZAG', 'LE', 'VOL', 'MC', 'MEI', 'PD', 'PE', 'ATA']
export const POS_NAME = {
  GOL: 'Goleiro', LD: 'Lateral-direito', ZAG: 'Zagueiro', LE: 'Lateral-esquerdo', VOL: 'Volante',
  MC: 'Meio-campista', MEI: 'Meia', PD: 'Ponta-direita', PE: 'Ponta-esquerda', ATA: 'Atacante',
}
export const POS_LINE = { GOL: 'GK', LD: 'DEF', ZAG: 'DEF', LE: 'DEF', VOL: 'MID', MC: 'MID', MEI: 'MID', PD: 'ATT', PE: 'ATT', ATA: 'ATT' }
export const LINE_NAME = { GK: 'Goleiros', DEF: 'Defensores', MID: 'Meio-campo', ATT: 'Ataque' }
export const LINES = ['GK', 'DEF', 'MID', 'ATT']

// Atributos (escala 1–99) agrupados para a ficha do jogador
export const ATTR_GROUPS = [
  { id: 'gk', label: 'Goleiro', attrs: [['gk_reflexes', 'Reflexos'], ['gk_handling', 'Defesa'], ['gk_positioning', 'Posicionamento']] },
  { id: 'def', label: 'Defesa', attrs: [['marking', 'Marcação'], ['tackling', 'Desarme'], ['positioning', 'Posicionamento'], ['heading', 'Jogo aéreo']] },
  { id: 'mid', label: 'Construção', attrs: [['passing', 'Passe'], ['vision', 'Visão de jogo'], ['technique', 'Controle de bola']] },
  { id: 'att', label: 'Ataque', attrs: [['finishing', 'Finalização'], ['off_ball', 'Movimentação'], ['dribbling', 'Drible']] },
  { id: 'phy', label: 'Físico', attrs: [['pace', 'Velocidade'], ['stamina', 'Resistência'], ['strength', 'Força']] },
]

// ---- Táticas: mesmas opções e efeitos do motor (03_engine.sql) ----
export const DEFAULT_TACTICS = { mentality: 0, pressing: 'medium', line: 'medium', tempo: 'normal', build: 'mixed', width: 'mixed', manage: 'normal', tackles: 'normal' }

export const MENTALITY = [
  { v: -2, label: 'Retranca', short: 'Retranca' },
  { v: -1, label: 'Defensiva', short: 'Defens.' },
  { v: 0, label: 'Equilibrada', short: 'Equil.' },
  { v: 1, label: 'Ofensiva', short: 'Ofens.' },
  { v: 2, label: 'Tudo ao ataque', short: 'Ataque' },
]

export const TACTIC_GROUPS = [
  {
    id: 'tackles',
    label: 'Entradas',
    options: [
      { v: 'cautious', label: 'Cautelosas', effect: 'Menos faltas e risco disciplinar. Útil para proteger atletas já advertidos.' },
      { v: 'normal', label: 'Normais', effect: 'Disputa equilibrada. Técnica, disciplina, cansaço e rigor da arbitragem influenciam os cartões.' },
      { v: 'aggressive', label: 'Firmes', effect: 'Mais contato e faltas, com maior risco de cartões e expulsões. Use com cuidado.' },
    ],
  },
  {
    id: 'pressing',
    label: 'Pressão na saída de bola',
    options: [
      { v: 'low', label: 'Baixa', effect: 'Time compacto e descansado: cansa bem menos e faz menos faltas, mas o rival fica mais com a bola.' },
      { v: 'medium', label: 'Média', effect: 'Equilíbrio entre recuperar a bola e poupar energia.' },
      { v: 'high', label: 'Alta', effect: 'Rouba mais bolas e cria mais jogadas, mas o desgaste físico sobe muito e saem mais faltas e cartões.' },
    ],
  },
  {
    id: 'line',
    label: 'Linha defensiva',
    options: [
      { v: 'low', label: 'Recuada', effect: 'Menos espaço nas costas e quase nenhum impedimento do rival, porém ele chega mais vezes à sua área.' },
      { v: 'medium', label: 'Média', effect: 'Posição padrão da defesa.' },
      { v: 'high', label: 'Adiantada', effect: 'O rival ataca menos e cai mais em impedimento, mas atacantes rápidos levam vantagem nas costas.' },
    ],
  },
  {
    id: 'tempo',
    label: 'Ritmo de jogo',
    options: [
      { v: 'slow', label: 'Cadenciado', effect: 'Mais posse e menos cansaço, com menos finalizações.' },
      { v: 'normal', label: 'Normal', effect: 'Ritmo padrão.' },
      { v: 'fast', label: 'Acelerado', effect: 'Mais transições e chutes, mais cansaço e menos controle da posse.' },
    ],
  },
  {
    id: 'build',
    label: 'Construção',
    options: [
      { v: 'short', label: 'Passes curtos', effect: 'Mais posse e chances de melhor qualidade, porém menos frequentes.' },
      { v: 'mixed', label: 'Mista', effect: 'Alterna passes curtos e longos.' },
      { v: 'direct', label: 'Bola longa', effect: 'Chega mais vezes ao ataque, com finalizações piores e mais impedimentos.' },
    ],
  },
  {
    id: 'width',
    label: 'Foco do ataque',
    options: [
      { v: 'center', label: 'Pelo meio', effect: 'Jogadas trabalhadas por dentro: menos cruzamentos, finalizações um pouco melhores.' },
      { v: 'mixed', label: 'Variado', effect: 'Usa o meio e as pontas.' },
      { v: 'wide', label: 'Pelas pontas', effect: 'Muitos cruzamentos: cabeceadores e jogo aéreo ganham importância.' },
    ],
  },
  {
    id: 'manage',
    label: 'Gestão do resultado',
    options: [
      { v: 'keep', label: 'Segurar', effect: 'Quando estiver vencendo, recua automaticamente a partir dos 70 minutos.' },
      { v: 'normal', label: 'Normal', effect: 'Mantém a postura escolhida o jogo todo.' },
      { v: 'push', label: 'Buscar', effect: 'Sem estar vencendo, avança automaticamente a partir dos 60 minutos.' },
    ],
  },
]

export const MENTALITY_EFFECT =
  'Mais ofensiva = mais chances criadas e defesa mais exposta. Mais defensiva = menos gols sofridos e menos presença no ataque.'

export const tacticLabel = (group, v) => TACTIC_GROUPS.find((g) => g.id === group)?.options.find((o) => o.v === v)?.label ?? v
export const mentalityLabel = (v) => MENTALITY.find((m) => m.v === Number(v))?.label ?? 'Equilibrada'

// ---- Tons visuais ----
export const fitTone = (fit) => (fit >= 0.97 ? 'ok' : fit >= 0.86 ? 'warn' : 'bad')
export const condTone = (c) => (c >= 85 ? 'ok' : c >= 70 ? 'warn' : 'bad')
export const ovrTone = (o) => (o >= 80 ? 'elite' : o >= 72 ? 'good' : o >= 64 ? 'mid' : 'low')

// ---- Diretoria / torcida / reputação ----
export function boardMood(v) {
  if (v >= 75) return { label: 'Muito satisfeita', tone: 'ok' }
  if (v >= 55) return { label: 'Satisfeita', tone: 'ok' }
  if (v >= 35) return { label: 'Atenta', tone: 'warn' }
  if (v >= 22) return { label: 'Preocupada', tone: 'bad' }
  return { label: 'Ultimato', tone: 'bad' }
}
export function fansMood(v) {
  if (v >= 75) return { label: 'Em festa', tone: 'ok' }
  if (v >= 55) return { label: 'Confiante', tone: 'ok' }
  if (v >= 35) return { label: 'Desconfiada', tone: 'warn' }
  if (v >= 20) return { label: 'Irritada', tone: 'bad' }
  return { label: 'Protestando', tone: 'bad' }
}
const REP_TIERS = [
  { at: 0, label: 'Desconhecido' },
  { at: 20, label: 'Promissor' },
  { at: 35, label: 'Respeitado' },
  { at: 50, label: 'Renomado' },
  { at: 65, label: 'Consagrado' },
  { at: 80, label: 'Lenda do banco' },
]
export function reputationTier(v = 0) {
  let i = 0
  REP_TIERS.forEach((t, k) => {
    if (v >= t.at) i = k
  })
  return { label: REP_TIERS[i].label, stars: Math.max(0.5, Math.min(5, Math.round((v / 20) * 2) / 2)) }
}

export const END_REASON = { fired: 'Demitido', left: 'Saiu para outro clube', resigned: 'Pediu demissão' }

export const winRate = (w = 0, d = 0, l = 0) => {
  const j = w + d + l
  return j ? Math.round(((w * 3 + d) / (j * 3)) * 100) : 0
}

// ---- Narração dos lances ----
export function eventText(e, name) {
  const p = e.player_name || 'Jogador'
  const p2 = e.player2_name
  switch (e.kind) {
    case 'kickoff': return 'Bola rolando!'
    case 'goal': return `GOL! ${p}${e.detail ? ` ${e.detail}` : ''}${p2 ? ` · assistência de ${p2}` : ''}`
    case 'pen_goal': return `GOL de pênalti! ${p} bate e converte`
    case 'pen_miss': return e.detail === 'defendido' ? `Pênalti defendido! ${p2 || 'O goleiro'} pega a cobrança de ${p}` : `${p} cobra o pênalti para fora!`
    case 'save': return `${e.detail === 'grande chance' ? 'Que defesa! ' : 'Defesa de '}${p2 || 'goleiro'}${e.detail === 'grande chance' ? ` salva o chute de ${p}` : ` no chute de ${p}`}`
    case 'shot_off': return e.detail === 'bloqueado' ? `Chute de ${p} travado pela defesa` : e.detail === 'grande chance' ? `${p} perde uma chance incrível!` : `${p} finaliza para fora`
    case 'offside': return `Impedimento de ${p}`
    case 'yellow': return `Cartão amarelo para ${p}`
    case 'second_yellow': return `Segundo amarelo: ${p} está expulso!`
    case 'red': return `Cartão vermelho direto! ${p} expulso`
    case 'injury': return `${p} sente uma lesão e não pode continuar`
    case 'sub': return `Substituição: entra ${p}${p2 ? `, sai ${p2}` : ''}${e.detail ? ` (${e.detail})` : ''}`
    case 'tactic': return `${name || 'Time'}: ${e.detail || 'ajuste tático'}`
    case 'ht': return 'Intervalo'
    case 'et': return 'Empate no tempo normal: prorrogação!'
    case 'ft': return 'Fim de jogo'
    case 'so_goal': return `Pênaltis: ${p} converte`
    case 'so_miss': return `Pênaltis: ${p} desperdiça${p2 ? ` (${p2} defende)` : ''}`
    default: return e.kind
  }
}
export const MAJOR_EVENTS = new Set(['goal', 'pen_goal', 'pen_miss', 'second_yellow', 'red', 'injury', 'ht', 'ft', 'et'])
export const isGoal = (e) => e.kind === 'goal' || e.kind === 'pen_goal'

// "Objetivo: terminar no G4 · hoje: 6º"
export function objectiveProgress(o, leaguePlayed = null) {
  if (o.kind === 'league_pos') {
    if (o.current == null || leaguePlayed === 0) return { text: 'ainda sem jogos', tone: 'mid' }
    const ok = o.current <= o.target
    return { text: `hoje: ${o.current}º`, tone: o.status === 'met' ? 'ok' : o.status === 'failed' ? 'bad' : ok ? 'ok' : o.current <= o.target + 3 ? 'warn' : 'bad' }
  }
  const STAGES = ['—', 'grupos', 'oitavas', 'quartas', 'semifinal', 'final', 'título']
  // rótulo da fase pela configuração da competição (ex.: FA Cup "terceira fase"); senão, o genérico
  const phases = COMPETITIONS[o.competition]?.phases || []
  const ph = o.current >= 1 && o.current <= 5 ? [...phases].reverse().find((p) => p.rank === o.current) : null
  const cur = o.current === 6 ? 'título' : ph?.type === 'swiss' ? 'fase de liga' : ph && ph.type !== 'groups' ? ph.label.toLowerCase() : STAGES[o.current] || '—'
  if (o.status === 'met') return { text: 'cumprido', tone: 'ok' }
  if (o.status === 'failed') return { text: 'não cumprido', tone: 'bad' }
  return { text: o.alive === false ? `eliminado (${cur})` : `chegou: ${cur}`, tone: o.alive === false ? 'bad' : o.current >= o.target ? 'ok' : 'mid' }
}

export const MSG_KIND = {
  board: { label: 'Diretoria', tone: 'board' },
  fans: { label: 'Torcida', tone: 'fans' },
  medical: { label: 'Médico', tone: 'medical' },
  offer: { label: 'Proposta', tone: 'offer' },
  result: { label: 'Resultado', tone: 'result' },
  system: { label: 'Clube', tone: 'system' },
  press: { label: 'Imprensa', tone: 'press' },
  title: { label: 'Título', tone: 'title' },
}

// Força de uma escalação, por setor (média das notas na posição de cada vaga)
export function lineupStrength(formation, slots, playersById) {
  if (!formation) return null
  const acc = { GK: [], DEF: [], MID: [], ATT: [] }
  for (const s of formation.slots) {
    const p = playersById[slots?.[s.slot]]
    if (!p) continue
    acc[POS_LINE[s.pos]].push(p.ratings?.[s.pos] ?? 40)
  }
  const avg = (a) => (a.length ? Math.round(a.reduce((x, y) => x + y, 0) / a.length) : 0)
  const all = Object.values(acc).flat()
  return { gk: avg(acc.GK), def: avg(acc.DEF), mid: avg(acc.MID), att: avg(acc.ATT), overall: avg(all) }
}

// Adequação à posição — mesmos valores padrão de sim_position_fit (01_schema.sql)
const NEAR_93 = new Set(['LD>LE', 'LE>LD', 'PD>PE', 'PE>PD', 'VOL>MC', 'MC>VOL', 'MC>MEI', 'MEI>MC'])
const NEAR_88 = new Set(['ZAG>VOL', 'VOL>ZAG', 'LD>ZAG', 'LE>ZAG', 'ZAG>LD', 'ZAG>LE', 'MEI>PD', 'MEI>PE', 'PD>MEI', 'PE>MEI', 'PD>ATA',
  'PE>ATA', 'ATA>PD', 'ATA>PE', 'MEI>ATA', 'ATA>MEI', 'LD>PD', 'LE>PE', 'PD>LD', 'PE>LE'])
const NEXT_LINE = new Set(['DEF>MID', 'MID>DEF', 'MID>ATT', 'ATT>MID'])
export function posFit(player, pos) {
  if (!player) return 1
  const from = player.position
  if (from === pos) return 1
  let fit
  if (from === 'GOL' || pos === 'GOL') fit = 0.45
  else if (NEAR_93.has(`${from}>${pos}`)) fit = 0.93
  else if (NEAR_88.has(`${from}>${pos}`)) fit = 0.88
  else if (POS_LINE[from] === POS_LINE[pos]) fit = 0.85
  else if (NEXT_LINE.has(`${POS_LINE[from]}>${POS_LINE[pos]}`)) fit = 0.78
  else fit = 0.65
  return player.secondary?.includes(pos) ? Math.max(fit, 0.97) : fit
}
