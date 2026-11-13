import BasePlayerCard from '../../cards/components/BasePlayerCard'
import { posFit } from '../utils/managerUtils'
import './season-pitch-card.css'

// Carta base no campo, no banco e nos não relacionados (mesmo padrão do modo online): nota na posição da vaga,
// e embaixo da carta a condição física. Recebe as mesmas props da ficha do campo (PitchTokenContext).
export default function SeasonPitchCard({ player, pos, colors, selected, live, onClick, label }) {
  const Tag = onClick ? 'button' : 'div'
  if (!player) {
    return (
      <Tag type={onClick ? 'button' : undefined} className={`spc is-empty ${selected ? 'is-sel' : ''}`} onClick={onClick} aria-label={`${label || pos}: vaga vazia`}>
        <span className="spc-empty"><b>+</b><small>{label || pos}</small></span>
      </Tag>
    )
  }
  const at = pos || player.position
  const rating = Math.round(player.ratings?.[at] ?? player.overall ?? 0)
  const off = at && player.position && at !== player.position && posFit(player, at) < 1
  const cond = player.condition
  const tone = cond == null ? '' : cond >= 85 ? 'ok' : cond >= 70 ? 'warn' : 'bad'
  const injured = player.injured_days > 0 || player.injured
  const susp = player.suspended > 0
  const name = player.short_name || player.name || ''
  return (
    <Tag
      type={onClick ? 'button' : undefined}
      className={`spc ${selected ? 'is-sel' : ''} ${player.available === false ? 'is-out' : ''} ${off ? 'is-off' : ''}`}
      onClick={onClick}
      aria-label={`${label || at}: ${name}, nota ${rating} nessa posição${cond != null ? `, condição ${Math.round(cond)}%` : ''}`}
    >
      <span className="spc-card">
        <BasePlayerCard player={player} position={at} overall={rating} width={58} colors={colors} />
        {(injured || susp || (live && player.yellow > 0)) && (
          <span className="spc-flags">
            {injured && <i className="inj" title="Lesionado">+</i>}
            {!injured && susp && <i className="susp" title="Suspenso">S</i>}
            {live && player.yellow > 0 && <i className="yel" title="Amarelo" />}
          </span>
        )}
      </span>
      {cond != null && (
        <span className={`spc-cond ${tone}`} title={`Condição física ${Math.round(cond)}%`}>
          <i style={{ width: `${Math.max(4, Math.min(100, cond))}%` }} />
          <em>{Math.round(cond)}%</em>
        </span>
      )}
    </Tag>
  )
}
