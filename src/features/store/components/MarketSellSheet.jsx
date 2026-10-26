import { useRef, useState } from 'react'
import { Check, CircleAlert, Coins, X } from 'lucide-react'
import CardView from '../../cards/components/CardView'
import { tierOf } from '../../cards/data/tiers'
import { feeOf, listCard, newRequestId } from '../services/storeApi'
import { cardFacts } from './cardFacts'
import { fmt } from './marketUtils'
import { useAudio } from '../../audio/AudioContext'

// Anunciar uma carta: preço (dentro do limite da raridade), taxa e valor líquido mostrados ANTES de confirmar.
export default function MarketSellSheet({ entry, rules, onClose, onListed }) {
  const requestId = useRef(newRequestId()).current
  const { card, qty, min, max } = entry
  const [price, setPrice] = useState(String(min))
  const [busy, setBusy] = useState(false)
  const { playSfx } = useAudio()
  const [error, setError] = useState('')
  const [result, setResult] = useState(null)
  const t = tierOf(card.tier)
  const f = cardFacts(card)
  const n = Math.floor(Number(price))
  const valid = Number.isFinite(n) && n >= min && n <= max
  const fee = valid ? feeOf(n, Number(rules.fee_pct)) : 0

  async function confirm() {
    setBusy(true)
    setError('')
    try {
      const r = await listCard(card.id, n, requestId)
      setResult(r)
      playSfx('purchase')
      onListed?.(r)
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="cx-sheet-wrap" role="dialog" aria-modal="true" aria-label="Anunciar no mercado" onClick={busy ? undefined : onClose}>
      <div className="cx-sheet sh-confirm" onClick={(e) => e.stopPropagation()}>
        <button type="button" className="cx-sheet-x" onClick={onClose} disabled={busy} aria-label="Fechar"><X size={18} /></button>
        <CardView card={card} width={140} shine />
        <h3>{card.name}</h3>
        <p className="sh-confirm-tier" style={{ color: t.color }}>{t.label}</p>
        <p className="sh-item-facts">Nota <b>{f.overall}</b> · {f.position} · {f.club} · você tem {qty}</p>
        {!result ? (
          <>
            <label className="mk-price">
              <span>Preço (moedas) · de {fmt(min)} a {fmt(max)}</span>
              <span className="mk-price-input">
                <Coins size={16} />
                <input type="number" inputMode="numeric" min={min} max={max} step="50" value={price} onChange={(e) => setPrice(e.target.value)} disabled={busy} />
              </span>
            </label>
            <dl className="sh-bill">
              <div><dt>Taxa do mercado ({Number(rules.fee_pct).toLocaleString('pt-BR')}%)</dt><dd>{valid ? `− ${fmt(fee)}` : '—'}</dd></div>
              <div><dt>Você recebe se vender</dt><dd><Coins size={14} /> {valid ? fmt(n - fee) : '—'}</dd></div>
              <div><dt>Anúncio fica no ar por</dt><dd>{rules.listing_hours} h</dd></div>
            </dl>
            {!valid && <p className="sh-msg is-error"><CircleAlert size={14} /> O preço precisa ficar entre {fmt(min)} e {fmt(max)} moedas.</p>}
            {error && <p className="sh-msg is-error"><CircleAlert size={14} /> {error}</p>}
            <button type="button" className="gx-btn sh-confirm-btn" disabled={busy || !valid} onClick={confirm}>
              {busy ? 'Publicando…' : 'Publicar anúncio'}
            </button>
            <p className="cx-hint">Enquanto estiver à venda, esta cópia fica reservada (sai da coleção). Se cancelar ou expirar, ela volta.</p>
          </>
        ) : (
          <>
            <p className="sh-msg is-ok"><Check size={16} /> Anúncio publicado por {fmt(result.price)} moedas.</p>
            <p className="cx-hint">Se vender, você recebe {fmt(result.seller_receives)} (taxa de {fmt(result.fee)}).</p>
            <button type="button" className="gx-btn sh-confirm-btn" onClick={onClose}>Fechar</button>
          </>
        )}
      </div>
    </div>
  )
}
