import { useState } from 'react'
import { Coins, Gem, Store, X } from 'lucide-react'
import CardView from './CardView'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import { tierOf } from '../data/tiers'
import { discardCard } from '../services/cardsApi'
import { ConfirmSheet } from '../../../components/ui/feedback'

// Detalhe de uma carta: quantas cópias, descarte das REPETIDAS (sempre fica 1) e atalho para vender no mercado.
export default function CardDetail({ entry, tier, onClose, onChanged, onSell }) {
  const { card, qty } = entry
  const t = tierOf(card.tier)
  const club = card.club_id ? getClubById(card.club_id) : null
  const spare = qty - 1
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState('')
  const [ask, setAsk] = useState(null) // quantas descartar (aguardando confirmação)

  async function discard(n) {
    setAsk(null)
    setBusy(true)
    setMsg('')
    try {
      const r = await discardCard(card.id, n)
      setMsg(`Descartadas: +${r.coins} moedas${r.diamonds ? ` e +${r.diamonds} diamantes` : ''}.`)
      await onChanged?.()
    } catch (e) {
      setMsg(e.message)
    } finally {
      setBusy(false)
    }
  }

  const perCoins = tier?.discard_coins ?? 0
  const perGems = tier?.discard_diamonds ?? 0
  const worth = (n) => (
    <>
      <Coins size={13} /> {perCoins * n}
      {perGems > 0 && (
        <>
          {' '}
          <Gem size={13} /> {perGems * n}
        </>
      )}
    </>
  )

  return (
    <div className="cx-sheet-wrap" role="dialog" aria-modal="true" aria-label={card.name} onClick={onClose}>
      <div className="cx-sheet" style={{ '--tier': t.color, '--glow': t.glow }} onClick={(e) => e.stopPropagation()}>
        <button type="button" className="cx-sheet-x" onClick={onClose} aria-label="Fechar">
          <X size={18} />
        </button>
        <div className="cx-detail-card">
          <span className="bx-card-aura" aria-hidden="true" />
          <CardView card={card} width={200} shine />
        </div>
        <h3>{card.name}</h3>
        <p className="cx-meta">
          <b style={{ color: t.color }}>{t.label}</b> · nota {card.overall}
          {card.position ? ` · ${card.position}` : ''}
        </p>
        {club && (
          <p className="cx-club">
            <ClubCrest clubId={club.id} size={18} /> {club.name}
          </p>
        )}
        <p className="cx-qty">
          Você tem <b>{qty}</b> cópia{qty === 1 ? '' : 's'}
        </p>

        <div className="cx-actions">
          {spare > 0 ? (
            <>
              <button type="button" className="bx-btn ghost" disabled={busy} onClick={() => (t.rank >= 3 ? setAsk(1) : discard(1))}>
                Descartar 1 repetida · {worth(1)}
              </button>
              {spare > 1 && (
                <button type="button" className="bx-btn" disabled={busy} onClick={() => setAsk(spare)}>
                  Descartar {spare} repetidas · {worth(spare)}
                </button>
              )}
            </>
          ) : (
            <p className="cx-hint">Sem repetidas. Quando vier outra igual, você poderá descartar ou vender.</p>
          )}
          {card.tier === 'basica' ? (
            <p className="cx-hint">Cartas Básicas não entram no mercado.</p>
          ) : (
            <button type="button" className="bx-btn ghost" disabled={!onSell || qty < 1} onClick={() => onSell?.(card.id)}>
              <Store size={14} /> Vender no mercado
            </button>
          )}
        </div>
        {msg && <p className="cx-msg">{msg}</p>}
      </div>
      {ask && (
        <ConfirmSheet
          title={ask === 1 ? 'Descartar 1 repetida?' : `Descartar ${ask} repetidas?`}
          text={<>Você recebe {worth(ask)} e continua com 1 cópia de {card.name}. O descarte não pode ser desfeito.</>}
          confirmLabel="Descartar"
          busy={busy}
          onCancel={() => setAsk(null)}
          onConfirm={() => discard(ask)}
        />
      )}
    </div>
  )
}
