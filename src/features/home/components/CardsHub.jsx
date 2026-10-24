import { ChevronRight, Layers, Lock, Store } from 'lucide-react'
import CardView from '../../cards/components/CardView'
import { tierOf } from '../../cards/data/tiers'
import lojaImg from '../assets/loja.webp'

// Coleção & loja: caixas esperando (grátis/conquistadas jogando), vitrine das melhores cartas
// do jogador e o acesso à loja (ainda "em breve" — nada pago aparece aqui).
export default function CardsHub({ boxes, summary, onNavigate, storeLocked = true }) {
  const count = boxes.length
  const best = boxes.reduce((b, x) => (tierOf(x.tier).rank > tierOf(b?.tier).rank ? x : b), boxes[0])
  const t = tierOf(best?.tier || 'basica')
  const pct = summary.total ? Math.round((summary.owned / summary.total) * 100) : 0

  return (
    <div className="hm-cards">
      {/* Caixa de entrada */}
      <button
        type="button"
        className={`hm-inbox ${count ? 'has-boxes' : ''}`}
        style={{ '--tier': t.color, '--glow': t.glow }}
        onClick={() => onNavigate?.('cards', { tab: 'inbox' })}
      >
        <span className="hm-inbox-pack">
          <span className="hm-inbox-glow" aria-hidden="true" />
          <img src={count ? t.closed : t.open} alt="" draggable="false" />
          {count > 0 && <span className="hm-inbox-count">{count > 99 ? '99+' : count}</span>}
        </span>
        <span className="hm-inbox-text">
          <strong>{count ? `${count} caixa${count === 1 ? '' : 's'} para abrir` : 'Caixa de entrada'}</strong>
          <span>{count ? 'Toque para abrir e revelar suas cartas' : 'Novas caixas todo dia e a cada vitória'}</span>
          <span className="hm-inbox-tags">
            <span className="gx-tag is-free">Grátis · diária</span>
            <span className="gx-tag is-earn">Ganhe jogando</span>
          </span>
        </span>
      </button>

      {/* Coleção */}
      <button type="button" className="hm-collection" onClick={() => onNavigate?.('cards', { tab: 'collection' })}>
        <span className="hm-fan" aria-hidden="true">
          {summary.top.length ? (
            summary.top.map((c, i) => <CardView key={c.id} card={c} width={64} className={`hm-fan-${i}`} />)
          ) : (
            <span className="hm-fan-empty">
              <Layers size={26} />
            </span>
          )}
        </span>
        <span className="hm-collection-text">
          <small>Coleção</small>
          <strong>
            {summary.owned}
            <em>/{summary.total || '—'}</em>
          </strong>
          <span className="gx-xp">
            <i style={{ width: `${pct}%` }} />
          </span>
        </span>
        <ChevronRight size={18} className="hm-chev" />
      </button>

      {/* Loja */}
      <button type="button" className={`hm-store ${storeLocked ? 'is-locked' : ''}`} disabled={storeLocked} onClick={() => onNavigate?.('store')}>
        <img src={lojaImg} alt="" />
        <span className="hm-store-scrim" aria-hidden="true" />
        <span className="hm-store-icon">
          <Store size={18} />
        </span>
        <span className="hm-store-text">
          <strong>Loja</strong>
          <span>Pacotes, itens e novidades</span>
        </span>
        {storeLocked && (
          <span className="gx-tag is-soon">
            <Lock /> Em breve
          </span>
        )}
      </button>
    </div>
  )
}
