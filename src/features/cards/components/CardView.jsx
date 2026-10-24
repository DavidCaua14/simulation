import { useState } from 'react'
import { tierOf } from '../data/tiers'

// A carta. A imagem já traz moldura, nota e nome desenhados (public/cards/<arquivo>); se ela faltar,
// aparece uma carta simples feita em CSS com a cor da raridade, então nada quebra.
// hidden: silhueta ("carta que você ainda não tem").
export default function CardView({ card, width = 140, qty, hidden = false, shine = false, onClick, className = '' }) {
  const [failed, setFailed] = useState(false)
  const t = tierOf(card?.tier)
  const src = card?.image && !failed ? `${import.meta.env.BASE_URL}cards/${card.image}` : null
  const style = { width, '--tier': t.color, '--glow': t.glow }
  const Tag = onClick ? 'button' : 'div'

  return (
    <Tag
      type={onClick ? 'button' : undefined}
      className={`cv ${hidden ? 'is-hidden' : ''} ${shine ? 'has-shine' : ''} ${className}`}
      style={style}
      onClick={onClick}
      aria-label={hidden ? 'Carta ainda não conquistada' : `${card?.name}, ${t.label}, nota ${card?.overall}`}
    >
      {src ? (
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
