import { CheckIcon } from '../../../components/ui/icons'

export default function ClubProposalCard({ club, selected, onSelect, style }) {
  return (
    <button
      type="button"
      className={`club-card ${selected ? 'is-selected' : ''}`}
      onClick={() => onSelect(club.id)}
      style={style}
    >
      <span className="club-card-shield">
        <img src={club.shield} alt="" />
      </span>
      <span className="club-card-info">
        <strong>{club.name}</strong>
        <span>{club.pitch}</span>
      </span>
      {selected && (
        <span className="club-card-check">
          <CheckIcon />
        </span>
      )}
    </button>
  )
}
