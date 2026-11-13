import { useCallback, useEffect, useMemo, useState } from 'react'
import { Banknote, Coins, Crown, DoorClosed, Flame, Gavel, Hourglass, Lock, Sprout, TrendingUp, Undo2, Users } from 'lucide-react'
import { EmptyState, Notice, Skeleton } from '../../components/ui/feedback'
import OnlineCrest from './components/OnlineCrest'
import { FutCard, OvrBadge } from './components/PlayerFut'
import { bidOnline, cancelOnlineLot, fetchOnlineMarket } from './services/onlineApi'
import { money, moneyShort, timeLeft } from './onlineUtils'

const STEPS = [
  [0, 'Mínimo'],
  [0.1, '+10%'],
  [0.25, '+25%'],
  [0.5, '+50%'],
]
const round100 = (n) => Math.ceil(n / 100) * 100

function Auction({ lot, now, busy, wallet, coins, closed, onBid, onCancel }) {
  const [step, setStep] = useState(0)
  const opensIn = new Date(lot.opens_at).getTime() - now
  const locked = opensIn > 0
  const special = lot.featured >= 8
  const left = new Date(lot.ends_at).getTime() - now
  const hot = !locked && left < 120000
  const amount = step === 0 ? lot.min_bid : round100(lot.min_bid * (1 + step))
  const need = amount - (lot.leading ? lot.best_bid : 0) - wallet.free
  const coinCost = need > 0 ? Math.ceil(need / coins.bid_rate) : 0
  const coinRoom = coins.unlimited ? coins.wallet : Math.max(0, (coins.cap ?? 0) - (coins.converted ?? 0))
  const canCoins = coinCost > 0 && coinCost <= coins.wallet && coinCost <= coinRoom
  const blocked = coinCost > 0 && !canCoins
  const p = lot.player
  return (
    <article className={`on-auc ${special ? 'is-special' : ''} ${p.legend ? 'is-legend' : ''} ${locked ? 'is-locked' : ''} ${lot.featured ? 'is-featured' : ''} ${lot.leading ? 'is-leading' : lot.bidding ? 'is-outbid' : ''} ${hot ? 'is-hot' : ''}`}>
      <FutCard p={p} club={lot.seller} size="sm" />
      <div className="on-auc-body">
        {special && <span className="on-auc-tag"><Crown size={11} /> {p.legend ? 'Lenda' : 'Destaque'}</span>}
        {!special && !lot.seller && p.age <= 23 && p.pot - p.ovr >= 6 && <span className="on-auc-tag is-prospect"><Sprout size={11} /> Promessa · pot. {p.pot}</span>}
        <header>
          {locked
            ? <span className="on-auc-clock is-locked"><Lock size={13} /> Abre às {new Date(lot.opens_at).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}</span>
            : <span className={`on-auc-clock ${hot ? 'is-hot' : ''}`}>{hot ? <Flame size={13} /> : <Hourglass size={13} />} {timeLeft(left)}</span>}
          {lot.bidders > 0 && <span className="on-auc-count"><Users size={12} /> {lot.bidders}</span>}
          {lot.seller && <span className="on-auc-seller"><OnlineCrest club={lot.seller} size={16} /> {lot.seller.short}</span>}
        </header>
        <div className="on-auc-price">
          <small>{lot.best_bid ? 'Maior lance' : 'Lance inicial'}</small>
          <b>{money(lot.best_bid || lot.start_price)}</b>
          {lot.best_club && (
            <span className="on-auc-leader"><OnlineCrest club={lot.best_club} size={18} /> {lot.leading ? 'Você lidera' : lot.best_club.name}</span>
          )}
        </div>
        {lot.history?.length > 1 && (
          <ol className="on-auc-hist">
            {lot.history.slice(0, 3).map((h, i) => <li key={i} className={h.me ? 'is-me' : ''}><span>{h.club.short}</span><b>{moneyShort(h.amount)}</b></li>)}
          </ol>
        )}
        {locked && <span className="on-auc-wait">Faltam {timeLeft(opensIn)}</span>}
        {lot.mine && !lot.best_bid && !locked && (
          <button type="button" className="gx-btn-ghost on-auc-cancel" disabled={busy} onClick={() => onCancel(lot)}><Undo2 size={14} /> Retirar do leilão</button>
        )}
        {!lot.mine && !locked && closed && <span className="on-auc-wait"><DoorClosed size={13} /> Mercado fechado</span>}
        {!lot.mine && !locked && !closed && (
          <>
            <div className="on-auc-steps" role="group" aria-label="Valor do lance">
              {STEPS.map(([v, label]) => <button key={v} type="button" className={step === v ? 'is-on' : ''} onClick={() => setStep(v)}>{label}</button>)}
            </div>
            <button type="button" className={`gx-btn on-auc-bid ${coinCost > 0 ? 'is-coins' : ''}`} disabled={busy || blocked || left <= 0} onClick={() => onBid(lot, amount, coinCost > 0)}>
              <Gavel size={16} /> {money(amount)}
              {coinCost > 0 && <em><Coins size={12} /> {coinCost}</em>}
            </button>
            {coinCost > coinRoom && <small>{coins.unlimited ? 'Moedas insuficientes para completar o lance.' : 'Limite de aporte da temporada insuficiente.'}</small>}
          </>
        )}
      </div>
    </article>
  )
}

