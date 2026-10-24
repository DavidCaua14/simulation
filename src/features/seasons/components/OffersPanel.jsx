import { useState } from 'react'
import { ArrowLeftRight, Clock3, Coins, Star } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import useCountdown from '../hooks/useCountdown'
import { EmptyState } from '../ui/States'
import { fmt, formatRemaining, popularityTier } from '../utils/seasonUtils'

const HISTORY_LABEL = { accepted: 'Aceita', declined: 'Recusada', expired: 'Expirou' }

// Contagem regressiva do prazo da proposta. Quando zera, a proposta sai (o banco também a expira).
function Deadline({ iso, onExpired }) {
  const ms = useCountdown(iso, onExpired)
  if (ms == null) return null
  const urgent = ms < 12 * 3600 * 1000
  return (
    <span className={`sn-deadline ${urgent ? 'urgent' : ''}`}>
      <Clock3 size={13} /> {ms <= 0 ? 'Expirou' : `Expira em ${formatRemaining(ms)}`}
    </span>
  )
}

// Propostas de outros clubes (com prazo). Aceitar = transferência imediata + bônus de assinatura.
export default function OffersPanel({ offers, history = [], currentClub, popularity, busyId, onRespond, onExpired }) {
  const [confirmId, setConfirmId] = useState(null)
  const tier = popularityTier(popularity)

  const current = getClubById(currentClub)

  return (
    <div className="sn-offers">
      <section className="fm">
        <div className="fm-head">
          <span className="fm-star">
            <Star size={20} fill="currentColor" />
          </span>
          <div>
            <small>Sua fama</small>
            <b>{tier.label}</b>
          </div>
          <span className="fm-val">{fmt(popularity)}</span>
        </div>
        <div className="gx-xp fm-bar">
          <i style={{ width: `${tier.pct}%` }} />
        </div>
        <p>
          {tier.next ? (
            <>
              Faltam <b>{fmt(tier.toNext)}</b> para <b>{tier.next}</b>.{' '}
            </>
          ) : null}
          Vitórias, gols, assistências e boas notas aumentam sua fama. Mais fama, mais propostas, de clubes cada vez maiores.
        </p>
        <details className="fm-rules">
          <summary>Como funcionam as propostas</summary>
          <p>
            Toda proposta tem <b>prazo</b>. Se vencer, ela sai e o clube demora mais para te procurar de novo. Depois que você troca de time, o clube
            antigo volta a considerar você, mas com menos chance que o normal.
          </p>
        </details>
      </section>

      <h2 className="gx-title">
        Propostas <small>{offers.length ? `${offers.length} na mesa` : 'nenhuma agora'}</small>
      </h2>

      {offers.length === 0 ? (
        <EmptyState icon={ArrowLeftRight} title="Nenhuma proposta por enquanto" text="Continue jogando bem: os clubes estão de olho." />
      ) : (
        offers.map((o) => {
          const club = getClubById(o.club_id)
          const busy = busyId === o.id
          const [c1, c2] = club?.colors || ['#2b3a5c', '#8a96b0']
          return (
            <article key={o.id} className="ofr" style={{ '--c1': c1, '--c2': c2 }}>
              <span className="ofr-band" aria-hidden="true" />
              <header>
                <span className="ofr-crest">
                  <ClubCrest clubId={o.club_id} size={50} />
                </span>
                <div>
                  <small>Proposta oficial</small>
                  <strong>{club?.name}</strong>
                </div>
                {o.expires_at && <Deadline iso={o.expires_at} onExpired={onExpired} />}
              </header>
              <p className="ofr-pitch">“{o.pitch}”</p>
              <div className="ofr-bonus">
                <Coins size={15} /> <b>+{fmt(o.bonus_coins)}</b> <span>luvas de assinatura</span>
              </div>

              {confirmId === o.id ? (
                <div className="ofr-confirm">
                  <p>
                    Sair do <b>{current?.name}</b> e assinar com o <b>{club?.name}</b>? A transferência é imediata e você segue nos campeonatos do novo
                    clube.
                  </p>
                  <div className="ofr-actions">
                    <button type="button" className="gx-btn-ghost" disabled={busy} onClick={() => setConfirmId(null)}>
                      Voltar
                    </button>
                    <button type="button" className="gx-btn ofr-go" disabled={busy} onClick={() => onRespond(o.id, true)}>
                      {busy ? 'Assinando…' : 'Confirmar'}
                    </button>
                  </div>
                </div>
              ) : (
                <div className="ofr-actions">
                  <button type="button" className="gx-btn-ghost" disabled={busy} onClick={() => onRespond(o.id, false)}>
                    Recusar
                  </button>
                  <button type="button" className="gx-btn ofr-go" disabled={busy} onClick={() => setConfirmId(o.id)}>
                    Aceitar proposta
                  </button>
                </div>
              )}
            </article>
          )
        })
      )}

      {history.length > 0 && (
        <section className="sn-sec">
          <h2 className="gx-title">Propostas anteriores</h2>
          <ul className="ofr-hist">
            {history.map((h) => (
              <li key={h.id} className={`st-${h.status}`}>
                <ClubCrest clubId={h.club_id} size={24} />
                <span>{getClubById(h.club_id)?.name}</span>
                <em>{HISTORY_LABEL[h.status] || h.status}</em>
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  )
}
