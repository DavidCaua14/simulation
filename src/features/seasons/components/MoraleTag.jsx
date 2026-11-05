import { ArrowDownRight, ArrowRight, ArrowUpRight } from 'lucide-react'

// MORAL (CM17): porcentagem e seta da última semana. Sobe com minutos e vitórias, cai sem jogar e com derrotas.
export default function MoraleTag({ morale, trend = 0, className = '' }) {
  if (morale == null) return null
  const v = Math.round(morale)
  const Icon = trend > 0 ? ArrowUpRight : trend < 0 ? ArrowDownRight : ArrowRight
  const tone = v >= 70 ? 'ok' : v >= 45 ? 'mid' : 'bad'
  return (
    <span className={`mrl t-${tone} ${className}`} title={`Moral ${v}%`} aria-label={`Moral ${v}%`}>
      {v}%
      <Icon size={14} strokeWidth={3} />
    </span>
  )
}
