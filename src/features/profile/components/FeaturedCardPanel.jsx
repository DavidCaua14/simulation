import { useEffect, useState } from 'react'
import CardView from '../../cards/components/CardView'
import { tierOf, TIER_ORDER } from '../../cards/data/tiers'
import { fetchCollection } from '../../cards/services/cardsApi'
import { setFeaturedCard } from '../services/profileApi'
import Sheet from './Sheet'
import '../../cards/cards.css'
import { Plus } from 'lucide-react'
import { Skeleton } from '../../../components/ui/feedback'

// Carta em destaque: o jogador escolhe uma carta que TEM (o servidor confere). Se ela for vendida,
// anunciada ou descartada, o servidor tira o destaque sozinho.
export default function FeaturedCardPanel({ card, editable, onChanged }) {
  const [picking, setPicking] = useState(false)
  const [owned, setOwned] = useState(null)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    if (!picking || owned) return
    fetchCollection()
      .then((rows) => setOwned((rows || []).filter((r) => r.card).sort((a, b) =>
        TIER_ORDER.indexOf(b.card.tier) - TIER_ORDER.indexOf(a.card.tier) || b.card.overall - a.card.overall)))
      .catch((e) => setError(e.message))
  }, [picking, owned])

  async function choose(id) {
    setBusy(true)
    setError('')
    try {
      await setFeaturedCard(id)
      setPicking(false)
      onChanged?.()
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <section className="pf-panel pf-featured" aria-labelledby="pf-featured-title">
      <header className="pf-panel-head">
        <h2 id="pf-featured-title">Carta em destaque</h2>
        {editable && <button type="button" className="pf-link" onClick={() => setPicking(true)}>{card ? 'Trocar' : 'Escolher'}</button>}
      </header>
      {card ? (
        <div className="pf-featured-body" style={{ '--tier': tierOf(card.tier).color }}>
          <CardView card={card} width={150} shine />
          <div>
            <strong>{card.name}</strong>
            <span>{tierOf(card.tier).label} · nota {card.overall}{card.position ? ` · ${card.position}` : ''}</span>
          </div>
        </div>
      ) : (
        <button type="button" className="pf-featured-empty" disabled={!editable} onClick={() => editable && setPicking(true)}>
          <span className="pf-card-ghost" aria-hidden="true"><Plus size={22} /></span>
          <span>{editable ? <><b>Mostre sua melhor carta</b>Escolha uma carta da coleção para exibir no seu perfil.</> : 'Nenhuma carta em destaque.'}</span>
        </button>
      )}
      {picking && (
        <Sheet title="Escolher carta em destaque" onClose={() => setPicking(false)}>
          {error && <p className="pf-error">{error}</p>}
          {!owned ? <Skeleton rows={1} variant="tall" /> : owned.length === 0 ? (
            <p className="pf-hint">Você ainda não tem cartas. Abra caixas ou visite a Loja.</p>
          ) : (
            <div className="pf-pick-grid">
              {owned.map((o) => (
                <CardView key={o.card.id} card={o.card} width={96} onClick={busy ? undefined : () => choose(o.card.id)} />
              ))}
            </div>
          )}
          {card && <button type="button" className="pf-btn block" disabled={busy} onClick={() => choose(null)}>Tirar o destaque</button>}
        </Sheet>
      )}
    </section>
  )
}
