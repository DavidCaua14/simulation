import { PITCH_LAYOUT } from '../data/pitchLayout'
import './Pitch.css'

export default function Pitch({ positions, selected, onSelect }) {
  const labelById = Object.fromEntries(positions.map((p) => [p.id, p.label]))

  return (
    <div className="pitch">
      <svg className="pitch-lines" viewBox="0 0 100 150" preserveAspectRatio="none">
        <rect x="1" y="1" width="98" height="148" fill="none" stroke="currentColor" strokeWidth="0.6" />
        <line x1="1" y1="75" x2="99" y2="75" stroke="currentColor" strokeWidth="0.6" />
        <circle cx="50" cy="75" r="11" fill="none" stroke="currentColor" strokeWidth="0.6" />
        <circle cx="50" cy="75" r="0.8" fill="currentColor" />
        <rect x="24" y="1" width="52" height="20" fill="none" stroke="currentColor" strokeWidth="0.6" />
        <rect x="38" y="1" width="24" height="8" fill="none" stroke="currentColor" strokeWidth="0.6" />
        <rect x="24" y="129" width="52" height="20" fill="none" stroke="currentColor" strokeWidth="0.6" />
        <rect x="38" y="141" width="24" height="8" fill="none" stroke="currentColor" strokeWidth="0.6" />
      </svg>

      {PITCH_LAYOUT.map((spot) => {
        const isSelected = selected === spot.id
        return (
          <button
            type="button"
            key={spot.id}
            className={`pitch-spot ${isSelected ? 'is-selected' : ''}`}
            style={{ left: `${spot.x}%`, top: `${spot.y}%` }}
            onClick={() => onSelect(spot.id)}
            aria-pressed={isSelected}
          >
            {spot.id}
          </button>
        )
      })}

      <div className="pitch-selected-label">
        {selected ? labelById[selected] : 'Toque em uma posição do campo'}
      </div>
    </div>
  )
}
