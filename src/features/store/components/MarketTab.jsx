import { useCallback, useEffect, useRef, useState } from 'react'
import { CircleAlert, Coins, Search } from 'lucide-react'
import CardView from '../../cards/components/CardView'
import { tierOf } from '../../cards/data/tiers'
import { cancelListing, fetchMarket, fetchMyMarket, fetchSellable } from '../services/storeApi'
import { cardFacts } from './cardFacts'
import { fmt, STATUS_LABEL, timeLeft } from './marketUtils'
import MarketBuySheet from './MarketBuySheet'
import MarketSellSheet from './MarketSellSheet'

const VIEWS = [
  { id: 'buy', label: 'Comprar' },
  { id: 'sell', label: 'Vender' },
  { id: 'mine', label: 'Meus anúncios' },
]
const SORTS = [
  { id: 'newest', label: 'Mais novos' },
  { id: 'price_asc', label: 'Menor preço' },
  { id: 'price_desc', label: 'Maior preço' },
  { id: 'overall', label: 'Maior nota' },
]

function Row({ card, children, onClick }) {
  const t = tierOf(card.tier)
  const f = cardFacts(card)
  const Tag = onClick ? 'button' : 'div'
  return (
    <Tag type={onClick ? 'button' : undefined} className="mk-row" style={{ '--tier': t.color }} onClick={onClick}>
      <CardView card={card} width={58} />
      <span className="mk-row-main">
        <strong>{card.name}</strong>
        <small><b>{f.overall}</b> {f.position} · {t.label} · {f.club}</small>
      </span>
      <span className="mk-row-side">{children}</span>
    </Tag>
  )
}

