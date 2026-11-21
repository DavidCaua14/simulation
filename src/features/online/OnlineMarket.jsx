import { useCallback, useEffect, useMemo, useState } from 'react'
import { Banknote, Coins, Crown, DoorClosed, FileText, Flame, Gavel, Hourglass, Lock, Sprout, TrendingUp, Undo2, UserCheck, Users, X, Zap } from 'lucide-react'
import { EmptyState, Notice, Skeleton } from '../../components/ui/feedback'
import OnlineCrest from './components/OnlineCrest'
import { MiniCard, OvrBadge } from './components/PlayerFut'
import PlayerDetails from './components/PlayerDetails'
import { POS_NAME } from '../seasons/utils/managerUtils'
import { bidOnline, cancelOnlineLot, fetchOnlineMarket } from './services/onlineApi'
import { cardTier, money, moneyShort, timeLeft } from './onlineUtils'
import './market.css'

const STEPS = [
  [0, 'Mínimo'],
  [0.1, '+10%'],
  [0.25, '+25%'],
  [0.5, '+50%'],
]
const round100 = (n) => Math.ceil(n / 100) * 100
const KIND_LABEL = (lot) => (lot.featured >= 8 ? (lot.player.legend ? 'Épica' : 'Destaque') : null)
const isProspect = (lot) => !lot.featured && !lot.seller && lot.player.age <= 23 && lot.player.pot - lot.player.ovr >= 6
const metaLine = (p, long = false) => [long ? POS_NAME[p.pos] || p.pos : p.pos, p.legend ? 'Épica' : `${p.age} anos`, p.pot != null ? `POT ${p.pot}` : null].filter(Boolean).join(' · ')

// Carta do mercado: a miniatura em pixel art, com a cor do tipo (base, destaque, épica, Big Time).
function MarketTile({ p, club, size = 64 }) {
  return <MiniCard p={p} club={club} size={size - 4} />
}

