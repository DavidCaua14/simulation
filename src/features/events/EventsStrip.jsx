import { ChevronRight, Gift } from 'lucide-react'
import { BANNER_ICONS, timeLeft, useNow } from './eventsUi'

// Faixa da Home: recompensas prontas para resgatar (prioridade) ou o evento especial em andamento/próximo.
export default function EventsStrip({ count, feature, onOpen }) {
  const now = useNow()
  if (!count && !feature) return null
  const Icon = (feature && BANNER_ICONS[feature.banner?.icon]) || Gift
  return (
    <button type="button" className={`hm-events ${count ? 'is-ready' : ''}`} onClick={onOpen}
      style={{ backgroundImage: feature?.banner?.css || 'linear-gradient(135deg,#1b1f27,#d97706)' }}>
      <span className="hm-events-icon" aria-hidden="true">{count ? <Gift size={22} /> : <Icon size={22} />}</span>
      <span className="hm-events-main">
        {count ? (
          <>
            <small>Eventos</small>
            <strong>{count} {count === 1 ? 'recompensa pronta' : 'recompensas prontas'}</strong>
            <em>Toque para resgatar</em>
          </>
        ) : (
          <>
            <small>{feature.live ? 'Evento especial · acontecendo' : 'Evento especial · em breve'}</small>
            <strong>{feature.name}</strong>
            <em>{feature.live ? `termina em ${timeLeft(feature.ends_at, now)}` : `começa em ${timeLeft(feature.starts_at, now)}`}</em>
          </>
        )}
      </span>
      <ChevronRight size={18} />
    </button>
  )
}
