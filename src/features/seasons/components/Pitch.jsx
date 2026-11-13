import { useContext } from 'react'
import { Ambulance, Ban, BatteryLow } from 'lucide-react'
import { POS_NAME, fitTone, posFit } from '../utils/managerUtils'
import MoodFace from './MoodFace'
import { PitchTokenContext } from './pitchToken'
import './pitch-cm.css'

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

// Camisa no estilo Championship Manager: cores do clube e o número do atleta.
const light = (hex) => {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex || '')
  if (!m) return false
  const n = parseInt(m[1], 16)
  return ((n >> 16) & 255) * 0.299 + ((n >> 8) & 255) * 0.587 + (n & 255) * 0.114 > 170
}
export function Jersey({ colors, number, keeper = false }) {
  const [c1, c2] = keeper ? ['#f2b705', '#1d1d1f'] : colors || ['#1b3566', '#f5b800']
  const ink = light(c1) ? (light(c2) ? '#14213d' : c2) : light(c2) ? c2 : '#ffffff'
  return (
    <svg className="pt-jersey" viewBox="0 0 64 60" aria-hidden="true">
      <path d="M21 4 9 9 2 23l10 5 3-6v34h34V22l3 6 10-5-7-14-12-5q-4 6-11 6T21 4Z" fill={c1} stroke="rgba(0,0,0,.55)" strokeWidth="1.6" strokeLinejoin="round" />
      <path d="M2 23l10 5 1.6-3.2L4 19.6ZM62 23l-10 5-1.6-3.2L60 19.6Z" fill={c2} />
      <path d="M21 4q4 6 11 6t11-6l-3-1.2Q37 7 32 7t-8-4.2Z" fill={c2} />
      {number != null && (
        <text x="32" y="41" textAnchor="middle" fill={ink} stroke="rgba(0,0,0,.35)" strokeWidth="0.8" paintOrder="stroke">
          {number}
        </text>
      )}
    </svg>
  )
}

export function PlayerToken({ player, pos, colors, selected, live, onClick, label }) {
  const renderToken = useContext(PitchTokenContext)
  if (renderToken) return renderToken({ player, pos, colors, selected, live, onClick, label })
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
      {player ? (
        <span className="pt-shirt is-kit">
          <Jersey colors={[c1, c2]} number={player.number} keeper={pos === 'GOL'} />
        </span>
      ) : (
        <span className="pt-shirt">
          <b>+</b>
        </span>
      )}
      {player && !live && player.morale != null && <MoodFace morale={player.morale} size={11} className="pt-mood" />}
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
      <span className="pt-label">
        <span className="pt-name">{player ? player.short_name || player.name : label || pos}</span>
        {player && pos && (
          <span className="pt-meta">
            <span className={`pt-pos fit-${fitTone(fit)}`} title={player.position && player.position !== pos ? `Jogando de ${POS_NAME[pos] || pos}; posição de origem: ${POS_NAME[player.position] || player.position}` : POS_NAME[pos] || pos}>
              {pos}
              {player.position && player.position !== pos && <em>é {player.position}</em>}
            </span>
            <b className="pt-rate">{rating}</b>
          </span>
        )}
        {player && player.condition != null && (
          <span className={`pt-cond ${player.condition >= 85 ? 'ok' : player.condition >= 70 ? 'warn' : 'bad'}`} title={`Condição física ${Math.round(player.condition)}%`}>
            <i style={{ width: `${Math.max(4, Math.min(100, player.condition))}%` }} />
          </span>
        )}
      </span>
      {live && player?.yellow > 0 && <span className="pt-card y" title="Amarelo" />}
    </Tag>
  )
}

// Vertical: usa o campo inteiro (atacante perto do topo, goleiro perto do fundo) para separar as linhas.
const slotTop = (y, compact) => (compact ? y * 0.94 + 2 : 7 + ((Math.min(95, Math.max(10, y)) - 10) / 85) * 86)

export default function Pitch({ formation, slots, playersById, colors, selected, onSlot, live = false, compact = false, bind, drag }) {
  const cards = useContext(PitchTokenContext) != null
  if (!formation) return <div className="pt pt-empty" />
  return (
    <div className={`pt ${compact ? 'is-compact' : ''} ${cards ? 'has-cards' : ''}`}>
      <PitchLines />
      {formation.slots.map((s) => {
        const pid = slots?.[s.slot]
        const player = pid ? playersById[pid] : null
        return (
          <div
            key={s.slot}
            className={`pt-slot ${drag?.over === `slot:${s.slot}` ? 'is-drop' : ''} ${drag?.from === `slot:${s.slot}` ? 'is-dragging' : ''}`}
            style={{ left: `${s.x}%`, top: `${slotTop(s.y, compact)}%` }}
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