// MERCADO: leilões iguais para todos, só no horário de funcionamento (data.hours). Sem lance, saem na virada da hora;
// cada lance põe o relógio em 5 minutos. Toda hora entram cartas base, destaques e lendas; técnicos também leiloam seus jogadores.
const KINDS = [
  ['all', 'Todos', () => true],
  ['legend', 'Lendas', (l) => l.featured >= 8 && l.player.legend],
  ['star', 'Destaques', (l) => l.featured >= 8 && !l.player.legend],
  ['base', 'Base', (l) => l.featured < 8],
]
export default function OnlineMarket({ notify, onChanged }) {
  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [offset, setOffset] = useState(0)
  const [now, setNow] = useState(() => Date.now())
  const [view, setView] = useState('featured')
  const [kind, setKind] = useState('all')

  const apply = useCallback((d) => {
    setOffset(new Date(d.server_now).getTime() - Date.now())
    setData(d)
  }, [])
  const load = useCallback(() => fetchOnlineMarket().then(apply).catch((e) => setError(e.message)), [apply])
  useEffect(() => {
    load()
  }, [load])
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 1000)
    return () => clearInterval(id)
  }, [])
  const serverNow = now + offset
  const open = useMemo(() => (data?.lots || []).filter((l) => l.featured >= 8 || new Date(l.opens_at).getTime() <= serverNow), [data, serverNow])
  const active = open.some((l) => l.bidding || l.mine || new Date(l.ends_at).getTime() - serverNow < 120000)
  useEffect(() => {
    const id = setInterval(load, active ? 5000 : 15000)
    return () => clearInterval(id)
  }, [load, active])

  const run = (job, ok) => {
    setBusy(true)
    job
      .then((d) => {
        apply(d)
        if (ok) notify?.(ok, 'success')
        onChanged?.()
      })
      .catch((e) => {
        notify?.(e.message, 'alert')
        load()
      })
      .finally(() => setBusy(false))
  }

  if (!data) return error ? <Notice kind="error">{error}</Notice> : <Skeleton rows={6} />
  const c = data.club
  const coins = data.coins || { wallet: 0, bid_rate: 1, cap: 0, converted: 0 }
  const wallet = { free: c.cash - c.reserved }
  const lists = {
    featured: open.filter((l) => !l.mine),
    mine: open.filter((l) => l.mine || l.bidding),
  }
  const hours = data.hours
  const closed = hours ? !hours.open : false
  const hh = (n) => `${String(n % 24).padStart(2, '0')}:00`
  const cancel = (lot) => run(cancelOnlineLot(lot.id), `${lot.player.name} voltou ao elenco`)
  const bid = (lot, v, useCoins) => run(bidOnline(lot.id, v, useCoins), `Lance de ${money(v)} em ${lot.player.name}`)
  const kindTest = (KINDS.find(([k]) => k === kind) || KINDS[0])[2]
  const list = view === 'featured' ? lists.featured.filter(kindTest) : lists[view] || []
  return (
    <section className="on-market">
      <div className="on-wallet">
        <span><small><Banknote size={11} /> Caixa livre</small><b>{moneyShort(wallet.free)}</b></span>
        <span><small><Gavel size={11} /> Em lances</small><b>{moneyShort(c.reserved)}</b></span>
        <span><small><Coins size={11} /> Moedas</small><b>{coins.wallet}</b></span>
      </div>
      {hours && (
        <div className={`on-mkt-hours ${closed ? 'is-closed' : ''}`}>
          {closed ? <><DoorClosed size={14} /> Mercado fechado <b>Abre às {hours.open_label || hh(hours.open_hour)}</b></> : <><Gavel size={14} /> Mercado aberto <b>Fecha às {hours.close_label || hh(hours.close_hour)}</b></>}
        </div>
      )}
      {c.debt > 0 && <Notice kind="error">Dívida de {money(c.debt)}: lances bloqueados.</Notice>}
      <div className="on-seg on-seg-3" role="tablist">
        <button type="button" role="tab" aria-selected={view === 'featured'} className={view === 'featured' ? 'is-on' : ''} onClick={() => setView('featured')}><Flame size={14} /> Leilões</button>
        <button type="button" role="tab" aria-selected={view === 'mine'} className={view === 'mine' ? 'is-on' : ''} onClick={() => setView('mine')}><Gavel size={14} /> Meus{lists.mine.length ? ` ${lists.mine.length}` : ''}</button>
        <button type="button" role="tab" aria-selected={view === 'recent'} className={view === 'recent' ? 'is-on' : ''} onClick={() => setView('recent')}><TrendingUp size={14} /> Fechados</button>
      </div>

      {view === 'featured' && lists.featured.length > 0 && (
        <div className="on-seg on-seg-4 on-mkt-kinds" role="tablist" aria-label="Tipo de carta">
          {KINDS.map(([k, label, test]) => (
            <button key={k} type="button" role="tab" aria-selected={kind === k} className={kind === k ? 'is-on' : ''} onClick={() => setKind(k)}>
              {label} {lists.featured.filter(test).length}
            </button>
          ))}
        </div>
      )}
      {view !== 'recent' && (
        <>
          {list.length === 0 && (
            <EmptyState compact icon={Gavel} title={view !== 'featured' ? 'Nenhum leilão em andamento' : lists.featured.length ? 'Nenhum leilão desse tipo agora' : `Próximos jogadores às ${hours?.open_label || '08:00'}`} />
          )}
          <div className="on-aucs">
            {list.map((l) => <Auction key={l.id} lot={l} now={serverNow} busy={busy} wallet={wallet} coins={coins} closed={closed} onBid={bid} onCancel={cancel} />)}
          </div>
        </>
      )}
      {view === 'recent' && (
        <ul className="on-deals-list">
          {data.recent.length === 0 && <EmptyState compact icon={TrendingUp} title="Nenhum negócio fechado" />}
          {data.recent.map((l) => (
            <li key={l.id} className="on-deal">
              <OvrBadge p={l.player} small />
              <span className="on-deal-who"><strong>{l.player.name}</strong><small>{l.seller ? l.seller.short : 'Mercado'} → {l.best_club?.short}</small></span>
              <OnlineCrest club={l.best_club} size={22} />
              <b>{moneyShort(l.best_bid)}</b>
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}