// Mercado entre jogadores: anúncios reais de cartas de outros usuários. Comprar / Vender / Meus anúncios.
export default function MarketTab({ wallet, onChanged, onOpenCollection, initialSell }) {
  const [view, setView] = useState(initialSell ? 'sell' : 'buy')
  const [filters, setFilters] = useState({ q: '', tier: '', min: '', max: '', sort: 'newest' })
  const [market, setMarket] = useState(null)
  const [mine, setMine] = useState(null)
  const [sellable, setSellable] = useState(null)
  const [error, setError] = useState('')
  const [buying, setBuying] = useState(null)
  const [selling, setSelling] = useState(null)
  const [busyId, setBusyId] = useState(null)

  const loadBuy = useCallback(async (f) => {
    try {
      setMarket(await fetchMarket(f))
      setError('')
    } catch (e) {
      setError(e.message)
    }
  }, [])
  const loadMine = useCallback(async () => {
    try {
      const [m, s] = await Promise.all([fetchMyMarket(), fetchSellable()])
      setMine(m)
      setSellable(s)
      setError('')
    } catch (e) {
      setError(e.message)
    }
  }, [])

  useEffect(() => {
    const t = setTimeout(() => loadBuy(filters), 250) // espera parar de digitar
    return () => clearTimeout(t)
  }, [filters, loadBuy])
  useEffect(() => {
    loadMine()
  }, [loadMine])

  // veio da Coleção com "Vender no mercado": abre direto a carta escolhida (uma vez só)
  const openedSell = useRef(false)
  useEffect(() => {
    if (initialSell && sellable && !openedSell.current) {
      openedSell.current = true
      const e = sellable.find((x) => x.card.id === initialSell)
      if (e && !e.listed) setSelling(e)
    }
  }, [initialSell, sellable])

  const rules = market?.rules || mine?.rules
  const set = (k) => (e) => setFilters((f) => ({ ...f, [k]: e.target.value }))

  async function cancel(id) {
    setBusyId(id)
    try {
      await cancelListing(id)
      await loadMine()
      loadBuy(filters)
      onChanged?.()
    } catch (e) {
      setError(e.message)
    } finally {
      setBusyId(null)
    }
  }

  return (
    <section className="mk" aria-label="Mercado entre jogadores">
      <div className="mk-views" role="tablist">
        {VIEWS.map((v) => (
          <button key={v.id} type="button" role="tab" aria-selected={view === v.id} className={view === v.id ? 'is-on' : ''} onClick={() => setView(v.id)}>
            {v.label}
            {v.id === 'mine' && mine?.active?.length > 0 && <span className="cx-count">{mine.active.length}</span>}
          </button>
        ))}
      </div>
      {rules && (
        <p className="mk-rules">
          Taxa de {Number(rules.fee_pct).toLocaleString('pt-BR')}% descontada do vendedor · anúncios valem {rules.listing_hours} h · até {rules.max_active_listings} anúncios por jogador
        </p>
      )}
      {error && <p className="sh-msg is-error"><CircleAlert size={14} /> {error}</p>}

      {view === 'buy' && (
        <>
          <div className="mk-filters">
            <label className="mk-search"><Search size={15} /><input type="search" placeholder="Nome do jogador" value={filters.q} onChange={set('q')} aria-label="Buscar pelo nome" /></label>
            <select value={filters.tier} onChange={set('tier')} aria-label="Raridade">
              <option value="">Todas</option>
              <option value="destaque">Destaque</option>
              <option value="lenda">Lenda</option>
              <option value="epica">Épica</option>
            </select>
            <select value={filters.sort} onChange={set('sort')} aria-label="Ordenar">
              {SORTS.map((s) => <option key={s.id} value={s.id}>{s.label}</option>)}
            </select>
            <input type="number" inputMode="numeric" placeholder="Preço mín." value={filters.min} onChange={set('min')} aria-label="Preço mínimo" />
            <input type="number" inputMode="numeric" placeholder="Preço máx." value={filters.max} onChange={set('max')} aria-label="Preço máximo" />
          </div>
          {!market ? <p className="cx-hint center">Carregando anúncios…</p> : market.items.length === 0 ? (
            <p className="cx-hint center">Nenhum anúncio {filters.q || filters.tier || filters.min || filters.max ? 'com esses filtros' : 'no momento'}. Que tal anunciar uma carta repetida?</p>
          ) : (
            <div className="mk-list">
              {market.items.map((it) => (
                <Row key={it.id} card={it.card} onClick={it.mine ? undefined : () => setBuying(it)}>
                  <b className="mk-price-tag"><Coins size={13} /> {fmt(it.price)}</b>
                  <small>{it.mine ? 'seu anúncio' : it.seller} · {timeLeft(it.expires_at)}</small>
                </Row>
              ))}
              {market.total > market.items.length && <p className="cx-hint center">Mostrando {market.items.length} de {market.total}. Use os filtros para achar mais.</p>}
            </div>
          )}
        </>
      )}

      {view === 'sell' && (
        !sellable ? <p className="cx-hint center">Carregando sua coleção…</p> : sellable.length === 0 ? (
          <p className="cx-hint center">Você ainda não tem cartas Destaque, Lenda ou Épica para vender. Básicas não entram no mercado.</p>
        ) : (
          <div className="mk-list">
            <p className="cx-hint">Escolha uma carta da sua coleção (Destaque, Lenda ou Épica):</p>
            {sellable.map((e) => (
              <Row key={e.card.id} card={e.card} onClick={e.listed ? undefined : () => setSelling(e)}>
                {e.listed ? <small className="mk-tag">já à venda</small> : <b className="mk-sell">Vender</b>}
                <small>você tem {e.qty}</small>
              </Row>
            ))}
          </div>
        )
      )}

      {view === 'mine' && (
        !mine ? <p className="cx-hint center">Carregando…</p> : (
          <>
            <h4 className="mk-h">À venda agora</h4>
            {mine.active.length === 0 ? <p className="cx-hint">Nenhum anúncio ativo.</p> : (
              <div className="mk-list">
                {mine.active.map((l) => (
                  <Row key={l.id} card={l.card}>
                    <b className="mk-price-tag"><Coins size={13} /> {fmt(l.price)}</b>
                    <small>recebe {fmt(l.seller_receives)} · {timeLeft(l.expires_at)}</small>
                    <button type="button" className="mk-cancel" disabled={busyId === l.id} onClick={() => cancel(l.id)}>
                      {busyId === l.id ? '…' : 'Cancelar'}
                    </button>
                  </Row>
                ))}
              </div>
            )}
            <h4 className="mk-h">Histórico</h4>
            {mine.history.length === 0 ? <p className="cx-hint">Nenhuma venda ou compra ainda.</p> : (
              <div className="mk-list">
                {mine.history.map((h) => (
                  <Row key={`${h.id}-${h.role}`} card={h.card}>
                    <b className={`mk-hist ${h.role === 'bought' ? 'is-out' : h.status === 'sold' ? 'is-in' : ''}`}>
                      {h.role === 'bought' ? `− ${fmt(h.price)}` : h.status === 'sold' ? `+ ${fmt(h.received)}` : STATUS_LABEL[h.status]}
                    </b>
                    <small>
                      {h.role === 'bought' ? `comprada de ${h.other}` : h.status === 'sold' ? `vendida a ${h.other} (taxa ${fmt(h.fee)})` : `${fmt(h.price)} moedas`} ·{' '}
                      {new Date(h.at).toLocaleDateString('pt-BR')}
                    </small>
                  </Row>
                ))}
              </div>
            )}
          </>
        )
      )}

      {buying && (
        <MarketBuySheet
          listing={buying}
          coins={wallet.coins ?? 0}
          onClose={() => { setBuying(null); loadBuy(filters); loadMine() }}
          onBought={() => onChanged?.()}
          onOpenCollection={onOpenCollection}
        />
      )}
      {selling && rules && (
        <MarketSellSheet
          entry={selling}
          rules={rules}
          onClose={() => { setSelling(null); loadMine(); loadBuy(filters) }}
          onListed={() => onChanged?.()}
        />
      )}
    </section>
  )
}
