export const XP_PER_LEVEL = 1000
export const FREE_ENERGY = 10
export const RECHARGE_HOURS = 5

export const STAGE_LABEL = {
  league: 'Pontos corridos',
  group: 'Fase de grupos',
  r16: 'Oitavas de final',
  qf: 'Quartas de final',
  sf: 'Semifinal',
  final: 'Final',
}
export const STAGE_ORDER = ['group', 'r16', 'qf', 'sf', 'final']

// ---------------------------------------------------------------------------
// CATÁLOGO DE COMPETIÇÕES (vem do banco: sim_competitions). Formato, fases, rótulos, tema e calendário de
// cada competição ficam na configuração — o app não tem regra fixa por campeonato.
// registerCompetitions() preenche os mapas abaixo (COMP_NAME, COMP_SHORT, COMP_THEME) sem trocar as referências.
export const COMPETITIONS = {}
export function registerCompetitions(list = []) {
  for (const c of list) {
    const { swiss_templates: _omit, ...rules } = c.rules || {}
    COMPETITIONS[c.id] = { ...c, rules, phases: rules.phases || [] }
    COMP_NAME[c.id] = c.name
    COMP_SHORT[c.id] = c.short_name
    if (c.theme?.c1) COMP_THEME[c.id] = { kicker: '', code: '', ...c.theme }
  }
}
// competições da temporada atual, na ordem do calendário (Brasil ou Inglaterra)
export function setSeasonCompetitions(ids = []) {
  COMP_ORDER.splice(0, COMP_ORDER.length, ...ids)
}
const LEGACY_RANK = { league: 0, group: 1, r16: 2, qf: 3, sf: 4, final: 5 }
export const phaseOf = (comp, stage) => COMPETITIONS[comp]?.phases?.find((p) => p.id === stage) || null
export function phaseIndex(comp, stage) {
  const list = COMPETITIONS[comp]?.phases
  const i = list ? list.findIndex((p) => p.id === stage) : -1
  return i >= 0 ? i : LEGACY_RANK[stage] ?? 99
}
export const stageLabel = (comp, stage) => phaseOf(comp, stage)?.label || STAGE_LABEL[stage] || stage
const legsOf = (comp, stage) => {
  const ph = phaseOf(comp, stage)
  return ph ? ph.legs || 1 : stage === 'final' ? 1 : 2
}
export const isSwiss = (comp) => COMPETITIONS[comp]?.phases?.some((p) => p.type === 'swiss')
export const knockoutPhases = (comp) => {
  const list = COMPETITIONS[comp]?.phases
  return list ? list.filter((p) => p.type === 'knockout').map((p) => p.id) : ['r16', 'qf', 'sf', 'final']
}
// "2026" (Brasil) ou "2026/27" (Inglaterra/Europa)
export const seasonLabel = (year, region) => (region === 'ENG' ? `${year}/${String((year + 1) % 100).padStart(2, '0')}` : `${year}`)

// "Rodada 12", "Grupo B · Rodada 3", "Fase de liga · Rodada 4", "Oitavas · Ida", "Quarta fase", "Final · jogo único"
export function describeMatch(m) {
  if (!m) return ''
  const comp = m.competition || m.comp || m.competition_id
  if (m.stage === 'league') return isSwiss(comp) ? `Fase de liga · Rodada ${m.round}` : `Rodada ${m.round}`
  if (m.stage === 'group') return `Grupo ${m.group} · Rodada ${m.round}`
  const label = stageLabel(comp, m.stage)
  if (legsOf(comp, m.stage) === 1) return m.stage === 'final' ? `${label} · jogo único` : label
  return `${label} · ${m.leg === 1 ? 'Ida' : 'Volta'}`
}

export const VENUE_LABEL = { home: 'Em casa', away: 'Fora de casa' }
export const venueLabel = (m) => (m?.neutral ? 'Campo neutro' : VENUE_LABEL[m?.venue] || '')

// Popularidade (0–1000) em faixas, no estilo "fama" de RPG
const POP_TIERS = [
  { at: 0, label: 'Desconhecido' },
  { at: 50, label: 'Promessa' },
  { at: 150, label: 'Conhecido' },
  { at: 300, label: 'Destaque' },
  { at: 500, label: 'Craque' },
  { at: 750, label: 'Ídolo' },
  { at: 950, label: 'Lenda' },
]
export function popularityTier(value = 0) {
  let idx = 0
  POP_TIERS.forEach((t, i) => {
    if (value >= t.at) idx = i
  })
  const cur = POP_TIERS[idx]
  const next = POP_TIERS[idx + 1]
  const pct = next ? ((value - cur.at) / (next.at - cur.at)) * 100 : 100
  return { label: cur.label, next: next?.label, toNext: next ? next.at - value : 0, pct: Math.max(0, Math.min(100, pct)) }
}

