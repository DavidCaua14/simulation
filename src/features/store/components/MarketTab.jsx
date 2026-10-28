import { useCallback, useEffect, useRef, useState } from 'react'
import { ArrowLeftRight, Check, Coins, History, Search, Store, Tag } from 'lucide-react'
import CardView from '../../cards/components/CardView'
import { tierOf } from '../../cards/data/tiers'
import { cancelListing, fetchMarket, fetchMyMarket, fetchSellable } from '../services/storeApi'
import { cardFacts } from './cardFacts'
import { fmt, STATUS_LABEL, timeLeft } from './marketUtils'
import MarketBuySheet from './MarketBuySheet'
import MarketSellSheet from './MarketSellSheet'
import MarketCompare from './MarketCompare'
import { ConfirmSheet, EmptyState, Notice, RarityBadge, Skeleton } from '../../../components/ui/feedback'

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

function Row({ card, children, onClick, compare }) {
  const t = tierOf(card.tier)
  const f = cardFacts(card)
  const El = onClick ? 'button' : 'div'
  return (
    <div className={`mk-item ${compare?.on ? 'is-cmp' : ''}`}>
      <El type={onClick ? 'button' : undefined} className="mk-row" style={{ '--tier': t.color }} onClick={onClick}>
        <CardView card={card} width={58} />
        <span className="mk-row-main">
          <strong>{card.name}</strong>
          <small><b>{f.overall}</b> {f.position} · {f.club}</small>
          <RarityBadge tier={card.tier} small />
        </span>
        <span className="mk-row-side">{children}</span>
      </El>
      {compare && (
        <button type="button" className="mk-cmp-toggle" aria-pressed={compare.on} onClick={compare.toggle}
          aria-label={compare.on ? `Tirar ${card.name} da comparação` : `Comparar ${card.name}`} disabled={!compare.on && compare.full}>
          {compare.on ? <Check size={12} /> : <ArrowLeftRight size={12} />}
        </button>
      )}
    </div>
  )
}

// Para cada carta anunciada: menor preço e quantas ofertas existem entre os anúncios carregados.
function priceStats(items) {
  const m = new Map()
  for (const it of items) {
    const s = m.get(it.card.id) || { min: Infinity, count: 0 }
    s.min = Math.min(s.min, it.price)
    s.count += 1
    m.set(it.card.id, s)
  }
  return m
}

