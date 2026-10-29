import GameIcon from '../../../components/ui/GameIcon'


// Modo de jogo com imagem. `size`: 'tall' (destaque) ou 'wide'.
// Estado vem do próprio modo (data/gameModes.js): locked = "Em breve".
export default function PlayModeCard({ mode, size = 'tall', badge, onSelect }) {
  const { title, desc, Icon, image, locked } = mode
  return (
    <button
      type="button"
      className={`hm-mode is-${size} ${locked ? 'is-locked' : ''}`}
      disabled={locked}
      onClick={() => onSelect?.(mode.id)}
      aria-label={locked ? `${title} — em breve` : title}
    >
      {image && <img className="hm-mode-bg" src={image} alt="" />}
      <span className="hm-mode-scrim" aria-hidden="true" />
      <span className="hm-mode-state">
        {locked ? (
          <span className="gx-tag is-soon">
            <GameIcon name="lock" size={16} /> Em breve
          </span>
        ) : (
          badge || (
            <span className="gx-tag is-live">
              <span className="gx-dot" /> Disponível
            </span>
          )
        )}
      </span>
      <span className="hm-mode-body">
        <span className="hm-mode-icon">
          <Icon size={18} />
        </span>
        <strong>{title}</strong>
        <span className="hm-mode-desc">{desc}</span>
      </span>
    </button>
  )
}
