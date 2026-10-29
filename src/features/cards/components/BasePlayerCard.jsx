import CardView from './CardView'
import '../cards.css'
import './base-player-card.css'

// The existing base card is also the presentation of a season player. The
// displayed rating comes from the current squad/position, never the old catalog.
export default function BasePlayerCard({ player, position, overall, width = 100, colors, className = '' }) {
  if (!player) return null
  const card = {
    id: player.id,
    player_key: player.id,
    tier: 'basica',
    image: 'auto',
    name: player.short_name || player.name || '',
    position: position || player.position || player.natural || player.pos,
    overall: Math.round(overall ?? player.overall ?? player.ratings?.[position || player.position] ?? 0),
    club_id: player.club_id,
    meta: { number: player.number, nationality: player.nationality, club_name: player.club_name, colors },
  }
  return <CardView as="span" card={card} width={width} className={`base-player-card ${className}`} />
}
