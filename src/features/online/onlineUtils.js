// Formatação compartilhada das telas do modo online.
export const money = (n) => `$ ${Math.round(Number(n || 0)).toLocaleString('pt-BR')}`

export const POS_LABEL = {
  GOL: 'Goleiro', LD: 'Lateral-direito', ZAG: 'Zagueiro', LE: 'Lateral-esquerdo', VOL: 'Volante',
  MC: 'Meio-campista', MEI: 'Meia', PD: 'Ponta-direita', PE: 'Ponta-esquerda', ATA: 'Atacante',
}
export const LINE_LABEL = { DEF: 'Defesa', MID: 'Meio-campo', ATT: 'Ataque' }

const dayFmt = new Intl.DateTimeFormat('pt-BR', { weekday: 'short', day: '2-digit', month: '2-digit' })
const timeFmt = new Intl.DateTimeFormat('pt-BR', { hour: '2-digit', minute: '2-digit' })
export const kickoffDay = (iso) => dayFmt.format(new Date(iso)).replace('.', '')
export const kickoffTime = (iso) => timeFmt.format(new Date(iso))
export const dayKey = (iso) => {
  const d = new Date(iso)
  return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`
}

// "em 2 h 05 min", "em 3 dias", "agora". `now` em milissegundos (relógio do servidor).
export function untilKickoff(iso, now) {
  const ms = new Date(iso).getTime() - now
  if (ms <= 0) return 'agora'
  const min = Math.ceil(ms / 60000)
  if (min < 60) return `em ${min} min`
  const h = Math.floor(min / 60)
  if (h < 24) return `em ${h} h ${String(min % 60).padStart(2, '0')} min`
  const days = Math.floor(h / 24)
  return `em ${days} ${days === 1 ? 'dia' : 'dias'}`
}

// Cores do clube online no formato do modo Temporadas ([principal, secundária]).
export const clubColors = (club) => [club?.colors?.a || '#1b3566', club?.colors?.b || '#ffffff']

// Relógio da partida (mesma regra do banco, on_clock): 7 s por minuto, intervalo de 90 s, fim em 12:00.
// Com prorrogação: pausa de 60 s e mais 30 minutos. Devolve minutos com fração (para a animação).
export function matchClock(kickoffMs, nowMs, et = false) {
  const s = (nowMs - kickoffMs) / 1000
  if (s < 0) return -1
  if (s < 315) return s / 7
  if (s < 405) return 45
  if (s < 720) return 45 + (s - 405) / 7
  if (!et || s < 780) return 90
  if (s < 990) return 90 + (s - 780) / 7
  return 120
}
// Fase do relógio para o placar.
export function clockPhase(kickoffMs, nowMs, et = false) {
  const s = (nowMs - kickoffMs) / 1000
  if (s < 0) return 'pre'
  if (s >= 315 && s < 405) return 'ht'
  if (s >= 720 && (!et || s >= 990)) return 'ft'
  if (et && s >= 720 && s < 780) return 'et_wait'
  return 'live'
}

// A tela mostra o jogo ~3 minutos atrás do servidor (24 s reais), para nunca ficar sem lances entre duas consultas (20 s).
export const SCREEN_LAG_MS = 24000

// Encaixe por posição (mesma tabela do modo Temporadas) → notas em cada posição para o campo.
const POSITIONS = ['GOL', 'LD', 'ZAG', 'LE', 'VOL', 'MC', 'MEI', 'PD', 'PE', 'ATA']
export function asSeasonPlayer(p, posFit) {
  const ratings = {}
  for (const pos of POSITIONS) {
    const fit = Math.max(posFit({ position: p.pos }, pos), p.sec?.includes(pos) ? 0.97 : 0)
    ratings[pos] = Math.round(p.ovr * fit)
  }
  return {
    ...p,
    short_name: p.name,
    position: p.pos,
    secondary: p.sec || [],
    overall: Math.round(p.ovr),
    ratings,
    condition: p.cond,
    injured_days: p.injured ? 1 : 0,
    suspended: p.suspended ? 1 : 0,
  }
}

// Tom da carta pela nota (bronze, prata, ouro, craque).
export const cardTier = (ovr, star) => (star ? 'star' : ovr >= 75 ? 'gold' : ovr >= 65 ? 'silver' : 'bronze')
// "$ 150 mil", "$ 1,2 mi" (para espaços curtos)
export function moneyShort(n) {
  const v = Math.round(Number(n || 0))
  if (Math.abs(v) >= 1e6) return `$ ${(v / 1e6).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} mi`
  if (Math.abs(v) >= 1e4) return `$ ${Math.round(v / 1000).toLocaleString('pt-BR')} mil`
  return money(v)
}

// Tempo restante curto: "12:05", "2 h 05", "encerrando".
export function timeLeft(ms) {
  if (!(ms > 0)) return 'encerrando'
  const s = Math.ceil(ms / 1000)
  if (s >= 3600) return `${Math.floor(s / 3600)} h ${String(Math.floor((s % 3600) / 60)).padStart(2, '0')}`
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`
}

// Rótulos dos seis atributos da carta (on_card no banco). O goleiro usa as mesmas chaves com outro significado.
const OUT_LABELS = [['pac', 'VEL'], ['sho', 'FIN'], ['pas', 'PAS'], ['dri', 'DRI'], ['def', 'DEF'], ['phy', 'FIS']]
const GK_LABELS = [['pac', 'ELA'], ['sho', 'MAO'], ['pas', 'REP'], ['dri', 'REF'], ['def', 'VEL'], ['phy', 'POS']]
export const cardLabels = (pos) => (pos === 'GOL' ? GK_LABELS : OUT_LABELS)

// Desenhos e formatos de escudo aceitos por on_club_identity.
export const CREST_PATTERNS = ['stripes', 'hoops', 'plain', 'sash', 'halves', 'chevron']
export const CREST_SHAPES = ['shield', 'round', 'diamond']