export const RESULT_LABEL = { win: 'VITÓRIA', draw: 'EMPATE', loss: 'DERROTA' }
export const resultOf = (my, opp) => (my > opp ? 'win' : my === opp ? 'draw' : 'loss')

export const ratingTone = (r) => (r >= 8 ? 'great' : r >= 6.5 ? 'good' : r >= 5 ? 'mid' : 'bad')

export const fmt = (n) => (n == null ? '—' : Number(n).toLocaleString('pt-BR'))

// Texto "2h 13min" / "45min" / "agora"
export function formatRemaining(ms) {
  if (ms <= 0) return 'agora'
  const totalMin = Math.ceil(ms / 60000)
  const h = Math.floor(totalMin / 60)
  const m = totalMin % 60
  if (h <= 0) return `${m}min`
  return `${h}h ${String(m).padStart(2, '0')}min`
}

export const ordinal = (n) => `${n}º`

export const COMP_NAME = { brasileirao: 'Brasileirão Série A', copa_brasil: 'Copa do Brasil', libertadores: 'Copa Libertadores' }
export const COMP_SHORT = { brasileirao: 'Brasileirão', copa_brasil: 'Copa do Brasil', libertadores: 'Libertadores' }
export const COMP_ORDER = ['brasileirao', 'copa_brasil', 'libertadores']

// Título de uma rodada: "Rodada 12", "Fase de grupos · Rodada 3", "Oitavas de final · Ida", "Final"
export function roundTitle(stage, round, comp) {
  if (stage === 'league') return isSwiss(comp) ? `Fase de liga · Rodada ${round}` : `Rodada ${round}`
  if (stage === 'group') return `Fase de grupos · Rodada ${round}`
  const label = stageLabel(comp, stage)
  if (legsOf(comp, stage) === 1) return label
  return `${label} · ${round === 1 ? 'Ida' : 'Volta'}`
}

// Rótulo curto de um jogo cru (linha da tabela season_fixtures)
export function fixtureLabel(f) {
  const comp = f.comp || f.competition_id
  if (f.stage === 'league') return isSwiss(comp) ? `Fase de liga · Rodada ${f.round_no}` : `Rodada ${f.round_no}`
  if (f.stage === 'group') return `Grupo ${f.group_label} · Rodada ${f.round_no}`
  const label = stageLabel(comp, f.stage)
  if (legsOf(comp, f.stage) === 1) return label
  return `${label} · ${f.leg === 1 ? 'Ida' : 'Volta'}`
}

// ---------------------------------------------------------------------------
// Identidade visual de cada campeonato (cores e símbolo). Não são logos oficiais:
// é um emblema próprio do jogo, com as cores que lembram cada torneio.
export const COMP_THEME = {
  brasileirao: { c1: '#0f8a45', c2: '#f7cf1e', code: 'A', kicker: 'Liga nacional' },
  copa_brasil: { c1: '#1747b8', c2: '#f5b800', code: 'CB', kicker: 'Copa nacional' },
  libertadores: { c1: '#121a33', c2: '#d4af37', code: 'LIB', kicker: 'Continental' },
}

// Regras de prêmio, só para EXIBIR (os cálculos de verdade ficam no banco: season_play e sim_finish_competition).
// Se mudar os números no SQL, mude aqui também.
export const REWARD_RULES = {
  result: [
    { id: 'win', label: 'Vitória', xp: 30, coins: 60 },
    { id: 'draw', label: 'Empate', xp: 15, coins: 25 },
    { id: 'loss', label: 'Derrota', xp: 8, coins: 10 },
  ],
  goal: { xp: 10, coins: 30 },
  assist: { xp: 6, coins: 15 },
  compMult: { brasileirao: 1, copa_brasil: 1.2, libertadores: 1.3 },
  stageMult: [
    { label: 'Oitavas, quartas e semi', mult: 1.2 },
    { label: 'Final', mult: 1.5 },
  ],
  campaign: [
    { label: 'Campeão brasileiro', xp: 500, coins: 3000 },
    { label: 'Campeão da Libertadores', xp: 600, coins: 4000 },
    { label: 'Campeão da Copa do Brasil', xp: 400, coins: 2500 },
    { label: 'G4 do Brasileirão', xp: 250, coins: 1500 },
  ],
}
