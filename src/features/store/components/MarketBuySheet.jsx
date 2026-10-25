import { useRef, useState } from 'react'
import { Check, CircleAlert, Coins, X } from 'lucide-react'
import CardView from '../../cards/components/CardView'
import { tierOf } from '../../cards/data/tiers'
import { buyListing, newRequestId } from '../services/storeApi'
import { cardFacts } from './cardFacts'
import { fmt, timeLeft } from './marketUtils'

// Confirmação de compra no mercado. O preço exibido é o do anúncio; o servidor confere tudo de novo na compra.
export default function MarketBuySheet({ listing, coins, onClose, onBought, onOpenCollection }) {
  const requestId = useRef(newRequestId()).current
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [result, setResult] = useState(null)
  const { card } = listing
  const t = tierOf(card.tier)
  const f = cardFacts(card)
  const short = coins < listing.price

  async function confirm() {
    setBusy(true)
    setError('')
    try {
      const r = await buyListing(listing.id, requestId)
      setResult(r)
      onBought?.(r)
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="cx-sheet-wrap" role="dialog" aria-modal="true" aria-label="Comprar no mercado" onClick={busy ? undefined : onClose}>
      <div className="cx-sheet sh-confirm" onClick={(e) => e.stopPropagation()}>
        <button type="button" className="cx-sheet-x" onClick={onClose} disabled={busy} aria-label="Fechar"><X size={18} /></button>
        <CardView card={card} width={150} shine />
        <h3>{card.name}</h3>
        <p className="sh-confirm-tier" style={{ color: t.color }}>{t.label}</p>
        <p className="sh-item-facts">Nota <b>{f.overall}</b> · {f.position} · {f.club} · {f.nationality}</p>
        {!result ? (
          <>
            <dl className="sh-bill">
              <div><dt>Vendedor</dt><dd>{listing.seller}</dd></div>
              <div><dt>Preço</dt><dd><Coins size={14} /> {fmt(listing.price)} moedas</dd></div>
              <div><dt>Seu saldo</dt><dd>{fmt(coins)}</dd></div>
              <div className={short ? 'is-short' : ''}><dt>Depois da compra</dt><dd>{short ? `faltam ${fmt(listing.price - coins)}` : fmt(coins - listing.price)}</dd></div>
              <div><dt>Anúncio termina em</dt><dd>{timeLeft(listing.expires_at)}</dd></div>
            </dl>
            {short && <p className="sh-msg is-error"><CircleAlert size={14} /> Saldo insuficiente: você tem {fmt(coins)} moedas e a carta custa {fmt(listing.price)}.</p>}
            {error && <p className="sh-msg is-error"><CircleAlert size={14} /> {error}</p>}
            <button type="button" className="gx-btn sh-confirm-btn" disabled={busy || short} onClick={confirm}>
              {busy ? 'Comprando…' : <><Coins size={16} /> Comprar por {fmt(listing.price)}</>}
            </button>
            <p className="cx-hint">Você paga só o preço anunciado. A taxa do mercado é descontada do vendedor.</p>
          </>
        ) : (
          <>
            <p className="sh-msg is-ok"><Check size={16} /> Compra concluída! {result.new ? 'Carta nova na sua coleção.' : `Agora você tem ${result.qty} cópias.`}</p>
            <dl className="sh-bill">
              <div><dt>Pago a {result.seller}</dt><dd><Coins size={14} /> {fmt(result.price)}</dd></div>
              <div><dt>Saldo atual</dt><dd>{fmt(result.coins)}</dd></div>
            </dl>
            <div className="sh-confirm-actions">
              <button type="button" className="gx-btn-ghost" onClick={onOpenCollection}>Ver coleção</button>
              <button type="button" className="gx-btn" onClick={onClose}>Continuar</button>
            </div>
          </>
        )}
      </div>
    </div>
  )
}
