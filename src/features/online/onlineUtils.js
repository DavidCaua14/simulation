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
