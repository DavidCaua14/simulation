import { Coins, Gem } from 'lucide-react'
import CardView from '../../cards/components/CardView'
import { cardFacts } from './cardFacts'

const fmt = (n) => Number(n).toLocaleString('pt-BR')

// Uma carta da vitrine: carta desenhada, atributos, quantas você tem, disponibilidade e os preços.
export default function ShopItem({ item, wallet, onBuy }) {
  const { card, prices, owned, available } = item
  const f = cardFacts(card)
  const soldOut = available <= 0
  return (
    <article className={`sh-item t-${card.tier} ${soldOut ? 'is-out' : ''}`}>
      <div className="sh-item-card">
        <CardView card={card} width={128} shine={card.tier === 'lenda'} />
        {owned > 0 && <span className="sh-owned">Você tem {owned}</span>}
      </div>
      <h4 className="sh-item-name">{card.name}</h4>
      <p className="sh-item-facts">
        <b>{f.overall}</b> {f.position} · {f.club}
      </p>
      <p className="sh-item-facts muted">{[f.nationality, f.kind].filter(Boolean).join(' · ')}</p>
      <p className={`sh-stock ${soldOut ? 'is-out' : ''}`}>{soldOut ? 'Comprada neste rodízio' : `${available} disponível`}</p>
      <div className="sh-prices">
        {prices.coins != null && (
          <button type="button" className={`sh-price coins ${wallet.coins < prices.coins ? 'is-short' : ''}`} disabled={soldOut}
            onClick={() => onBuy(item, 'coins')} aria-label={`Comprar ${card.name} por ${fmt(prices.coins)} moedas`}>
            <Coins size={14} /> {fmt(prices.coins)}
          </button>
        )}
        {prices.diamonds != null && (
          <button type="button" className={`sh-price gems ${wallet.diamonds < prices.diamonds ? 'is-short' : ''}`} disabled={soldOut}
            onClick={() => onBuy(item, 'diamonds')} aria-label={`Comprar ${card.name} por ${fmt(prices.diamonds)} diamantes`}>
            <Gem size={14} /> {fmt(prices.diamonds)}
          </button>
        )}
      </div>
    </article>
  )
}
