import { Ambulance, Ban, BatteryLow } from 'lucide-react'
import BasePlayerCard from '../../cards/components/BasePlayerCard'
import { POS_NAME, fitTone, posFit } from '../utils/managerUtils'
import MoodBadge from './MoodBadge'

// Campo visto de cima (ataque para cima). Cada vaga da formação fica na posição real do campo
// (coordenadas vêm de sim_formations, as mesmas que o motor usa).
function PitchLines() {
  return (
    <svg className="pt-lines" viewBox="0 0 100 140" preserveAspectRatio="none" aria-hidden="true">
      <rect x="3" y="3" width="94" height="134" rx="1.5" />
      <line x1="3" y1="70" x2="97" y2="70" />
      <circle cx="50" cy="70" r="11" />
      <circle cx="50" cy="70" r="0.9" className="dot" />
      <rect x="24" y="3" width="52" height="20" />
      <rect x="38" y="3" width="24" height="7" />
      <path d="M40 23 A12 12 0 0 0 60 23" />
      <rect x="24" y="117" width="52" height="20" />
      <rect x="38" y="130" width="24" height="7" />
      <path d="M40 117 A12 12 0 0 1 60 117" />
    </svg>
  )
}

export function PlayerToken({ player, pos, colors, selected, live, onClick, label }) {
  const rating = player ? Math.round(player.ratings?.[pos] ?? player.overall ?? 0) : null
  const fit = player ? (player.fit ?? posFit(player, pos)) : 1
  const unavailable = player && player.available === false
  const injured = player && (player.injured_days > 0 || player.injured)
  const susp = player && player.suspended > 0
  const tired = player && player.condition != null && player.condition < 70
  const [c1, c2] = colors || ['#1b3566', '#f5b800']
  const Tag = onClick ? 'button' : 'div'
  return (
    <Tag
      type={onClick ? 'button' : undefined}
      className={`pt-tok ${player ? '' : 'is-empty'} ${selected ? 'is-sel' : ''} ${unavailable ? 'is-out' : ''} fit-${fitTone(fit)}`}
      onClick={onClick}
      aria-label={player ? `${label || pos}: ${player.short_name || player.name}, nota ${rating} nessa posição` : `${label || pos}: vaga vazia`}
    >
      {player ? <BasePlayerCard player={player} position={pos} overall={rating} colors={[c1, c2]} /> : <span className="pt-shirt"><b>+</b></span>}
      {player?.morale != null && !live && <MoodBadge morale={player.morale} size={14} className="pt-mood" />}
      <span className="pt-status">
        {injured && (
          <i className="pt-flag inj" title="Lesionado">
            <Ambulance size={10} />
          </i>
        )}
        {!injured && susp && (
          <i className="pt-flag susp" title="Suspenso">
            <Ban size={10} />
          </i>
        )}
        {!injured && !susp && tired && (
          <i className="pt-flag tired" title="Cansado">
            <BatteryLow size={10} />
          </i>
        )}
      </span>
      <span className="pt-name">{player ? player.short_name || player.name : label || pos}</span>
      {player && pos && (
        <span className={`pt-pos fit-${fitTone(fit)}`} title={player.position && player.position !== pos ? `Jogando de ${POS_NAME[pos] || pos}; posição de origem: ${POS_NAME[player.position] || player.position}` : POS_NAME[pos] || pos}>
          {pos}
          {player.position && player.position !== pos && <em>é {player.position}</em>}
        </span>
      )}
      {player && player.condition != null && (
        <span className={`pt-cond ${player.condition >= 85 ? 'ok' : player.condition >= 70 ? 'warn' : 'bad'}`}>
          <i style={{ width: `${Math.max(4, Math.min(100, player.condition))}%` }} />
        </span>
      )}
      {live && player?.yellow > 0 && <span className="pt-card y" title="Amarelo" />}
    </Tag>
  )
}

export default function Pitch({ formation, slots, playersById, colors, selected, onSlot, live = false, compact = false, bind, drag }) {
  if (!formation) return <div className="pt pt-empty" />
  return (
    <div className={`pt ${compact ? 'is-compact' : ''}`}>
      <PitchLines />
      {formation.slots.map((s) => {
        const pid = slots?.[s.slot]
        const player = pid ? playersById[pid] : null
        return (
          <div
            key={s.slot}
            className={`pt-slot ${drag?.over === `slot:${s.slot}` ? 'is-drop' : ''} ${drag?.from === `slot:${s.slot}` ? 'is-dragging' : ''}`}
            style={{ left: `${s.x}%`, top: `${s.y * 0.94 + 2}%` }}
            {...(bind ? bind(`slot:${s.slot}`, pid) : {})}
          >
            <PlayerToken
              player={player}
              pos={s.pos}
              label={s.pos}
              colors={colors}
              selected={selected === s.slot}
              live={live}
              onClick={onSlot ? () => onSlot(s) : undefined}
            />
          </div>
        )
      })}
    </div>
  )
}
