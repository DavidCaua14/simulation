import ConditionArrow from './ConditionArrow'
import { PlayerFace } from './PlayerFut'
import { shortName } from './pixelFace'
import { BtPhoto } from './BigTime'
import { cardTier } from '../onlineUtils'

// MINIATURA DA CARTA em pixel art: nota e posição no topo, rosto (Big Time: a foto real), seta de condição e nome.
// Usada no campo e nas listas do Elenco. pos: posição da vaga (nota nessa posição).
export default function EfTile({ player, pos, colors, selected, onClick, label, dim = false, badge = null, size = 66 }) {
  const box = { '--ef': `${size}px` }
  const Tag = onClick ? 'button' : 'div'
  if (!player) {
    return (
      <Tag type={onClick ? 'button' : undefined} className={`ef-tile is-empty ${selected ? 'is-sel' : ''}`} style={box} onClick={onClick} aria-label={`${label || pos || 'Vaga'} vazia`}>
        <span className="pxm is-empty"><span><b>+</b><br /><small>{label || pos}</small></span></span>
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
  // físico (cansaço): diferente da seta, que é a condição (forma) da partida
  const cond = player.condition ?? player.cond
  const tone = cond == null ? '' : cond >= 85 ? 'ok' : cond >= 70 ? 'warn' : 'bad'
  return (
    <Tag
      type={onClick ? 'button' : undefined}
      className={`ef-tile t-${tier} ${selected ? 'is-sel' : ''} ${dim ? 'is-dim' : ''} ${off ? 'is-off' : ''} ${rating >= 100 ? 'is-3d' : ''}`}
      style={box}
      onClick={onClick}
      aria-label={`${at}: ${name}, nota ${rating}${off ? `, fora da posição (é ${player.position})` : ''}${cond != null ? `, físico ${Math.round(cond)}%` : ''}`}
    >
      <span className="pxm">
        <span className="pxm-art">
          {player.bt?.photo ? <BtPhoto bt={player.bt} className="is-tile" /> : <PlayerFace seed={name} colors={colors ? { a: colors[0], b: colors[1] } : undefined} size={Math.round(size * 1.3)} />}
          <b className="pxm-ovr">{rating}</b>
          <small className="pxm-pos">{at}</small>
          {player.arrow != null && <span className="pxm-arrow"><ConditionArrow arrow={player.arrow} size={14} /></span>}
          {(injured || susp) && <span className="pxm-flags"><i className={injured ? 'inj' : 'susp'}>{injured ? '+' : 'S'}</i></span>}
          {badge && <em className="pxm-badge">{badge}</em>}
        </span>
        <span className="pxm-name">{shortName(name)}</span>
      </span>
      {off && <span className="px-natpos" title={`Fora da posição: a posição de origem é ${player.position}`}>É {player.position}</span>}
      {cond != null && (
        <span className={`ef-tile-cond ${tone}`} title={`Físico ${Math.round(cond)}%`} aria-label={`Físico ${Math.round(cond)}%`}>
          <i style={{ width: `${Math.max(4, Math.min(100, cond))}%` }} />
        </span>
      )}
    </Tag>
  )
}
