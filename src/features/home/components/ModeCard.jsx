import { ChevronRightIcon } from '../../../components/ui/icons'

export default function ModeCard({ mode, onSelect }) {
  const { title, desc, Icon, image, locked } = mode

  return (
    <button
      type="button"
      className={`mode-card ${image ? 'has-image' : ''}`}
      disabled={locked}
      onClick={() => onSelect?.(mode.id)}
    >
      {image && (
        <>
          <img className="mode-card-bg" src={image} alt="" />
          <span className="mode-card-scrim" />
        </>
      )}

      {locked && <span className="mode-card-lock">Em breve</span>}

      <span className="mode-card-icon">
        <Icon />
      </span>
      <span className="mode-card-text">
        <strong>{title}</strong>
        <span>{desc}</span>
      </span>
      {!image && <ChevronRightIcon className="mode-card-chevron" />}
    </button>
  )
}
