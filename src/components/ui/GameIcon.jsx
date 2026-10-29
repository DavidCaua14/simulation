import { GAME_ICONS } from './gameIcons'

// Ícone ilustrado do jogo (moedas, diamante, energia, extrato...). Decorativo: o texto ao lado dá o significado.
export default function GameIcon({ name, size = 16, className = '', title, style }) {
  const src = GAME_ICONS[name]
  if (!src) return null
  return (
    <img
      src={src}
      width={size}
      height={size}
      alt={title || ''}
      aria-hidden={title ? undefined : 'true'}
      title={title}
      draggable="false"
      decoding="async"
      className={`gx-icon ${className}`}
      style={{ width: size, height: size, ...style }}
    />
  )
}