function Auction({ lot, now, busy, wallet, coins, closed, onBid, onCancel, onSheet }) {
  const [step, setStep] = useState(0)
  const opensIn = new Date(lot.opens_at).getTime() - now
  const locked = opensIn > 0
  const left = new Date(lot.ends_at).getTime() - now
  const hot = !locked && left < 120000
  const amount = step === 0 ? lot.min_bid : round100(lot.min_bid * (1 + step))
  const need = amount - (lot.leading ? lot.best_bid : 0) - wallet.free
  const coinCost = need > 0 ? Math.ceil(need / coins.bid_rate) : 0
  const coinRoom = coins.unlimited ? coins.wallet : Math.max(0, (coins.cap ?? 0) - (coins.converted ?? 0))
  const canCoins = coinCost > 0 && coinCost <= coins.wallet && coinCost <= coinRoom
  const blocked = coinCost > 0 && !canCoins
  const p = lot.player
  const kind = KIND_LABEL(lot)
  const state = lot.leading ? 'is-leading' : lot.bidding ? 'is-outbid' : ''
  return (
    <article className={`omk-card t-${cardTier(p)} ${kind ? 'is-featured' : ''} ${lot.flash ? 'is-flash' : ''} ${locked ? 'is-locked' : ''} ${hot ? 'is-hot' : ''} ${state}`}>
      <div className="omk-head">
        <button type="button" className="omk-tile-btn" onClick={() => onSheet(lot)} aria-label={`Ver a ficha de ${p.name}`}>
          <MarketTile p={p} club={lot.seller} />
        </button>
        <div className="omk-who">
          <span className="omk-tags">
            {lot.flash && <em className="omk-tag is-flash"><Zap size={10} /> Relâmpago</em>}
            {kind && <em className={`omk-tag ${p.legend ? 'is-legend' : 'is-star'}`}><Crown size={10} /> {kind}</em>}
            {isProspect(lot) && <em className="omk-tag is-prospect"><Sprout size={10} /> Promessa</em>}
            {lot.seller && <em className="omk-tag is-seller"><OnlineCrest club={lot.seller} size={13} /> {lot.seller.short}</em>}
          </span>
          <strong>{p.name}</strong>
          <small>{metaLine(p)}</small>
        </div>
        <span className={`omk-clock ${hot ? 'is-hot' : ''} ${locked ? 'is-locked' : ''}`}>
          {locked ? <Lock size={12} /> : hot ? <Flame size={12} /> : <Hourglass size={12} />}
          {locked ? new Date(lot.opens_at).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' }) : timeLeft(left)}
        </span>
      </div>

      <div className="omk-price">
        <span>
          <small>{lot.best_bid ? 'Maior lance' : 'Lance inicial'}</small>
          <b>{money(lot.best_bid || lot.start_price)}</b>
        </span>
        <span className="omk-price-side">
          {lot.best_club ? (
            <span className={`omk-leader ${lot.leading ? 'is-me' : ''}`}><OnlineCrest club={lot.best_club} size={16} /> {lot.leading ? 'Você lidera' : lot.best_club.short}</span>
          ) : <span className="omk-leader is-none">Sem lances</span>}
          {lot.bidders > 0 && <small><Users size={11} /> {lot.bidders} {lot.bidders === 1 ? 'clube' : 'clubes'}</small>}
        </span>
      </div>

      {locked && <p className="omk-note"><Lock size={12} /> Abre em {timeLeft(opensIn)} · veja a ficha antes</p>}
      {lot.mine && !lot.best_bid && !locked && (
        <button type="button" className="omk-ghost" disabled={busy} onClick={() => onCancel(lot)}><Undo2 size={14} /> Retirar do leilão</button>
      )}
      {!lot.mine && !locked && closed && <p className="omk-note"><DoorClosed size={12} /> Mercado fechado</p>}
      {!lot.mine && !locked && !closed && lot.owned && <p className="omk-note"><UserCheck size={12} /> Você já tem esse jogador no elenco</p>}
      {!lot.mine && !locked && !closed && !lot.owned && lot.locked && <p className="omk-note is-tier"><Lock size={12} /> {lot.locked}</p>}
      {!lot.mine && !locked && !closed && !lot.owned && !lot.locked && (
        <div className="omk-act">
          <div className="omk-steps" role="group" aria-label="Valor do lance">
            {STEPS.map(([v, label]) => <button key={v} type="button" className={step === v ? 'is-on' : ''} onClick={() => setStep(v)}>{label}</button>)}
          </div>
          <div className="omk-btns">
            <button type="button" className="omk-ghost" onClick={() => onSheet(lot)}><FileText size={14} /> Ficha</button>
            <button type="button" className={`gx-btn omk-bid ${coinCost > 0 ? 'is-coins' : ''}`} disabled={busy || blocked || left <= 0} onClick={() => onBid(lot, amount, coinCost)}>
              <Gavel size={16} /> {money(amount)}
              {coinCost > 0 && <em><Coins size={12} /> {coinCost}</em>}
            </button>
          </div>
          {coinCost > coinRoom && <small className="omk-warn">{coins.unlimited ? 'Moedas insuficientes para completar o lance.' : 'Limite de aporte da temporada insuficiente.'}</small>}
        </div>
      )}
    </article>
  )
}

// Dados que importam para decidir a proposta (a condição do dia não entra: ela muda a cada jogo).
function PlayerFacts({ p }) {
  const positions = [p.pos, ...(p.sec || [])].map((x) => POS_NAME[x] || x).join(' · ')
  return (
    <dl className="omk-facts">
      <div><dt>Posições</dt><dd>{positions}</dd></div>
      <div><dt>Idade</dt><dd>{p.legend ? 'Carta Épica' : `${p.age} anos`}</dd></div>
      <div><dt>Nota / potencial</dt><dd>{Math.round(p.ovr)}{p.pot != null ? ` / ${p.pot}` : ''}</dd></div>
      <div><dt>Valor de mercado</dt><dd>{money(p.value)}</dd></div>
      <div><dt>Salário</dt><dd>{money(p.wage)}/dia</dd></div>
      {p.nat && <div><dt>Nacionalidade</dt><dd>{p.nat}</dd></div>}
    </dl>
  )
}

// Cabeçalho comum da ficha e da confirmação: carta, nome, posição/idade e de onde vem.
function SheetHead({ lot, kicker, onClose }) {
  const p = lot.player
  const kind = KIND_LABEL(lot)
  return (
    <header className="omk-sheet-head">
      <MarketTile p={p} club={lot.seller} size={76} />
      <div>
        {kicker && <small className="omk-kicker">{kicker}</small>}
        <strong>{p.name}</strong>
        <span>{metaLine(p, true)}</span>
        <em className="omk-from">{kind || (lot.seller ? <><OnlineCrest club={lot.seller} size={13} /> {lot.seller.name}</> : 'Mercado')}</em>
      </div>
      {onClose && <button type="button" className="omk-x" onClick={onClose} aria-label="Fechar"><X size={18} /></button>}
    </header>
  )
}

// Ficha completa de um jogador do mercado (estilo de jogo, especialidades e atributos), como a do elenco.
function LotSheet({ lot, onClose, onBid }) {
  return (
    <div className="on-modal omk-modal" role="dialog" aria-modal="true" aria-label={`Ficha de ${lot.player.name}`} onClick={onClose}>
      <div className="omk-sheet" onClick={(e) => e.stopPropagation()}>
        <div className="omk-sheet-body">
          <SheetHead lot={lot} onClose={onClose} />
          <PlayerFacts p={lot.player} />
          <PlayerDetails playerId={lot.player.id} market />
        </div>
        {onBid && (
          <footer className="omk-sheet-foot">
            <button type="button" className="gx-btn" onClick={onBid}><Gavel size={15} /> Fazer proposta · {money(lot.min_bid)}</button>
          </footer>
        )}
      </div>
    </div>
  )
}

// Confirmação do lance: o jogador, a proposta contra o valor dele, de onde sai o dinheiro e a ficha (recolhível).
function BidConfirm({ ask, wallet, coins, busy, onCancel, onConfirm }) {
  const { lot, amount, coinCost } = ask
  const p = lot.player
  const extra = amount - (lot.leading ? lot.best_bid : 0)
  const fromCoins = coinCost > 0 ? Math.min(extra, coinCost * coins.bid_rate) : 0
  const fromCash = extra - fromCoins
  const diff = p.value ? Math.round(((amount - p.value) / p.value) * 100) : null
  return (
    <div className="on-modal omk-modal" role="dialog" aria-modal="true" aria-label={`Confirmar lance em ${p.name}`}>
      <div className="omk-sheet">
        <div className="omk-sheet-body">
          <SheetHead lot={lot} kicker={<><Gavel size={12} /> Confirmar proposta</>} />
          <div className="omk-offer">
            <span><small>Sua proposta</small><b>{money(amount)}</b></span>
            <span><small>Valor de mercado</small><b>{money(p.value)}</b>
              {diff != null && <em className={diff > 0 ? 'is-up' : 'is-down'}>{diff > 0 ? `${diff}% acima` : diff < 0 ? `${-diff}% abaixo` : 'no valor'}</em>}
            </span>
          </div>
          <dl className="omk-rows">
            <div><dt>{lot.best_bid ? 'Maior lance agora' : 'Lance inicial'}</dt><dd>{money(lot.best_bid || lot.start_price)}</dd></div>
            <div><dt>Salário</dt><dd>{money(p.wage)} por dia</dd></div>
            <div><dt>Sai do caixa (reservado)</dt><dd>{money(fromCash)}</dd></div>
            {coinCost > 0 && <div><dt>Moedas usadas</dt><dd><Coins size={12} /> {coinCost}</dd></div>}
            <div><dt>Caixa livre depois</dt><dd>{money(wallet.free - fromCash)}</dd></div>
          </dl>
          <p className="omk-hint">O valor fica reservado até o fim do leilão. Se outro clube cobrir, ele volta para o caixa{coinCost > 0 ? ' e as moedas voltam para a sua conta' : ''}.</p>
          <details className="omk-more">
            <summary>Ficha do jogador</summary>
            <PlayerFacts p={p} />
            <PlayerDetails playerId={p.id} market />
          </details>
        </div>
        <footer className="omk-sheet-foot is-two">
          <button type="button" className="gx-btn-ghost" onClick={onCancel}>Cancelar</button>
          <button type="button" className="gx-btn" disabled={busy} onClick={onConfirm}><Gavel size={15} /> Confirmar</button>
        </footer>
      </div>
    </div>
  )
}

// MERCADO: leilões iguais para todos, só no horário de funcionamento (data.hours). Sem lance, saem na virada da hora;
// cada lance põe o relógio em 5 minutos. Toda hora entram cartas base, destaques e épicas; técnicos também leiloam seus jogadores.
// A série do clube limita o tipo: C e D só base, B até destaque, A tudo (lot.locked traz o motivo).
const KINDS = [
  ['all', 'Todos', () => true],
  ['legend', 'Épicas', (l) => l.featured >= 8 && l.player.legend],
  ['star', 'Destaques', (l) => l.featured >= 8 && !l.player.legend],
  ['flash', 'Relâmpago', (l) => l.flash],
  ['base', 'Base', (l) => l.featured < 8 && !l.flash],
]
export default function OnlineMarket({ notify, onChanged }) {
  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [offset, setOffset] = useState(0)
  const [now, setNow] = useState(() => Date.now())
  const [view, setView] = useState('featured')
  const [kind, setKind] = useState('all')
  const [ask, setAsk] = useState(null) // lance esperando confirmação: { lot, amount, coinCost }
  const [sheetLot, setSheetLot] = useState(null) // ficha completa aberta (toque na carta)

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
    featured: open.filter((l) => !l.mine).sort((a, b) => Number(Boolean(b.flash)) - Number(Boolean(a.flash))),
    mine: open.filter((l) => l.mine || l.bidding),
  }
  const hours = data.hours
  const closed = hours ? !hours.open : false
  const hh = (n) => `${String(n % 24).padStart(2, '0')}:00`
  const cancel = (lot) => run(cancelOnlineLot(lot.id), `${lot.player.name} voltou ao elenco`)
  // o lance só sai depois da confirmação (janela com o jogador e os valores)
  const bid = (lot, amount, coinCost) => setAsk({ lot, amount, coinCost })
  const confirmBid = () => {
    const { lot, amount, coinCost } = ask
    setAsk(null)
    run(bidOnline(lot.id, amount, coinCost > 0), `Lance de ${money(amount)} em ${lot.player.name}`)
  }
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
          {hours.off ? <><DoorClosed size={14} /> Mercado de transferências fechado <b>Sem data de reabertura</b></> : closed ? <><DoorClosed size={14} /> Mercado fechado <b>Abre às {hours.open_label || hh(hours.open_hour)}</b></> : <><Gavel size={14} /> Mercado aberto <b>Fecha às {hours.close_label || hh(hours.close_hour)}</b></>}
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
            <EmptyState compact icon={Gavel} title={hours?.off ? 'Mercado de transferências fechado' : view !== 'featured' ? 'Nenhum leilão em andamento' : lists.featured.length ? 'Nenhum leilão desse tipo agora' : `Próximos jogadores às ${hours?.open_label || '08:00'}`} />
          )}
          <div className="omk-list">
            {list.map((l) => <Auction key={l.id} lot={l} now={serverNow} busy={busy} wallet={wallet} coins={coins} closed={closed} onBid={bid} onCancel={cancel} onSheet={setSheetLot} />)}
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
      {sheetLot && (
        <LotSheet lot={sheetLot} onClose={() => setSheetLot(null)}
          onBid={!sheetLot.mine && !closed && new Date(sheetLot.opens_at).getTime() <= serverNow ? () => {
            const l = sheetLot
            const need = l.min_bid - (l.leading ? l.best_bid : 0) - wallet.free
            setSheetLot(null)
            bid(l, l.min_bid, need > 0 ? Math.ceil(need / coins.bid_rate) : 0)
          } : null} />
      )}
      {ask && <BidConfirm ask={ask} wallet={wallet} coins={coins} busy={busy} onCancel={() => setAsk(null)} onConfirm={confirmBid} />}
    </section>
  )
}
