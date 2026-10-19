import { formatMult } from '../data/predictionRules'
import { Amount, PICK_STATUS_ICON } from './PredIcons'

// Aparece sozinho quando um bilhete é liquidado (chega por Realtime).
export default function TicketResultModal({ ticket, onClose }) {
  const Icon = PICK_STATUS_ICON[ticket.status] || PICK_STATUS_ICON.void
  const won = ticket.status === 'won'
  const lost = ticket.status === 'lost'

  return (
    <div className="pred-overlay center" onClick={onClose}>
      <div className={`pred-modal ${ticket.status}`} onClick={(e) => e.stopPropagation()} role="dialog" aria-modal="true">
        <span className="pred-modal-icon"><Icon size={40} aria-hidden="true" /></span>
        <h3>{won ? 'Bilhete ganho!' : lost ? 'Não foi dessa vez' : 'Bilhete anulado'}</h3>
        <p className="pred-hint">
          {won && `Você acertou todos os palpites, com odd ${formatMult(Number(ticket.multiplier))}.`}
          {lost && 'Um dos palpites errou. Em outra rodada você recupera.'}
          {!won && !lost && 'Os jogos foram anulados e sua entrada voltou para o saldo.'}
        </p>

        {won && (
          <div className="pred-modal-rewards">
            <Amount kind="coin" value={ticket.reward_coins} sign="+" />
            <span className="pred-amt"><b>+{ticket.reward_xp} XP</b></span>
            <Amount kind="energy" value={ticket.reward_energy} sign="+" />
          </div>
        )}
        {lost && <div className="pred-modal-rewards"><Amount kind="coin" value={ticket.stake} sign="-" /></div>}

        <button type="button" className="pred-btn primary" onClick={onClose}>Continuar</button>
      </div>
    </div>
  )
}
