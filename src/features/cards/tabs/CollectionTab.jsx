import { useMemo, useState } from 'react'
import CardView from '../components/CardView'
import { TIER_ORDER, tierOf } from '../data/tiers'

// Coleção: todas as cartas do jogo; as que você ainda não tem aparecem como silhueta.
export default function CollectionTab({ catalog, owned, onSelect }) {
  const [tier, setTier] = useState('all')
  const [show, setShow] = useState('all') // all | have | missing

  const rows = useMemo(() => {
    const map = new Map()
    for (const c of catalog) map.set(c.id, { card: c, qty: 0 })
    for (const o of owned) map.set(o.card.id, { card: o.card, qty: o.qty }) // inclui cartas que saíram de circulação
    // quem você tem primeiro; dentro de cada grupo, do mais raro para o mais comum
    return [...map.values()].sort(
      (a, b) =>
        (b.qty > 0) - (a.qty > 0) || tierOf(b.card.tier).rank - tierOf(a.card.tier).rank || b.card.overall - a.card.overall,
    )
  }, [catalog, owned])

  const have = rows.filter((r) => r.qty > 0).length
  const pct = rows.length ? Math.round((have / rows.length) * 100) : 0
  const list = rows.filter((r) => (tier === 'all' || r.card.tier === tier) && (show === 'all' || (show === 'have') === r.qty > 0))

  return (
    <div className="cx-collection">
      <div className="cx-progress">
        <div>
          <b>
            {have} / {rows.length}
          </b>
          <small>cartas na coleção</small>
        </div>
        <span className="cx-bar">
          <i style={{ width: `${pct}%` }} />
        </span>
      </div>

      <div className="cx-filters">
        <button type="button" className={tier === 'all' ? 'is-on' : ''} onClick={() => setTier('all')}>
          Todas
        </button>
        {TIER_ORDER.map((id) => (
          <button key={id} type="button" className={tier === id ? 'is-on' : ''} style={{ '--tier': tierOf(id).color }} onClick={() => setTier(id)}>
            <i /> {tierOf(id).label}
          </button>
        ))}
      </div>
      <div className="cx-filters small">
        {[
          ['all', 'Todas'],
          ['have', 'Tenho'],
          ['missing', 'Faltam'],
        ].map(([id, label]) => (
          <button key={id} type="button" className={show === id ? 'is-on' : ''} onClick={() => setShow(id)}>
            {label}
          </button>
        ))}
      </div>

      {rows.length === 0 && <p className="cx-hint center">Nenhuma carta cadastrada ainda.</p>}
      {rows.length > 0 && list.length === 0 && <p className="cx-hint center">Nada por aqui com esses filtros.</p>}

      <div className="cx-grid">
        {list.map(({ card, qty }) => (
          <div key={card.id} className="cx-cell">
            <CardView card={card} width="100%" qty={qty} hidden={qty === 0} onClick={qty > 0 ? () => onSelect({ card, qty }) : undefined} />
            <small>{qty > 0 ? card.name : '???'}</small>
          </div>
        ))}
      </div>
    </div>
  )
}
