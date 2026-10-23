import { CheckIcon } from '../../../components/ui/icons'
import ClubCrest from './ClubCrest'
import { getClubById } from '../data/clubs'

// Proposta inicial de um clube (escudo real, nome, o que prometem e as luvas de assinatura).
export default function ClubProposalCard({ offer, selected, onSelect, style }) {
  const club = getClubById(offer.club_id)
  return (
    <button type="button" className={`club-card ${selected ? 'is-selected' : ''}`} onClick={() => onSelect(offer.id)} style={style}>
      <span className="club-card-shield">
        <ClubCrest clubId={offer.club_id} size={44} />
      </span>
      <span className="club-card-info">
        <strong>{club?.name}</strong>
        <span>{offer.pitch}</span>
        <span className="club-card-bonus">Luvas de assinatura: +{offer.bonus_coins} moedas</span>
      </span>
      {selected && (
        <span className="club-card-check">
          <CheckIcon />
        </span>
      )}
    </button>
  )
}
