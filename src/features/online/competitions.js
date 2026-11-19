// Competições do modo online (supabase/online/38_series.sql): Liga Online A, B, C e D e Copa Online.
import serieA from '../../assets/online/serie_a.webp'
import serieB from '../../assets/online/serie_b.webp'
import serieC from '../../assets/online/serie_c.webp'
import serieD from '../../assets/online/serie_d.webp'
import logoCopa from '../../assets/online/logo_copa.webp'
import logoLiga from '../../assets/online/logo_liga.webp'

export const DIVS = ['A', 'B', 'C', 'D']
export const SERIES = {
  A: { name: 'Liga Online A', logo: serieA, color: '#e2b13c', deep: '#0d4a26', size: 20, format: 'Pontos corridos, turno e returno. Os 4 últimos caem.' },
  B: { name: 'Liga Online B', logo: serieB, color: '#c9d4e4', deep: '#0d2a7a', size: 20, format: '1º e 2º sobem. Do 3º ao 6º, playoff de ida e volta por mais 2 vagas. Os 4 últimos caem.' },
  C: { name: 'Liga Online C', logo: serieC, color: '#e0a274', deep: '#5a1414', size: 24, format: 'Turno único. Os 8 primeiros vão aos quadrangulares: os 2 melhores de cada grupo sobem. Os 4 últimos caem.' },
  D: { name: 'Liga Online D', logo: serieD, color: '#d58cf0', deep: '#2c0b3d', size: 30, format: 'Dois grupos de 15, turno e returno. Os 4 primeiros de cada grupo vão às quartas: quem vence, sobe.' },
}
export const CUP = { name: 'Copa Online', logo: logoCopa, color: '#7fb2ff', deep: '#0b2560' }
export const OLD_LEAGUE = { name: 'Liga Online', logo: logoLiga }

export const STAGE = {
  f1: '1ª fase', f2: '2ª fase', f3: '3ª fase', r16: 'Oitavas de final', qf: 'Quartas de final', sf: 'Semifinal', final: 'Final',
  po: 'Playoff de acesso', quad: 'Quadrangular', r1: '1ª fase',
}
export const STAGE_SHORT = { f1: '1ª fase', f2: '2ª fase', f3: '3ª fase', r16: 'Oitavas', qf: 'Quartas', sf: 'Semi', final: 'Final', po: 'Playoff', quad: 'Quadrangular', r1: '1ª fase' }

// Competição de um jogo: { name, logo, color, detail } — detail = "Rodada 5", "Quartas · ida"...
export function compOf(f) {
  if (!f) return null
  const leg = f.leg ? ` · ${f.leg === 1 ? 'ida' : 'volta'}` : ''
  if (f.comp === 'C') return { ...CUP, key: 'C', detail: `${STAGE[f.stage] || 'Copa'}${leg}`, short: `${STAGE_SHORT[f.stage] || 'Copa'}${leg}` }
  const s = SERIES[f.div] || { ...OLD_LEAGUE, color: '#ffd23f' }
  const detail = f.stage && f.stage !== 'quad' ? `${STAGE[f.stage]}${leg}` : f.stage === 'quad' ? `Quadrangular · rodada ${f.round}` : `Rodada ${f.round}`
  return { ...s, key: f.div || 'L', detail, short: f.stage && f.stage !== 'quad' ? `${STAGE_SHORT[f.stage]}${leg}` : `R${f.round}` }
}

// Zona da tabela pela posição: title, up (acesso), po (playoff), qual (classifica), down (rebaixamento).
export function zoneOf(div, phase, pos, size) {
  if (div === 'A') return pos === 1 ? 'title' : pos > size - 4 ? 'down' : null
  if (div === 'B') return pos <= 2 ? 'up' : pos <= 6 ? 'po' : pos > size - 4 ? 'down' : null
  if (div === 'C') return phase === 2 ? (pos <= 2 ? 'up' : null) : pos <= 8 ? 'qual' : pos > size - 4 ? 'down' : null
  if (div === 'D') return pos <= 4 ? 'qual' : null
  return null
}
export const ZONE_LABEL = {
  title: 'Campeão', up: 'Acesso', po: 'Playoff de acesso', qual: 'Classifica para o mata-mata', down: 'Rebaixamento',
}
export function zonesFor(div, phase) {
  if (div === 'A') return ['title', 'down']
  if (div === 'B') return ['up', 'po', 'down']
  if (div === 'C') return phase === 2 ? ['up'] : ['qual', 'down']
  return ['qual']
}

export const RESULT_LABEL = { champion: 'Campeão', promoted: 'Acesso', relegated: 'Rebaixado', playoff: 'Playoff', quad: 'Quadrangular', qf: 'Mata-mata' }
