import { Coins, Gem, Zap } from 'lucide-react'
import CardView from './CardView'
import { tierOf } from '../data/tiers'

// Resumo de "abrir todas": total de prêmios + as cartas que vieram (repetidas agrupadas).
export default function OpenSummary({ results, onClose }) {
  const sum = (k) => results.reduce((a, r) => a + (r[k] || 0), 0)
  const cards = []
  const idx = {}
  for (const r of results) {
    if (!r.card) continue
    if (idx[r.card.id] == null) {
      idx[r.card.id] = cards.length
      cards.push({ card: r.card, n: 0, isNew: false })
    }
    const c = cards[idx[r.card.id]]
    c.n += 1
    if (r.card_new) c.isNew = true
  }
  cards.sort((a, b) => tierOf(b.card.tier).rank - tierOf(a.card.tier).rank || b.card.overall - a.card.overall)

  return (
    <div className="bx-overlay bx-summary" role="dialog" aria-modal="true" aria-label="Resumo das caixas">
      <div className="bx-bg" />
      <div className="bx-sum-body">
        <h2>{results.length} caixa{results.length === 1 ? '' : 's'} aberta{results.length === 1 ? '' : 's'}</h2>
        <div className="bx-chips static">
          <span className="bx-chip coins"><Coins size={16} /> +{sum('coins')}</span>
          <span className="bx-chip energy"><Zap size={16} fill="currentColor" /> +{sum('energy')}</span>
          {sum('diamonds') > 0 && <span className="bx-chip gems"><Gem size={16} /> +{sum('diamonds')}</span>}
        </div>
        <div className="bx-sum-grid">
          {cards.map(({ card, n, isNew }) => (
            <div key={card.id} className="bx-sum-item">
              <CardView card={card} width={92} />
              {isNew && <em>NOVA</em>}
              {n > 1 && <b>x{n}</b>}
            </div>
          ))}
        </div>
      </div>
      <footer className="bx-bottom">
        <div className="bx-actions">
          <button type="button" className="bx-btn" onClick={onClose}>
            Concluir
          </button>
        </div>
      </footer>
    </div>
  )
}
