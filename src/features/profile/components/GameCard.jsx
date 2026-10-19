import { getRarity } from '../data/cards'
import { UserIcon } from './ProfileIcons'

// Carta no estilo de jogo de futebol: moldura e brilho mudam conforme a raridade.
export default function GameCard({ card }) {
  const rarity = getRarity(card.rarity)
  return (
    <article
      className={`pf-card tier-${rarity.id}`}
      style={{ '--c1': rarity.c1, '--c2': rarity.c2, '--glow': rarity.glow }}
      aria-label={`${card.name}, ${rarity.label}, nota ${card.rating}`}
    >
      <div className="pf-card-top">
        <strong>{card.rating}</strong>
        <span>{card.position}</span>
      </div>
      <div className="pf-card-art">
        <UserIcon size={38} />
      </div>
      <div className="pf-card-name">{card.name}</div>
      <div className="pf-card-tier">{rarity.label}</div>
    </article>
  )
}
