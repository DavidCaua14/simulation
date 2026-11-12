import { useCallback, useEffect, useMemo, useState } from 'react'
import { Banknote, Coins, Crown, Flame, Gavel, Hourglass, Lock, TrendingUp, Users } from 'lucide-react'
import { EmptyState, Notice, Skeleton } from '../../components/ui/feedback'
import OnlineCrest from './components/OnlineCrest'
import { FutCard, OvrBadge } from './components/PlayerFut'
import { bidOnline, fetchOnlineMarket } from './services/onlineApi'
import { money, moneyShort, timeLeft } from './onlineUtils'

const STEPS = [
  [0, 'Mínimo'],
  [0.1, '+10%'],
  [0.25, '+25%'],
  [0.5, '+50%'],
]
const round100 = (n) => Math.ceil(n / 100) * 100

function Auction({ lot, now, busy, wallet, coins, onBid }) {
  const [step, setStep] = useState(0)
  const opensIn = new Date(lot.opens_at).getTime() - now
  const locked = opensIn > 0
  const special = lot.featured >= 8
  const left = new Date(lot.ends_at).getTime() - now
  const hot = !locked && left < 120000
  const amount = step === 0 ? lot.min_bid : round100(lot.min_bid * (1 + step))
  const need = amount - (lot.leading ? lot.best_bid : 0) - wallet.free
  const coinCost = need > 0 ? Math.ceil(need / coins.bid_rate) : 0
  const canCoins = coinCost > 0 && coinCost <= coins.wallet
  const blocked = coinCost > 0 && !canCoins
  const p = lot.player
  return (
    <article className={`on-auc ${special ? 'is-special' : ''} ${p.legend ? 'is-legend' : ''} ${locked ? 'is-locked' : ''} ${lot.featured ? 'is-featured' : ''} ${lot.leading ? 'is-leading' : lot.bidding ? 'is-outbid' : ''} ${hot ? 'is-hot' : ''}`}>
      <FutCard p={p} club={lot.seller} size="sm" />
      <div className="on-auc-body">
        {special && <span className="on-auc-tag"><Crown size={11} /> {p.legend ? 'Lenda do dia' : 'Destaque do dia'}</span>}
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
        {!lot.mine && !locked && (
          <>
            <div className="on-auc-steps" role="group" aria-label="Valor do lance">
              {STEPS.map(([v, label]) => <button key={v} type="button" className={step === v ? 'is-on' : ''} onClick={() => setStep(v)}>{label}</button>)}
            </div>
            <button type="button" className={`gx-btn on-auc-bid ${coinCost > 0 ? 'is-coins' : ''}`} disabled={busy || blocked || left <= 0} onClick={() => onBid(lot, amount, coinCost > 0)}>
              <Gavel size={16} /> {money(amount)}
              {coinCost > 0 && <em><Coins size={12} /> {coinCost}</em>}
            </button>
          </>
        )}
      </div>
    </article>
  )
}

// MERCADO: três jogadores reais em leilão, os mesmos para todos. Sem lance, saem na virada da hora; cada lance
// põe o relógio em 5 minutos. Só entra jogador que não está em nenhum clube.
export default function OnlineMarket({ notify, onChanged }) {
  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [offset, setOffset] = useState(0)
  const [now, setNow] = useState(() => Date.now())
  const [view, setView] = useState('featured')

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
  const coins = data.coins || { wallet: 0, bid_rate: 600 }
  const wallet = { free: c.cash - c.reserved }
  const lists = {
    featured: open.filter((l) => !l.mine),
    mine: open.filter((l) => l.mine || l.bidding),
  }
  const bid = (lot, v, useCoins) => run(bidOnline(lot.id, v, useCoins), `Lance de ${money(v)} em ${lot.player.name}`)
  const list = lists[view] || []
  return (
    <section className="on-market">
      <div className="on-wallet">
        <span><small><Banknote size={11} /> Caixa livre</small><b>{moneyShort(wallet.free)}</b></span>
        <span><small><Gavel size={11} /> Em lances</small><b>{moneyShort(c.reserved)}</b></span>
        <span><small><Coins size={11} /> Moedas</small><b>{coins.wallet}</b></span>
      </div>
      {c.debt > 0 && <Notice kind="error">Dívida de {money(c.debt)}: lances bloqueados.</Notice>}
      <div className="on-seg on-seg-3" role="tablist">
        <button type="button" role="tab" aria-selected={view === 'featured'} className={view === 'featured' ? 'is-on' : ''} onClick={() => setView('featured')}><Flame size={14} /> Leilões</button>
        <button type="button" role="tab" aria-selected={view === 'mine'} className={view === 'mine' ? 'is-on' : ''} onClick={() => setView('mine')}><Gavel size={14} /> Meus{lists.mine.length ? ` ${lists.mine.length}` : ''}</button>
        <button type="button" role="tab" aria-selected={view === 'recent'} className={view === 'recent' ? 'is-on' : ''} onClick={() => setView('recent')}><TrendingUp size={14} /> Fechados</button>
      </div>

      {view !== 'recent' && (
        <>
          {list.length === 0 && (
            <EmptyState compact icon={Gavel} title={view === 'featured' ? 'Próximos jogadores às 08:00' : 'Nenhum leilão em andamento'} />
          )}
          <div className="on-aucs">
            {list.map((l) => <Auction key={l.id} lot={l} now={serverNow} busy={busy} wallet={wallet} coins={coins} onBid={bid} />)}
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
