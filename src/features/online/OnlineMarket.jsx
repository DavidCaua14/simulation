import { useCallback, useEffect, useMemo, useState } from 'react'
import { Clock, Gavel, Hourglass, Star, Tag, TrendingUp, X } from 'lucide-react'
import { EmptyState, Notice, Skeleton } from '../../components/ui/feedback'
import OnlineCrest from './components/OnlineCrest'
import { bidOnline, cancelOnlineLot, fetchOnlineMarket } from './services/onlineApi'
import { cardTier, money, moneyShort } from './onlineUtils'
import { POS_NAME } from '../seasons/utils/managerUtils'

const fmtLeft = (ms) => {
  if (ms <= 0) return 'encerrando'
  const s = Math.ceil(ms / 1000)
  if (s >= 3600) return `${Math.floor(s / 3600)} h ${String(Math.floor((s % 3600) / 60)).padStart(2, '0')}`
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`
}

function LotCard({ lot, now, busy, onBid, onCancel }) {
  const open = new Date(lot.opens_at).getTime() <= now
  const left = new Date(lot.ends_at).getTime() - now
  const hot = open && left < 60000
  const p = lot.player
  const [custom, setCustom] = useState('')
  const tier = cardTier(p.ovr, p.star)
  return (
    <article className={`on-lot t-${tier} ${lot.leading ? 'is-leading' : ''} ${hot ? 'is-hot' : ''} ${!open ? 'is-soon' : ''}`}>
      <header className="on-lot-head">
        <span className="on-lot-ovr"><b>{Math.round(p.ovr)}</b><small>{p.pos}</small></span>
        <div className="on-lot-who">
          <strong>{p.star && <Star size={12} />} {p.name}</strong>
          <small>{POS_NAME[p.pos]} · {p.age} anos · potencial {p.pot}</small>
          <small className="on-lot-from">
            {lot.seller ? <><OnlineCrest club={lot.seller} size={14} /> {lot.mine ? 'Seu jogador' : lot.seller.name}</> : 'Mercado livre'}
          </small>
        </div>
        <span className={`on-lot-clock ${hot ? 'is-hot' : ''}`}>
          {open ? <><Hourglass size={13} /> {fmtLeft(left)}</> : <><Clock size={13} /> abre {new Date(lot.opens_at).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}</>}
        </span>
      </header>
      <div className="on-lot-bid">
        <span>
          <small>{lot.best_bid ? 'Maior lance' : 'Lance inicial'}</small>
          <b>{money(lot.best_bid || lot.start_price)}</b>
        </span>
        <span>
          <small>Valor</small>
          <b className="is-dim">{moneyShort(p.value)}</b>
        </span>
        <span className="on-lot-leader">
          {lot.best_club ? (
            <>
              <OnlineCrest club={lot.best_club} size={20} />
              <em>{lot.leading ? 'Você lidera' : lot.best_club.short}</em>
            </>
          ) : (
            <em>sem lances</em>
          )}
        </span>
      </div>
      {open && !lot.mine && (
        <div className="on-lot-actions">
          <button type="button" className="gx-btn" disabled={busy || lot.leading} onClick={() => onBid(lot, lot.min_bid)}>
            <Gavel size={15} /> {lot.leading ? 'Na frente' : `Dar ${moneyShort(lot.min_bid)}`}
          </button>
          <form
            className="on-lot-custom"
            onSubmit={(e) => {
              e.preventDefault()
              const v = Math.round(Number(custom))
              if (v) onBid(lot, v)
            }}
          >
            <input inputMode="numeric" placeholder={String(lot.min_bid)} value={custom} onChange={(e) => setCustom(e.target.value.replace(/\D/g, ''))} aria-label="Valor do lance" />
            <button type="submit" className="gx-btn-ghost" disabled={busy || !custom}><TrendingUp size={15} /></button>
          </form>
        </div>
      )}
      {lot.mine && !lot.best_club && (
        <button type="button" className="gx-btn-ghost on-lot-cancel" disabled={busy} onClick={() => onCancel(lot)}><X size={14} /> Retirar da venda</button>
      )}
    </article>
  )
}

// MERCADO: leilões ao vivo. A tela consulta a cada 5 s só quando um lote está no fim; senão a cada 20 s.
export default function OnlineMarket({ notify, onChanged }) {
  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [offset, setOffset] = useState(0)
  const [now, setNow] = useState(() => Date.now())
  const [view, setView] = useState('open')

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
  const hot = (data?.lots || []).some((l) => {
    const t = new Date(l.ends_at).getTime() - serverNow
    return new Date(l.opens_at).getTime() <= serverNow && t < 60000
  })
  useEffect(() => {
    const id = setInterval(load, hot ? 5000 : 20000)
    return () => clearInterval(id)
  }, [load, hot])

  const run = (job, ok) => {
    setBusy(true)
    job
      .then((d) => {
        apply(d)
        if (ok) notify?.(ok, 'success')
        onChanged?.()
      })
      .catch((e) => notify?.(e.message, 'alert'))
      .finally(() => setBusy(false))
  }
  const lists = useMemo(() => {
    const lots = data?.lots || []
    return {
      open: lots.filter((l) => !l.mine && new Date(l.opens_at).getTime() <= serverNow),
      soon: lots.filter((l) => !l.mine && new Date(l.opens_at).getTime() > serverNow).slice(0, 4),
      mine: lots.filter((l) => l.mine),
      leading: lots.filter((l) => l.leading),
    }
  }, [data, serverNow])

  if (!data) return error ? <Notice kind="error">{error}</Notice> : <Skeleton rows={6} />
  const c = data.club
  return (
    <section className="on-market">
      <div className="on-wallet">
        <span><small>Caixa livre</small><b>{money(c.cash - c.reserved)}</b></span>
        <span><small>Em lances</small><b>{money(c.reserved)}</b></span>
        <span><small>Elenco</small><b>{c.roster}/28</b></span>
      </div>
      {c.debt > 0 && <Notice kind="error">Seu clube deve {money(c.debt)}. Com dívida não dá para dar lances; as próximas receitas pagam a dívida primeiro.</Notice>}
      <div className="on-seg on-seg-3" role="tablist">
        <button type="button" role="tab" aria-selected={view === 'open'} className={view === 'open' ? 'is-on' : ''} onClick={() => setView('open')}><Gavel size={15} /> Leilões</button>
        <button type="button" role="tab" aria-selected={view === 'mine'} className={view === 'mine' ? 'is-on' : ''} onClick={() => setView('mine')}><Tag size={15} /> Meus ({lists.mine.length + lists.leading.length})</button>
        <button type="button" role="tab" aria-selected={view === 'recent'} className={view === 'recent' ? 'is-on' : ''} onClick={() => setView('recent')}><TrendingUp size={15} /> Negócios</button>
      </div>

      {view === 'open' && (
        <>
          {lists.open.length === 0 && <EmptyState compact icon={Gavel} title="Nenhum leilão aberto agora" text="Novos jogadores entram no mercado ao longo do dia." />}
          <div className="on-lots">
            {lists.open.map((l) => <LotCard key={l.id} lot={l} now={serverNow} busy={busy} onBid={(lot, v) => run(bidOnline(lot.id, v), `Lance de ${money(v)} em ${lot.player.name}.`)} />)}
          </div>
          {lists.soon.length > 0 && (
            <>
              <h3 className="gx-subtitle">Em breve</h3>
              <div className="on-lots">{lists.soon.map((l) => <LotCard key={l.id} lot={l} now={serverNow} busy={busy} />)}</div>
            </>
          )}
        </>
      )}
      {view === 'mine' && (
        <>
          <p className="on-hint">Para vender, toque em um jogador no Elenco e escolha “Vender”. Elenco entre 16 e 28 jogadores.</p>
          {lists.mine.length + lists.leading.length === 0 && <EmptyState compact icon={Tag} title="Nada em andamento" text="Seus jogadores à venda e os leilões em que você lidera aparecem aqui." />}
          <div className="on-lots">
            {[...lists.mine, ...lists.leading].map((l) => (
              <LotCard key={l.id} lot={l} now={serverNow} busy={busy} onBid={(lot, v) => run(bidOnline(lot.id, v))} onCancel={(lot) => run(cancelOnlineLot(lot.id), 'Jogador retirado da venda.')} />
            ))}
          </div>
        </>
      )}
      {view === 'recent' && (
        <ul className="on-list">
          {data.recent.length === 0 && <li className="on-hint">Nenhum negócio fechado ainda.</li>}
          {data.recent.map((l) => (
            <li key={l.id} className="on-deal">
              <span className="on-lot-ovr is-small"><b>{Math.round(l.player.ovr)}</b><small>{l.player.pos}</small></span>
              <span className="on-deal-who"><strong>{l.player.name}</strong><small>{l.seller ? `${l.seller.short} → ` : 'Livre → '}{l.best_club?.short}</small></span>
              <b>{money(l.best_bid)}</b>
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}
