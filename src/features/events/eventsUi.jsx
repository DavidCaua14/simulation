import { useEffect, useState } from 'react'
import { Activity, Award, CalendarDays, Coins, Crown, Flame, Gem, Gift, Layers, Palette, Sparkles, Star, Trophy, Zap } from 'lucide-react'

export const BANNER_ICONS = { activity: Activity, trophy: Trophy, flame: Flame, star: Star, layers: Layers, crown: Crown, calendar: CalendarDays, gift: Gift, sparkles: Sparkles }
export const CATEGORY_LABEL = { daily: 'Diário', weekly: 'Semanal', themed: 'Especial', collection: 'Coleção' }

// relógio da tela (atualiza a cada 30 s) — o tempo restante vem das datas reais do servidor
export function useNow(step = 30000) {
  const [now, setNow] = useState(() => Date.now())
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), step)
    return () => clearInterval(t)
  }, [step])
  return now
}

export function timeLeft(to, now) {
  const ms = new Date(to).getTime() - now
  if (ms <= 0) return 'agora'
  const m = Math.ceil(ms / 60000)
  const d = Math.floor(m / 1440)
  const h = Math.floor((m % 1440) / 60)
  if (d >= 1) return `${d}d ${h}h`
  if (h >= 1) return `${h}h ${String(m % 60).padStart(2, '0')}min`
  return `${m} min`
}

export const fmtDate = (iso, withYear = false) =>
  new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', ...(withYear ? { year: 'numeric' } : {}), hour: '2-digit', minute: '2-digit', timeZone: 'America/Sao_Paulo' })

export function rewardText(r) {
  switch (r.kind) {
    case 'coins': return `${Number(r.amount).toLocaleString('pt-BR')} moedas`
    case 'diamonds': return `${r.amount} ${r.amount === 1 ? 'diamante' : 'diamantes'}`
    case 'energy': return `${r.amount} de energia bônus`
    case 'cosmetic': return `Visual: ${r.label || r.ref}`
    case 'badge': return `Insígnia: ${r.label || r.ref}`
    default: return r.kind
  }
}

export function RewardChip({ r }) {
  if (r.kind === 'box' || r.kind === 'card') return null // historical records remain auditable, without an acquisition action
  let icon
  if (r.kind === 'coins') icon = <Coins size={13} className="ev-ic-coins" />
  else if (r.kind === 'diamonds') icon = <Gem size={13} className="ev-ic-gems" />
  else if (r.kind === 'energy') icon = <Zap size={13} fill="currentColor" className="ev-ic-energy" />
  else if (r.kind === 'cosmetic') icon = <Palette size={13} className="ev-ic-gold" />
  else if (r.kind === 'badge') icon = <Award size={13} className="ev-ic-gold" />
  else icon = <Gift size={13} />
  return <span className="ev-chip">{icon}{rewardText(r)}</span>
}
