import { Inbox, Layers } from 'lucide-react'
import { tierOf } from '../data/tiers'

// Atalhos da Home: caixa de entrada (com contador) e coleção de cartas.
export default function RewardsStrip({ count, onSelect }) {
  return (
    <div className="rs-strip">
      <button type="button" className={`rs-btn ${count > 0 ? 'has-boxes' : ''}`} onClick={() => onSelect?.('cards', { tab: 'inbox' })}>
        <span className="rs-ico">
          {count > 0 ? <img src={tierOf('basica').closed} alt="" draggable="false" /> : <Inbox size={22} />}
          {count > 0 && <span className="rs-badge">{count > 99 ? '99+' : count}</span>}
        </span>
        <span className="rs-text">
          <strong>Caixa de entrada</strong>
          <small>{count > 0 ? `${count} caixa${count === 1 ? '' : 's'} para abrir` : 'Nenhuma caixa agora'}</small>
        </span>
      </button>
      <button type="button" className="rs-btn" onClick={() => onSelect?.('cards', { tab: 'collection' })}>
        <span className="rs-ico">
          <Layers size={22} />
        </span>
        <span className="rs-text">
          <strong>Minhas cartas</strong>
          <small>Coleção</small>
        </span>
      </button>
    </div>
  )
}
