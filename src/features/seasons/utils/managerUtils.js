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

// ---- Táticas do CM17 (evolução 64): o servidor deriva as chaves internas do motor a partir destas ----
export const DEFAULT_TACTICS = { style: 'neutral', attack: 'mixed', passing: 'mixed', tackling: 'balanced', tempo: 'normal', marking: 'medium', long_shots: 'sometimes', set_pieces: 'cross', crossing: 'mixed' }

export const TACTIC_GROUPS = [
  {
    id: 'style',
    label: 'Estilo',
    column: true,
    options: [
      { v: 'defensive', label: 'Defensivo', effect: 'Time recuado: sofre menos gols e cria menos.' },
      { v: 'neutral', label: 'Neutro', effect: 'Equilíbrio entre atacar e defender.' },
      { v: 'attacking', label: 'Ataque', effect: 'Mais gente no ataque: cria mais e se expõe mais.' },
      { v: 'counter', label: 'Contra', effect: 'Defende baixo e sai rápido: transições perigosas, menos posse.' },
    ],
  },
  {
    id: 'attack',
    label: 'Ataque',
    column: true,
    options: [
      { v: 'left', label: 'Ponta esquerda', effect: 'Jogadas pelo lado esquerdo, com cruzamentos.' },
      { v: 'right', label: 'Ala direita', effect: 'Jogadas pelo lado direito, com cruzamentos.' },
      { v: 'both', label: 'Duas alas', effect: 'Ataque aberto pelos dois lados.' },
      { v: 'central', label: 'Central', effect: 'Jogadas por dentro, finalizações um pouco melhores.' },
      { v: 'mixed', label: 'Misto', effect: 'Usa o meio e as pontas.' },
    ],
  },
  { id: 'passing', label: 'Passe', options: [
    { v: 'short', label: 'Curto', effect: 'Mais posse e chances melhores, porém menos frequentes.' },
    { v: 'mixed', label: 'Misto', effect: 'Alterna passes curtos e longos.' },
    { v: 'long', label: 'Longo', effect: 'Chega mais vezes ao ataque, com finalizações piores e mais impedimentos.' },
  ] },
  { id: 'tackling', label: 'Desarme', options: [
    { v: 'light', label: 'Leve', effect: 'Menos faltas e cartões.' },
    { v: 'balanced', label: 'Equilibrado', effect: 'Disputa normal.' },
    { v: 'heavy', label: 'Pesado', effect: 'Rouba mais bolas, com mais faltas e cartões.' },
  ] },
  { id: 'tempo', label: 'Ritmo', options: [
    { v: 'slow', label: 'Lento', effect: 'Mais posse e menos cansaço, com menos finalizações.' },
    { v: 'normal', label: 'Médio', effect: 'Ritmo padrão.' },
    { v: 'fast', label: 'Rápido', effect: 'Mais chegadas e chutes, mais cansaço.' },
  ] },
  { id: 'marking', label: 'Marcação', options: [
    { v: 'low', label: 'Pouca', effect: 'Time compacto e descansado; o rival fica mais com a bola.' },
    { v: 'medium', label: 'Média', effect: 'Equilíbrio entre pressionar e poupar energia.' },
    { v: 'high', label: 'Alta', effect: 'Pressão e linha alta: recupera mais bolas, cansa mais e deixa espaço nas costas.' },
  ] },
  { id: 'long_shots', label: 'Chutes longos', options: [
    { v: 'often', label: 'Freq', effect: 'Chuta muito de fora da área: mais finalizações, de qualidade menor. Bom com bons finalizadores.' },
    { v: 'sometimes', label: 'Às vezes', effect: 'Chuta de fora quando aparece a chance.' },
    { v: 'rarely', label: 'Raro', effect: 'Só finaliza de perto: menos chutes, mais qualidade.' },
  ] },
  { id: 'set_pieces', label: 'Bola parada', options: [
    { v: 'shoot', label: 'Chute', effect: 'Faltas cobradas direto pelo batedor de falta.' },
    { v: 'cross', label: 'Cruz.', effect: 'Faltas e escanteios levantados na área: bom com cabeceadores.' },
    { v: 'short', label: 'Curto', effect: 'Cobranças curtas: mantém a posse, gera pouco perigo.' },
  ] },
  { id: 'crossing', label: 'Cruzamento', options: [
    { v: 'byline', label: 'Fundo', effect: 'Vai à linha de fundo: muitos cabeceios.' },
    { v: 'deep', label: 'L. de fundo', effect: 'Cruza de trás: cabeceios frequentes.' },
    { v: 'mixed', label: 'Misto', effect: 'Varia os cruzamentos.' },
    { v: 'rarely', label: 'Raro', effect: 'Quase não cruza: jogo pelo chão.' },
  ] },
]

// Táticas gravadas antes da evolução 64 (ou vindas da IA) só têm as chaves internas: converte para o CM17.
export function toCM(t = {}) {
  if (!t) return { ...DEFAULT_TACTICS }
  const m = Number(t.mentality || 0)
  return {
    ...DEFAULT_TACTICS,
    style: t.style || (m < 0 ? 'defensive' : m > 0 ? 'attacking' : 'neutral'),
    attack: t.attack || ({ wide: 'both', center: 'central' }[t.width] ?? 'mixed'),
    passing: t.passing || ({ short: 'short', direct: 'long' }[t.build] ?? 'mixed'),
    tackling: t.tackling || ({ cautious: 'light', aggressive: 'heavy' }[t.tackles] ?? 'balanced'),
    tempo: t.tempo || 'normal',
    marking: t.marking || t.pressing || 'medium',
    long_shots: t.long_shots || 'sometimes',
    set_pieces: t.set_pieces || 'cross',
    crossing: t.crossing || ({ wide: 'byline', center: 'rarely' }[t.width] ?? 'mixed'),
  }
}
// Só as chaves do CM17 vão ao servidor: ele deriva as internas (postura, construção, pressão...).
export const cmOnly = (t) => Object.fromEntries(Object.keys(DEFAULT_TACTICS).map((k) => [k, toCM(t)[k]]))
export const tacticLabel = (group, v) => TACTIC_GROUPS.find((g) => g.id === group)?.options.find((o) => o.v === v)?.label ?? v

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

export const END_REASON = { fired: 'Demitido', left: 'Saiu para outro clube', resigned: 'Pediu demissão', expired: 'Contrato encerrado' }

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
  squad: { label: 'Elenco', tone: 'squad' },
  transfer: { label: 'Negociação', tone: 'offer' },
  contract: { label: 'Contrato', tone: 'squad' },
  finance: { label: 'Finanças', tone: 'board' },
}

// Assuntos da caixa de mensagens (categoria gravada no banco; mensagens antigas sem categoria ficam em Clube).
export const MSG_CATEGORIES = [
  { id: 'all', label: 'Todas' },
  { id: 'squad', label: 'Elenco', hint: 'Moral, lesões e contratos' },
  { id: 'market', label: 'Mercado', hint: 'Propostas recebidas e respostas das negociações' },
  { id: 'club', label: 'Clube', hint: 'Diretoria, torcida, departamento médico e resultados' },
  { id: 'career', label: 'Carreira', hint: 'Propostas de trabalho para você' },
  { id: 'world', label: 'Mundo', hint: 'Notícias do futebol: contratações, técnicos e resultados' },
]
export const msgCategory = (m) => m.category || (m.kind === 'offer' ? 'career' : 'club')
export const MSG_ACTIONS = {
  open_negotiations: 'Ver negociação',
  open_player: 'Ver no elenco',
  open_finance: 'Ver finanças',
  open_offers: 'Ver propostas',
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
