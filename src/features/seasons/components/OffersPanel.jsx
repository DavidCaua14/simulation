import { useState } from 'react'
import { Clock3, Coins, Star } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import useCountdown from '../hooks/useCountdown'
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

  return (
    <div className="sn-offers">
      <div className="sn-fame card">
        <div className="sn-fame-head">
          <Star size={18} fill="currentColor" />
          <div>
            <strong className="heading">{tier.label}</strong>
            <small>Popularidade {fmt(popularity)}</small>
          </div>
        </div>
        <div className="sn-bar">
          <i style={{ width: `${tier.pct}%` }} />
        </div>
        <p className="sn-hint">
          {tier.next ? `Faltam ${fmt(tier.toNext)} pontos para "${tier.next}". ` : ''}
          Vitórias, gols, assistências e boas notas aumentam sua fama, e com mais fama chegam mais propostas, de clubes cada vez maiores.
        </p>
        <p className="sn-hint">
          Toda proposta tem <b>prazo</b>. Se vencer, ela sai, e o clube demora mais para te procurar de novo. Depois que você troca de time, esse clube volta a
          considerar você, mas com menos chance que o normal.
        </p>
      </div>

      {offers.length === 0 ? (
        <div className="sn-empty card">
          <p>Nenhuma proposta por enquanto.</p>
          <small>Continue jogando bem: os clubes estão de olho.</small>
        </div>
      ) : (
        offers.map((o) => {
          const club = getClubById(o.club_id)
          const busy = busyId === o.id
          return (
            <article key={o.id} className="sn-offer card">
              <header>
                <ClubCrest clubId={o.club_id} size={46} />
                <div>
                  <strong className="heading">{club?.name}</strong>
                  <small>quer contratar você</small>
                </div>
                <span className="sn-offer-bonus">
                  <Coins size={14} /> +{fmt(o.bonus_coins)}
                </span>
              </header>
              <p className="sn-offer-pitch">{o.pitch}</p>
              {o.expires_at && <Deadline iso={o.expires_at} onExpired={onExpired} />}

              {confirmId === o.id ? (
                <div className="sn-confirm">
                  <p>
                    Sair do <b>{getClubById(currentClub)?.name}</b> e assinar com o <b>{club?.name}</b>? A transferência é imediata e você segue
                    nos campeonatos do novo clube.
                  </p>
                  <div className="sn-offer-actions">
                    <button type="button" className="sn-ghost" disabled={busy} onClick={() => setConfirmId(null)}>
                      Voltar
                    </button>
                    <button type="button" className="sn-play" disabled={busy} onClick={() => onRespond(o.id, true)}>
                      {busy ? 'Assinando…' : 'Confirmar transferência'}
                    </button>
                  </div>
                </div>
              ) : (
                <div className="sn-offer-actions">
                  <button type="button" className="sn-ghost" disabled={busy} onClick={() => onRespond(o.id, false)}>
                    Recusar
                  </button>
                  <button type="button" className="sn-play" disabled={busy} onClick={() => setConfirmId(o.id)}>
                    Aceitar proposta
                  </button>
                </div>
              )}
            </article>
          )
        })
      )}

      {history.length > 0 && (
        <section className="card sn-history">
          <h3 className="heading">Propostas anteriores</h3>
          {history.map((h) => (
            <div key={h.id} className="sn-hist-row">
              <ClubCrest clubId={h.club_id} size={26} />
              <div>
                <b>{getClubById(h.club_id)?.name}</b>
                <small>{HISTORY_LABEL[h.status] || h.status}</small>
              </div>
            </div>
          ))}
        </section>
      )}
    </div>
  )
}