// Mercado entre técnicos: anúncios reais de cartas de outros usuários. Comprar / Vender / Meus anúncios.
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
  const [cmp, setCmp] = useState([]) // até 2 anúncios para comparar
  const [comparing, setComparing] = useState(false)
  const [toCancel, setToCancel] = useState(null)

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
  const stats = priceStats(market?.items || [])
  const cmpItems = cmp.map((id) => market?.items.find((x) => x.id === id)).filter(Boolean)
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
    <section className="mk" aria-label="Mercado entre técnicos">
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
          Taxa de {Number(rules.fee_pct).toLocaleString('pt-BR')}% descontada do vendedor · anúncios valem {rules.listing_hours} h · até {rules.max_active_listings} anúncios por técnico
        </p>
      )}
      {error && <Notice kind="error" onClose={() => setError('')}>{error}</Notice>}

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
          {!market ? <Skeleton rows={4} /> : market.items.length === 0 ? (
            filters.q || filters.tier || filters.min || filters.max ? (
              <EmptyState icon={Search} title="Nada com esses filtros" text="Tente outra raridade, outro nome ou uma faixa de preço maior."
                action="Limpar filtros" onAction={() => setFilters({ q: '', tier: '', min: '', max: '', sort: filters.sort })} />
            ) : (
              <EmptyState icon={Store} title="Mercado vazio por enquanto" text="Ninguém anunciou cartas ainda. Seja o primeiro: anuncie uma carta repetida e receba moedas quando alguém comprar."
                action="Anunciar uma carta" onAction={() => setView('sell')} />
            )
          ) : (
            <div className="mk-list">
              {market.items.map((it) => {
                const st = stats.get(it.card.id)
                const diff = st && st.count > 1 ? Math.round(((it.price - st.min) / st.min) * 100) : null
                const on = cmp.includes(it.id)
                return (
                  <Row key={it.id} card={it.card} onClick={it.mine ? undefined : () => setBuying(it)}
                    compare={{ on, full: cmp.length >= 2, toggle: () => setCmp((c) => (on ? c.filter((x) => x !== it.id) : [...c, it.id].slice(-2))) }}>
                    <b className="mk-price-tag"><Coins size={13} /> {fmt(it.price)}</b>
                    {diff === 0 && <span className="mk-deal is-best">menor preço</span>}
                    {diff > 0 && <span className="mk-deal">+{diff}% que o menor</span>}
                    <small>{it.mine ? 'seu anúncio' : it.seller} · {timeLeft(it.expires_at)}</small>
                  </Row>
                )
              })}
              {market.total > market.items.length && <p className="cx-hint center">Mostrando {market.items.length} de {market.total}. Use os filtros para achar mais.</p>}
            </div>
          )}
        </>
      )}

      {view === 'sell' && (
        !sellable ? <Skeleton rows={3} /> : sellable.length === 0 ? (
          <EmptyState icon={Tag} title="Nada para vender ainda" text="Só cartas Destaque, Lenda e Épica entram no mercado. Abra caixas, gire a roleta ou compre na loja para conseguir as suas."
            action="Ver minha coleção" onAction={onOpenCollection} />
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
        !mine ? <Skeleton rows={3} /> : (
          <>
            <h4 className="gx-subtitle">À venda agora <small>{mine.active.length} de {rules?.max_active_listings ?? 10}</small></h4>
            {mine.active.length === 0 ? <EmptyState compact icon={Tag} text="Nenhum anúncio ativo." action="Anunciar uma carta" onAction={() => setView('sell')} /> : (
              <div className="mk-list">
                {mine.active.map((l) => (
                  <Row key={l.id} card={l.card}>
                    <b className="mk-price-tag"><Coins size={13} /> {fmt(l.price)}</b>
                    <small>recebe {fmt(l.seller_receives)} · {timeLeft(l.expires_at)}</small>
                    <button type="button" className="mk-cancel" disabled={busyId === l.id} onClick={() => setToCancel(l)}>
                      {busyId === l.id ? '…' : 'Cancelar'}
                    </button>
                  </Row>
                ))}
              </div>
            )}
            <h4 className="gx-subtitle">Histórico</h4>
            {mine.history.length === 0 ? <EmptyState compact icon={History} text="Nenhuma venda ou compra ainda." /> : (
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

      {view === 'buy' && cmp.length > 0 && (
        <div className="mk-cmp-bar" role="region" aria-label="Comparação">
          <span><ArrowLeftRight size={14} /> {cmp.length === 1 ? 'Escolha mais 1 anúncio' : '2 anúncios escolhidos'}</span>
          <button type="button" className="gx-btn-ghost" onClick={() => setCmp([])}>Limpar</button>
          <button type="button" className="gx-btn" disabled={cmpItems.length < 2} onClick={() => setComparing(true)}>Comparar</button>
        </div>
      )}
      {comparing && cmpItems.length === 2 && (
        <MarketCompare listings={cmpItems} onClose={() => setComparing(false)} onBuy={(l) => { setComparing(false); setBuying(l) }} />
      )}
      {toCancel && (
        <ConfirmSheet
          title="Cancelar anúncio?"
          text={`${toCancel.card.name} sai do mercado e volta para a sua coleção. Nada é cobrado.`}
          confirmLabel="Cancelar anúncio"
          cancelLabel="Manter"
          busy={busyId === toCancel.id}
          onCancel={() => setToCancel(null)}
          onConfirm={() => cancel(toCancel.id).then(() => setToCancel(null))}
        />
      )}
      {buying && (
        <MarketBuySheet
          offers={stats.get(buying.card.id)}
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
