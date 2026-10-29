import GameIcon from '../../../components/ui/GameIcon'


// Atalho secundário (ranking, eventos, mensagens, convites): pequeno, só ícone e nome.
export default function QuickTile({ mode, onSelect, badge = 0 }) {
  const { title, Icon, locked } = mode
  return (
    <button type="button" className={`hm-quick ${locked ? 'is-locked' : ''}`} disabled={locked} onClick={() => onSelect?.(mode.id)}>
      <span className="hm-quick-icon">
        <Icon size={20} />
        {locked && (
          <span className="hm-quick-lock" aria-hidden="true">
            <GameIcon name="lock" size={9} />
          </span>
        )}
      </span>
      {badge > 0 && !locked && <span className="hm-quick-dot" aria-label={`${badge} para resgatar`}>{badge}</span>}
      <span className="hm-quick-label">{title}</span>
      {locked && <small>Em breve</small>}
    </button>
  )
}
