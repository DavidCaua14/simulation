import { useState } from 'react'
import { tierOf } from '../data/tiers'
import AutoCard from './AutoCard'

// A carta. Cartas automáticas (image = 'auto') são desenhadas pelo app (AutoCard). As manuais usam a imagem
// pronta em public/cards/<arquivo> (moldura, nota e nome desenhados); se ela faltar,
// aparece uma carta simples feita em CSS com a cor da raridade, então nada quebra.
// hidden: silhueta ("carta que você ainda não tem").
export default function CardView({ card, width = 140, qty, hidden = false, shine = false, onClick, className = '' }) {
  const [failed, setFailed] = useState(false)
  const t = tierOf(card?.tier)
  const auto = card?.image === 'auto'
  const src = card?.image && !auto && !failed ? `${import.meta.env.BASE_URL}cards/${card.image}` : null
  const style = { width, '--tier': t.color, '--glow': t.glow }
  const Tag = onClick ? 'button' : 'div'

  return (
    <Tag
      type={onClick ? 'button' : undefined}
      className={`cv ${hidden ? 'is-hidden' : ''} ${shine ? 'has-shine' : ''} ${className}`}
      style={style}
      onClick={onClick}
      data-sfx={onClick ? 'select' : undefined}
      aria-label={hidden ? 'Carta ainda não conquistada' : `${card?.name}, ${t.label}, nota ${card?.overall}`}
    >
      {auto ? (
        <AutoCard card={card} />
      ) : src ? (
        <img src={src} alt="" draggable="false" loading="lazy" decoding="async" onError={() => setFailed(true)} />
      ) : (
        <span className="cv-fallback">
          <b>{card?.overall}</b>
          <i>{card?.name}</i>
        </span>
      )}
      {hidden && <span className="cv-q">?</span>}
      {!hidden && qty > 1 && <span className="cv-qty">x{qty}</span>}
      {shine && !hidden && <span className="cv-shine" aria-hidden="true" />}
    </Tag>
  )
}
