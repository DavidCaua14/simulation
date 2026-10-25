import { useRef, useState } from 'react'
import { Check, CircleAlert, Coins, Gem, X } from 'lucide-react'
import CardView from '../../cards/components/CardView'
import { tierOf } from '../../cards/data/tiers'
import { buyCard, newRequestId } from '../services/storeApi'
import { cardFacts } from './cardFacts'

const fmt = (n) => Number(n ?? 0).toLocaleString('pt-BR')
const CUR = {
  coins: { label: 'moedas', Icon: Coins },
  diamonds: { label: 'diamantes', Icon: Gem },
}

// Confirmação → resultado. O identificador do pedido nasce quando a janela abre e é reaproveitado em
// qualquer nova tentativa: se a internet cair no meio, tentar de novo NÃO cobra duas vezes.
export default function BuyConfirm({ item, currency, wallet, onClose, onBought, onOpenCollection }) {
  const requestId = useRef(newRequestId()).current
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [result, setResult] = useState(null)
  const { card } = item
  const price = item.prices[currency]
  const balance = wallet[currency] ?? 0
  const short = balance < price
  const t = tierOf(card.tier)
  const f = cardFacts(card)
  const { label, Icon } = CUR[currency]

  async function confirm() {
    setBusy(true)
    setError('')
    try {
      const r = await buyCard(card.id, currency, requestId)
      setResult(r)
      onBought?.(r)
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="cx-sheet-wrap" role="dialog" aria-modal="true" aria-label="Confirmar compra" onClick={busy ? undefined : onClose}>
      <div className="cx-sheet sh-confirm" onClick={(e) => e.stopPropagation()}>
        <button type="button" className="cx-sheet-x" onClick={onClose} disabled={busy} aria-label="Fechar">
          <X size={18} />
        </button>

        <CardView card={card} width={150} shine />
        <h3>{card.name}</h3>
        <p className="sh-confirm-tier" style={{ color: t.color }}>{t.label}</p>
        <p className="sh-item-facts">
          Nota <b>{f.overall}</b> · {f.position} · {f.club} · {f.nationality}
        </p>

        {!result ? (
          <>
            <dl className="sh-bill">
              <div><dt>Preço</dt><dd><Icon size={14} /> {fmt(price)} {label}</dd></div>
              <div><dt>Seu saldo</dt><dd>{fmt(balance)}</dd></div>
              <div className={short ? 'is-short' : ''}><dt>Depois da compra</dt><dd>{short ? `faltam ${fmt(price - balance)}` : fmt(balance - price)}</dd></div>
            </dl>
            {item.owned > 0 && <p className="cx-hint">Você já tem {item.owned} {item.owned === 1 ? 'cópia' : 'cópias'}: a nova entra como repetida (pode descartar na Coleção).</p>}
            {short && (
              <p className="sh-msg is-error"><CircleAlert size={14} /> Saldo insuficiente: você tem {fmt(balance)} {label} e a carta custa {fmt(price)}.</p>
            )}
            {error && <p className="sh-msg is-error"><CircleAlert size={14} /> {error}</p>}
            <button type="button" className="gx-btn sh-confirm-btn" disabled={busy || short} onClick={confirm}>
              {busy ? 'Comprando…' : <><Icon size={16} /> Comprar por {fmt(price)}</>}
            </button>
            <p className="cx-hint">A cobrança acontece uma única vez, no servidor.</p>
          </>
        ) : (
          <>
            <p className="sh-msg is-ok"><Check size={16} /> Compra concluída! {result.new ? 'Carta nova na sua coleção.' : `Agora você tem ${result.qty} cópias.`}</p>
            <dl className="sh-bill">
              <div><dt>Pago</dt><dd><Icon size={14} /> {fmt(result.price)} {label}</dd></div>
              <div><dt>Saldo atual</dt><dd>{fmt(result.balance)}</dd></div>
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
