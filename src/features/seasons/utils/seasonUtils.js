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

// "Rodada 12", "Grupo B · Rodada 3", "Oitavas · Ida", "Final · jogo único"
export function describeMatch(m) {
  if (!m) return ''
  if (m.stage === 'league') return `Rodada ${m.round}`
  if (m.stage === 'group') return `Grupo ${m.group} · Rodada ${m.round}`
  if (m.stage === 'final') return 'Final · jogo único'
  const leg = m.leg === 1 ? 'Ida' : 'Volta'
  return `${STAGE_LABEL[m.stage]} · ${leg}`
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
export const STAGE_RANK = { league: 0, group: 1, r16: 2, qf: 3, sf: 4, final: 5 }

// Título de uma rodada: "Rodada 12", "Fase de grupos · Rodada 3", "Oitavas de final · Ida", "Final"
export function roundTitle(stage, round) {
  if (stage === 'league') return `Rodada ${round}`
  if (stage === 'group') return `Fase de grupos · Rodada ${round}`
  if (stage === 'final') return 'Final'
  return `${STAGE_LABEL[stage]} · ${round === 1 ? 'Ida' : 'Volta'}`
}

// Rótulo curto de um jogo cru (linha da tabela season_fixtures)
export function fixtureLabel(f) {
  if (f.stage === 'league') return `Rodada ${f.round_no}`
  if (f.stage === 'group') return `Grupo ${f.group_label} · Rodada ${f.round_no}`
  if (f.stage === 'final') return 'Final'
  return `${STAGE_LABEL[f.stage]} · ${f.leg === 1 ? 'Ida' : 'Volta'}`
}
