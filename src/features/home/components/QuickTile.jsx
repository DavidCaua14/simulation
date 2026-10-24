import { Lock } from 'lucide-react'

// Atalho secundário (ranking, eventos, mensagens, convites): pequeno, só ícone e nome.
export default function QuickTile({ mode, onSelect }) {
  const { title, Icon, locked } = mode
  return (
    <button type="button" className={`hm-quick ${locked ? 'is-locked' : ''}`} disabled={locked} onClick={() => onSelect?.(mode.id)}>
      <span className="hm-quick-icon">
        <Icon size={20} />
        {locked && (
          <span className="hm-quick-lock" aria-hidden="true">
            <Lock size={9} />
          </span>
        )}
      </span>
      <span className="hm-quick-label">{title}</span>
      {locked && <small>Em breve</small>}
    </button>
  )
}
