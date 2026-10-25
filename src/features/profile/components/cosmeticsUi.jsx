import './identity.css'
import CosmeticIcon from './CosmeticIcon'

export const KINDS = [
  { id: 'background', label: 'Fundos' },
  { id: 'frame', label: 'Molduras' },
  { id: 'effect', label: 'Efeitos' },
  { id: 'emblem', label: 'Emblemas' },
  { id: 'theme', label: 'Temas' },
]
export const RARITY_LABEL = { comum: 'Comum', raro: 'Raro', epico: 'Épico', lendario: 'Lendário' }

// Miniatura de um cosmético (o mesmo desenho usado no perfil)
export function CosmeticSwatch({ item, size = 54 }) {
  const s = item.style || {}
  const st = { width: size, height: size }
  if (item.kind === 'background') return <span className="cs cs-bg" style={{ ...st, backgroundImage: s.css, backgroundSize: s.size || 'cover' }} />
  if (item.kind === 'frame')
    return (
      <span className={`cs cs-frame ${s.spin ? 'is-spin' : ''}`} style={{ ...st, '--ring': s.ring, '--glow': s.glow || 'transparent' }}>
        <i />
      </span>
    )
  if (item.kind === 'effect') return <span className={`cs cs-fx fx-${s.type}`} style={{ ...st, '--fx-color': s.color }}><i /><i /><i /></span>
  if (item.kind === 'emblem') return <span className="cs cs-emb" style={{ ...st, color: s.color }}><CosmeticIcon name={s.icon} size={size * 0.5} /></span>
  if (item.kind === 'theme') return <span className="cs cs-theme" style={{ ...st, backgroundImage: `linear-gradient(135deg, ${s.accent}, ${s.accent2})` }} />
  return <span className="cs" style={st} />
}
