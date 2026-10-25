export const fmt = (n) => Number(n ?? 0).toLocaleString('pt-BR')

export function timeLeft(iso) {
  const ms = new Date(iso).getTime() - Date.now()
  if (ms <= 0) return 'expirado'
  const h = Math.floor(ms / 3600000)
  if (h >= 24) return `${Math.floor(h / 24)}d ${h % 24}h`
  const m = Math.floor((ms % 3600000) / 60000)
  return h > 0 ? `${h}h ${String(m).padStart(2, '0')}min` : `${m} min`
}

export const STATUS_LABEL = { sold: 'Vendida', cancelled: 'Cancelado', expired: 'Expirado', active: 'À venda' }
