import { Gift } from 'lucide-react'
import { RewardChip, fmtDate } from './eventsUi'

// Earlier periods keep their original claim deadline even after the event renews.
export default function PendingRewards({ rewards, busy, onClaim }) {
  if (!rewards.length) return null
  return (
    <section aria-label="Recompensas pendentes">
      <h4 className="gx-subtitle">Recompensas pendentes</h4>
      <div className="ev-list">
        {rewards.map((r) => (
          <article key={r.completion_id} className="ev-card is-claimable">
            <div className="ev-body">
              <strong>{r.name}</strong>
              <p className="ev-note">Concluído em {fmtDate(r.completed_at)}. Resgate até {fmtDate(r.claim_until)}.</p>
              <div className="ev-chips">{r.rewards.map((reward, i) => <RewardChip key={i} r={reward} />)}</div>
              <button type="button" className="gx-btn ev-claim" disabled={busy === r.id} onClick={() => onClaim(r, r.completion_id)} data-sfx="select">
                <Gift size={16} /> {busy === r.id ? 'Resgatando…' : 'Resgatar'}
              </button>
            </div>
          </article>
        ))}
      </div>
    </section>
  )
}
