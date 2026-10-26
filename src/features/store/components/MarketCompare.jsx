import { Coins, X } from 'lucide-react'
import CardView from '../../cards/components/CardView'
import { tierOf } from '../../cards/data/tiers'
import { RarityBadge } from '../../../components/ui/feedback'
import { cardFacts } from './cardFacts'
import { fmt, timeLeft } from './marketUtils'

// Comparação lado a lado de dois anúncios: nota, posição, raridade, clube, preço e custo por ponto de nota.
// O melhor valor de cada linha fica em destaque. "Comprar" abre a confirmação normal do mercado.
const perPoint = (l) => (l.card.overall ? l.price / l.card.overall : null)

export default function MarketCompare({ listings, onBuy, onClose }) {
  const [a, b] = listings
  const best = (fa, fb, higher) => {
    if (fa == null || fb == null || fa === fb) return [false, false]
    return higher ? [fa > fb, fb > fa] : [fa < fb, fb < fa]
  }
  const rows = [
    { label: 'Nota', get: (l) => l.card.overall, show: (v) => v, cmp: (x, y) => best(x, y, true) },
    { label: 'Raridade', get: (l) => tierOf(l.card.tier).rank, show: (_, l) => <RarityBadge tier={l.card.tier} small />, cmp: (x, y) => best(x, y, true) },
    { label: 'Posição', get: (l) => cardFacts(l.card).position },
    { label: 'Clube', get: (l) => cardFacts(l.card).club },
    { label: 'País', get: (l) => cardFacts(l.card).nationality },
    { label: 'Preço', get: (l) => l.price, show: (v) => <><Coins size={12} /> {fmt(v)}</>, cmp: (x, y) => best(x, y, false) },
    { label: 'Moedas por ponto', get: perPoint, show: (v) => (v == null ? '—' : fmt(Math.round(v))), cmp: (x, y) => best(x, y, false) },
    { label: 'Vendedor', get: (l) => l.seller },
    { label: 'Termina em', get: (l) => timeLeft(l.expires_at) },
  ]
  return (
    <div className="cx-sheet-wrap" role="dialog" aria-modal="true" aria-label="Comparar anúncios" onClick={onClose}>
      <div className="cx-sheet mk-cmp-sheet" onClick={(e) => e.stopPropagation()}>
        <button type="button" className="cx-sheet-x" onClick={onClose} aria-label="Fechar"><X size={18} /></button>
        <h3>Comparar</h3>
        <div className="mk-cmp-cards">
          {[a, b].map((l) => (
            <div key={l.id} className="mk-cmp-col">
              <CardView card={l.card} width={112} shine={tierOf(l.card.tier).rank >= 3} />
              <strong>{l.card.name}</strong>
            </div>
          ))}
        </div>
        <table className="mk-cmp-table">
          <tbody>
            {rows.map((r) => {
              const va = r.get(a)
              const vb = r.get(b)
              const [wa, wb] = r.cmp ? r.cmp(va, vb) : [false, false]
              const show = r.show || ((v) => v)
              return (
                <tr key={r.label}>
                  <td className={wa ? 'is-best' : ''}>{show(va, a)}</td>
                  <th scope="row">{r.label}</th>
                  <td className={wb ? 'is-best' : ''}>{show(vb, b)}</td>
                </tr>
              )
            })}
          </tbody>
        </table>
        <div className="mk-cmp-actions">
          {[a, b].map((l) => (
            <button key={l.id} type="button" className="gx-btn" disabled={l.mine} onClick={() => onBuy(l)}>
              {l.mine ? 'Seu anúncio' : <><Coins size={15} /> {fmt(l.price)}</>}
            </button>
          ))}
        </div>
        <p className="cx-hint">Em verde, o melhor valor de cada linha. "Moedas por ponto" = preço ÷ nota.</p>
      </div>
    </div>
  )
}
