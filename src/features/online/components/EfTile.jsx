import ConditionArrow from './ConditionArrow'
import { PlayerFace } from './PlayerFut'
import { cardTier } from '../onlineUtils'

// CARTA QUADRADA no estilo eFootball: posição e nota no canto, rosto, seta de condição e o nome embaixo.
// Usada no campo e nas listas do Elenco. pos: posição da vaga (nota nessa posição).
export default function EfTile({ player, pos, colors, selected, onClick, label, dim = false, badge = null }) {
  const Tag = onClick ? 'button' : 'div'
  if (!player) {
    return (
      <Tag type={onClick ? 'button' : undefined} className={`ef-tile is-empty ${selected ? 'is-sel' : ''}`} onClick={onClick} aria-label={`${label || pos || 'Vaga'} vazia`}>
        <span className="ef-tile-box"><b>+</b><small>{label || pos}</small></span>
      </Tag>
    )
  }
  const tier = cardTier({ ...player, ovr: player.ovr ?? player.overall })
  const at = pos || player.position || player.pos
  const rating = Math.round(player.ratings?.[at] ?? player.ovr ?? player.overall ?? 0)
  const off = Boolean(pos && player.position && player.position !== pos && !(player.secondary || []).includes(pos))
  const injured = player.injured_days > 0 || player.injured
  const susp = player.suspended > 0
  const name = player.short_name || player.name || ''
  const short = name.length > 13 ? name.split(' ').slice(-1)[0] : name
  return (
    <Tag
      type={onClick ? 'button' : undefined}
      className={`ef-tile t-${tier} ${selected ? 'is-sel' : ''} ${dim ? 'is-dim' : ''} ${off ? 'is-off' : ''}`}
      onClick={onClick}
      aria-label={`${at}: ${name}, nota ${rating}${off ? `, fora da posição (é ${player.position})` : ''}`}
    >
      <span className="ef-tile-box">
        <span className="ef-tile-ovr"><small>{at}</small><b>{rating}</b></span>
        {player.arrow != null && <ConditionArrow arrow={player.arrow} size={14} className="ef-tile-arrow" />}
        <span className="ef-tile-face"><PlayerFace seed={name} colors={colors ? { a: colors[0], b: colors[1] } : undefined} size={40} /></span>
        {(injured || susp) && <i className={`ef-tile-flag ${injured ? 'inj' : 'susp'}`}>{injured ? '+' : 'S'}</i>}
        {badge && <em className="ef-tile-badge">{badge}</em>}
      </span>
      <span className="ef-tile-name">{short}</span>
    </Tag>
  )
}
