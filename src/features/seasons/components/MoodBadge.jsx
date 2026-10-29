import { moodOf } from '../utils/mood'

export default function MoodBadge({ morale, size = 14, withLabel = false, className = '' }) {
  const m = moodOf(morale)
  if (!m) return null
  const text = `${m.label} (${Math.round(morale)}%)`
  return (
    <span className={`mood m-${m.id} ${withLabel ? 'has-label' : ''} ${className}`} title={text} aria-label={`Satisfação: ${text}`} role="img">
      <m.Icon size={size} strokeWidth={2.4} aria-hidden="true" />
      {withLabel && <span>{m.label}</span>}
    </span>
  )
}
