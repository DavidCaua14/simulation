import { Check, Coins } from 'lucide-react'
import ClubCrest from './ClubCrest'
import { getClubById } from '../data/clubs'

const LEAGUE = { serie_a: 'Série A', br_other: 'Brasil', foreign: 'Exterior' }

// Proposta inicial = "contrato": faixa com as cores do clube, escudo grande, o que prometem
// e as luvas de assinatura (moedas que entram ao assinar).
export default function ClubProposalCard({ offer, selected, onSelect, style }) {
  const club = getClubById(offer.club_id)
  const [c1, c2] = club?.colors || ['#2b3a5c', '#8a96b0']
  return (
    <button
      type="button"
      role="radio"
      aria-checked={selected}
      className={`of-card ${selected ? 'is-selected' : ''}`}
      onClick={() => onSelect(offer.id)}
      style={{ ...style, '--c1': c1, '--c2': c2 }}
    >
      <span className="of-card-band" aria-hidden="true" />
      <span className="of-card-top">
        <span className="of-card-crest">
          <ClubCrest clubId={offer.club_id} size={50} />
        </span>
        <span className="of-card-id">
          <small>{LEAGUE[club?.tier] || 'Proposta'}</small>
          <strong>{club?.name}</strong>
        </span>
        <span className="of-card-pick" aria-hidden="true">
          {selected ? <Check size={16} strokeWidth={3} /> : null}
        </span>
      </span>
      <span className="of-card-pitch">“{offer.pitch}”
      </span>
      <span className="of-card-foot">
        <span className="of-card-bonus">
          <Coins size={14} /> +{Number(offer.bonus_coins).toLocaleString('pt-BR')}
        </span>
        <span className="of-card-bonus-label">luvas de assinatura</span>
        {selected && <span className="gx-tag is-gold">Escolhido</span>}
      </span>
    </button>
  )
}
