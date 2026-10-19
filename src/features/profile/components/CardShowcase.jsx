import { useMemo, useState } from 'react'
import { RARITIES, getShowcaseCards } from '../data/cards'
import GameCard from './GameCard'
import { CardsIcon, EyeIcon, LockIcon } from './ProfileIcons'

export default function CardShowcase({ isPublic, onTogglePublic }) {
  const cards = useMemo(getShowcaseCards, [])
  const [filter, setFilter] = useState('all')

  const counts = useMemo(() => {
    const map = Object.fromEntries(RARITIES.map((r) => [r.id, 0]))
    cards.forEach((c) => {
      if (map[c.rarity] != null) map[c.rarity] += 1
    })
    return map
  }, [cards])

  // Mais raras primeiro; dentro da raridade, maior nota primeiro
  const groups = RARITIES.map((r) => ({
    rarity: r,
    items: cards.filter((c) => c.rarity === r.id).sort((a, b) => b.rating - a.rating),
  })).filter((g) => g.items.length && (filter === 'all' || filter === g.rarity.id))

  return (
    <section className="pf-panel" aria-labelledby="pf-showcase-title">
      <header className="pf-panel-head">
        <h2 id="pf-showcase-title">
          <CardsIcon size={16} />
          Vitrine de cartas
        </h2>
        <span className="pf-count">{cards.length}</span>
      </header>

      <button
        type="button"
        role="switch"
        aria-checked={isPublic}
        className={`pf-visibility ${isPublic ? 'is-on' : ''}`}
        onClick={() => onTogglePublic(!isPublic)}
      >
        {isPublic ? <EyeIcon size={16} /> : <LockIcon size={16} />}
        <span>
          <strong>{isPublic ? 'Vitrine visível' : 'Vitrine privada'}</strong>
          {isPublic ? 'Outros jogadores podem ver suas cartas raras.' : 'Só você vê suas cartas.'}
        </span>
        <i className="pf-switch" aria-hidden="true" />
      </button>

      <div className="pf-rarity-bar" role="img" aria-label="Distribuição de cartas por raridade">
        {cards.length === 0 ? (
          <span className="empty" />
        ) : (
          RARITIES.filter((r) => counts[r.id]).map((r) => (
            <span key={r.id} style={{ flex: counts[r.id], background: `linear-gradient(90deg,${r.c1},${r.c2})` }} />
          ))
        )}
      </div>

      <div className="pf-chips" role="tablist" aria-label="Filtrar por raridade">
        <button type="button" role="tab" aria-selected={filter === 'all'} className={filter === 'all' ? 'is-on' : ''} onClick={() => setFilter('all')}>
          Todas <b>{cards.length}</b>
        </button>
        {RARITIES.map((r) => (
          <button
            key={r.id}
            type="button"
            role="tab"
            aria-selected={filter === r.id}
            className={filter === r.id ? 'is-on' : ''}
            style={{ '--c1': r.c1, '--c2': r.c2 }}
            onClick={() => setFilter(r.id)}
          >
            <i aria-hidden="true" />
            {r.label} <b>{counts[r.id]}</b>
          </button>
        ))}
      </div>

      {cards.length === 0 ? (
        <div className="pf-empty">
          <div className="pf-empty-slots" aria-hidden="true">
            {[0, 1, 2].map((i) => (
              <span key={i}>
                <LockIcon size={18} />
              </span>
            ))}
          </div>
          <strong>Sua vitrine está vazia</strong>
          <p>Em breve você poderá escolher suas cartas mais raras para exibir aos outros jogadores.</p>
        </div>
      ) : groups.length === 0 ? (
        <p className="pf-hint center">Nenhuma carta dessa raridade ainda.</p>
      ) : (
        groups.map(({ rarity, items }) => (
          <div className="pf-group" key={rarity.id}>
            <h3 style={{ '--c1': rarity.c1, '--c2': rarity.c2 }}>
              <i aria-hidden="true" />
              {rarity.label}
              <small>{items.length}</small>
            </h3>
            <div className="pf-card-grid">
              {items.map((c) => (
                <GameCard key={c.id} card={c} />
              ))}
            </div>
          </div>
        ))
      )}
    </section>
  )
}
