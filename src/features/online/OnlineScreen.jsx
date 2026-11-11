import { useCallback, useEffect, useState } from 'react'
import { ArrowLeft, Banknote, Clock, Coins, Gavel, Home, Landmark, LogOut, Radio, Shirt, Swords, Trophy } from 'lucide-react'
import AppShell from '../../components/layout/AppShell'
import { EmptyState, Notice, Skeleton } from '../../components/ui/feedback'
import OnlineCrest from './components/OnlineCrest'
import OnlineClub from './OnlineClub'
import OnlineDraft from './OnlineDraft'
import OnlineHome from './OnlineHome'
import OnlineLeague from './OnlineLeague'
import OnlineMarket from './OnlineMarket'
import OnlineMatchLive from './OnlineMatchLive'
import OnlineSquad from './OnlineSquad'
import { fetchOnlineStatus, joinOnlineQueue } from './services/onlineApi'
import { moneyShort } from './onlineUtils'
import './online.css'
import './online-v2.css'

// MODO ONLINE: liga compartilhada com um jogo por dia em horário real. Mesma moldura de celular do resto do jogo.
const TABS = [
  { id: 'home', label: 'Início', Icon: Home },
  { id: 'squad', label: 'Elenco', Icon: Shirt },
  { id: 'market', label: 'Mercado', Icon: Gavel },
  { id: 'club', label: 'Clube', Icon: Landmark },
  { id: 'league', label: 'Liga', Icon: Trophy },
]
const TITLES = { squad: 'Elenco', market: 'Mercado', club: 'Clube', league: 'Competições' }

export default function OnlineScreen({ onBack }) {
  const [toast, setToast] = useState(null)
  const notify = useCallback((text, kind = 'info') => setToast({ text, kind, id: Date.now() }), [])
  useEffect(() => {
    if (!toast) return undefined
    const t = setTimeout(() => setToast(null), 3800)
    return () => clearTimeout(t)
  }, [toast])
  const [status, setStatus] = useState(null)
  const [error, setError] = useState('')
  const [nav, setNav] = useState({ tab: 'home', view: null, n: 0 })
  const [match, setMatch] = useState(null) // id da partida aberta
  const [offset, setOffset] = useState(0) // diferença entre o relógio do servidor e o do aparelho
  const [tick, setTick] = useState(() => Date.now())

  const apply = useCallback((s) => {
    if (s?.server_now) setOffset(new Date(s.server_now).getTime() - Date.now())
    setStatus(s)
  }, [])
  const load = useCallback(() => fetchOnlineStatus().then(apply).catch((e) => setError(e.message)), [apply])
  useEffect(() => {
    load()
  }, [load])
  const now = tick + offset

  const playing = status?.access === 'playing'
  const drafting = playing && status.club.draft_step < 3
  const ready = playing && !drafting
  const { tab } = nav
  // Só o relógio da tela anda sozinho (contagens da tela inicial a cada segundo; nas outras, a cada 15 s).
  useEffect(() => {
    const id = setInterval(() => setTick(Date.now()), tab === 'home' ? 1000 : 15000)
    return () => clearInterval(id)
  }, [tab])
  // Na tela inicial o servidor é consultado a cada 30 s: leilões em andamento, resultado de leilão e jogo ao vivo.
  useEffect(() => {
    if (!ready || tab !== 'home' || match != null) return undefined
    const id = setInterval(load, 30000)
    return () => clearInterval(id)
  }, [ready, tab, match, load])

  const go = (id, view = null) => setNav((v) => ({ tab: id, view, n: v.n + 1 }))
  const join = () => joinOnlineQueue().then(apply).catch((e) => setError(e.message))
  const club = playing ? status.club : null
  const liveNow = ready && status.next && new Date(status.next.kickoff).getTime() <= now

  let body
  if (!status) body = error ? null : <Skeleton rows={5} />
  else if (drafting) body = <OnlineDraft onDone={load} />
  else if (playing) {
    body = (
      <>
        {tab === 'home' && <OnlineHome status={status} now={now} go={go} onOpenMatch={setMatch} onExit={onBack} onReload={load} />}
        {tab === 'squad' && <OnlineSquad onOpenMatch={setMatch} notify={notify} seasonId={status.season?.id} />}
        {tab === 'league' && <OnlineLeague now={now} onOpenMatch={setMatch} />}
        {tab === 'market' && <OnlineMarket notify={notify} onChanged={load} />}
        {tab === 'club' && <OnlineClub key={nav.n} initialView={nav.view} status={status} notify={notify} onChanged={load} onStatus={apply} />}
      </>
    )
  } else {
    const gate = status.access === 'queued'
      ? { icon: Clock, title: 'Vaga garantida', text: 'Você entra na próxima temporada.' }
      : status.access === 'unavailable'
        ? { icon: Swords, title: 'Em breve', text: 'A liga online ainda não abriu.' }
        : { icon: Swords, title: 'Liga Online', text: 'Garanta seu clube na próxima temporada.', action: 'Entrar na fila', onAction: join }
    body = (
      <>
        <EmptyState {...gate} />
        <button type="button" className="on-exit" onClick={onBack}><LogOut size={16} /> Sair do modo Online</button>
      </>
    )
  }

  const header = (
    <header className="on-top">
      {ready && tab !== 'home' ? (
        <button type="button" className="on-back" onClick={() => go('home')} aria-label="Voltar ao início do modo online"><ArrowLeft size={20} /></button>
      ) : club ? (
        <span className="on-top-crest"><OnlineCrest club={club} size={30} /></span>
      ) : (
        <button type="button" className="on-back" onClick={onBack} aria-label="Sair do modo online"><ArrowLeft size={20} /></button>
      )}
      <div className="on-top-title">
        <strong>{drafting ? 'Monte seu time' : ready && tab !== 'home' ? TITLES[tab] : 'Liga Online'}</strong>
        {ready && status.season && <small>Temporada {status.season.id} · Dia {status.day?.n ?? 1}</small>}
      </div>
      {liveNow && match == null && (
        <button type="button" className="on-top-live" onClick={() => setMatch(status.next.id)}><Radio size={13} /> AO VIVO</button>
      )}
      {ready && (
        <div className="on-top-chips">
          <span className="on-chip is-cash" title="Caixa livre"><Banknote size={13} /> {moneyShort(club.cash - club.reserved).replace('$ ', '')}</span>
          <span className="on-chip is-coin" title="Moedas"><Coins size={13} /> {status.coins ?? 0}</span>
        </div>
      )}
    </header>
  )

  return (
    <AppShell header={match != null ? <span hidden /> : header}>
      <div className="on">
        <div className="on-scroll" key={`${tab}-${nav.n}`}>
          {error && <Notice kind="error" onClose={() => setError('')}>{error}</Notice>}
          {body}
        </div>
        {ready && (
          <nav className="on-tabs" aria-label="Seções do modo online" style={{ '--n': TABS.length }}>
            {TABS.map(({ id, label, Icon }) => (
              <button key={id} type="button" className={tab === id ? 'is-on' : ''} aria-current={tab === id ? 'page' : undefined} onClick={() => go(id)}>
                <span className="on-tab-icon"><Icon size={19} /></span><small>{label}</small>
              </button>
            ))}
          </nav>
        )}
        {toast && <div key={toast.id} className={`on-toast is-${toast.kind}`} role="status">{toast.text}</div>}
        {match != null && (
          <OnlineMatchLive
            fixtureId={match}
            notify={notify}
            onClose={() => {
              setMatch(null)
              load()
            }}
          />
        )}
      </div>
    </AppShell>
  )
}
