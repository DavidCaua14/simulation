import './identity.css'
import { useState } from 'react'
import CosmeticIcon from './CosmeticIcon'
import { BADGE_ART } from '../data/badgeArt'

const TIER = { bronze: 'Bronze', prata: 'Prata', ouro: 'Ouro' }

// Insígnias: conquistadas em cor; bloqueadas em cinza com a regra (como conseguir). Só o servidor concede.
export default function BadgeGrid({ badges = [], showLocked = true }) {
  const [open, setOpen] = useState(null)
  const list = showLocked ? badges : badges.filter((b) => b.earned)
  const earned = badges.filter((b) => b.earned).length
  if (!list.length) return <p className="pf-hint">Nenhuma insígnia conquistada ainda.</p>
  const sel = list.find((b) => b.id === open)
  return (
    <>
      {showLocked && <p className="pf-hint">{earned} de {badges.length} conquistadas. Toque numa insígnia para ver como conseguir.</p>}
      <div className="bg-grid">
        {list.map((b) => (
          <button key={b.id} type="button" className={`bg-item t-${b.tier} ${b.earned ? 'is-on' : ''} ${open === b.id ? 'is-open' : ''}`}
            onClick={() => setOpen(open === b.id ? null : b.id)} aria-label={`${b.label}: ${b.earned ? 'conquistada' : 'bloqueada'}`}>
            {BADGE_ART[b.id] ? (
              <img className="bg-art" src={BADGE_ART[b.id]} alt="" width={64} height={64} loading="lazy" decoding="async" draggable="false" />
            ) : (
              <span className="bg-medal"><CosmeticIcon name={b.icon} size={20} /></span>
            )}
            <span className="bg-label">{b.label}</span>
          </button>
        ))}
      </div>
      {sel && (
        <p className="bg-detail">
          {BADGE_ART[sel.id] && <img className={`bg-detail-art ${sel.earned ? 'is-on' : ''}`} src={BADGE_ART[sel.id]} alt="" width={72} height={72} />}
          <span>
            <b>{sel.label}</b> · {TIER[sel.tier]} — {sel.description}{' '}
            {sel.earned ? `Conquistada em ${new Date(sel.awarded_at).toLocaleDateString('pt-BR')}.` : '(ainda não conquistada)'}
          </span>
        </p>
      )}
    </>
  )
}
