import { useCallback, useEffect, useMemo, useState } from 'react'
import { ArrowLeft, CalendarDays, Clock, Home, Landmark, ListOrdered, Pencil, Radio, Shirt, Swords, Trophy, Users, Gavel } from 'lucide-react'
import { EmptyState, Notice, Skeleton } from '../../components/ui/feedback'
import OnlineCrest from './components/OnlineCrest'
import OnlineDraft from './OnlineDraft'
import OnlineClub from './OnlineClub'
import OnlineCup from './OnlineCup'
import OnlineMarket from './OnlineMarket'
import OnlineMatchLive from './OnlineMatchLive'
import OnlineSquad from './OnlineSquad'
import { fetchOnlineCalendar, fetchOnlineStandings, fetchOnlineStatus, joinOnlineQueue, renameOnlineClub } from './services/onlineApi'
import { dayKey, kickoffDay, kickoffTime, moneyShort, untilKickoff } from './onlineUtils'
import './online.css'

// MODO ONLINE: liga compartilhada com um jogo por dia em horário real.
const TABS = [
  { id: 'home', label: 'Início', Icon: Home },
  { id: 'squad', label: 'Elenco', Icon: Shirt },
  { id: 'market', label: 'Mercado', Icon: Gavel },
  { id: 'club', label: 'Clube', Icon: Landmark },
  { id: 'league', label: 'Liga', Icon: Trophy },
]

const ordinal = (n) => (n ? `${n}º` : '–')

function HomeTab({ status, now, onRenamed, onOpenMatch }) {
  const { club, next, season, position, last } = status
  const [editing, setEditing] = useState(false)
  const [name, setName] = useState(club.name)
  const [error, setError] = useState('')
  const save = (e) => {
    e.preventDefault()
    setError('')
    renameOnlineClub(name).then((s) => {
      setEditing(false)
      onRenamed(s)
    }).catch((err) => setError(err.message))
  }
  const live = next && new Date(next.kickoff).getTime() <= now
  const homeClub = next ? (next.at_home ? club : next.opp) : null
  const awayClub = next ? (next.at_home ? next.opp : club) : null
  return (
    <section className="on-home">
      <div className="on-hero" style={{ '--a': club.colors?.a, '--b': club.colors?.b }}>
        <div className="on-hero-crest"><OnlineCrest club={club} size={84} /></div>
        <div className="on-hero-info">
          {editing ? (
            <form className="on-rename" onSubmit={save}>
              <input value={name} onChange={(e) => setName(e.target.value)} maxLength={24} aria-label="Nome do clube" autoFocus />
              <button type="submit" className="gx-btn">Salvar</button>
              <button type="button" className="gx-btn-ghost" onClick={() => { setEditing(false); setName(club.name) }}>Cancelar</button>
            </form>
          ) : (
            <div className="on-club-name">
              <strong>{club.name}</strong>
              <button type="button" className="on-icon-btn" onClick={() => setEditing(true)} aria-label="Mudar o nome do clube"><Pencil size={14} /></button>
            </div>
          )}
          <div className="on-hero-stats">
            <span><small>Posição</small><b>{ordinal(position)}</b></span>
            <span><small>Caixa</small><b>{moneyShort(club.cash)}</b></span>
            <span><small>Em lances</small><b>{moneyShort(club.reserved)}</b></span>
          </div>
        </div>
      </div>
      {error && <Notice kind="error" onClose={() => setError('')}>{error}</Notice>}
      {season?.kind === 'sandbox' && <Notice kind="info">Temporada de teste: os jogos acontecem em sequência rápida.</Notice>}

      {status.rest_today && (
        <div className="on-rest gx-panel"><CalendarDays size={18} /> <span><b>Sem jogo hoje.</b> Dia de copa e seu clube não joga. Bom dia para treinar e ir ao mercado.</span></div>
      )}
      {next ? (
        <div className={`on-match-card ${live ? 'is-live' : ''}`}>
          <div className="on-match-head">
            <span className="gx-tag">{next.comp === 'C' ? 'Copa Online' : `Liga Online · rodada ${next.round}`}</span>
            {live ? <span className="on-live-dot"><Radio size={12} /> AO VIVO</span> : <span className="on-when"><Clock size={13} /> {kickoffDay(next.kickoff)} · {kickoffTime(next.kickoff)}</span>}
          </div>
          <div className="on-match-teams">
            <span className={next.at_home ? 'is-mine' : ''}><OnlineCrest club={homeClub} size={64} /><b>{homeClub.name}</b></span>
            <span className="on-match-vs">{live ? <Radio size={22} /> : 'VS'}</span>
            <span className={!next.at_home ? 'is-mine' : ''}><OnlineCrest club={awayClub} size={64} /><b>{awayClub.name}</b></span>
          </div>
          {live ? (
            <button type="button" className="gx-btn on-match-cta is-live" onClick={() => onOpenMatch(next.id)}>
              <Radio size={18} /> Entrar na partida
            </button>
          ) : (
            <>
              <div className="on-countdown"><small>Começa</small><b>{untilKickoff(next.kickoff, now)}</b></div>
              <button type="button" className="gx-btn-ghost on-match-cta" onClick={() => onOpenMatch(next.id)}>Ir para o vestiário</button>
            </>
          )}
          <small className="on-match-note">{next.opp.bot ? 'Adversário comandado pelo jogo.' : 'Adversário comandado por outro técnico.'} A partida dura 12 minutos reais.</small>
        </div>
      ) : (
        <EmptyState compact icon={CalendarDays} title="Sem jogos pela frente" text="A temporada chegou ao fim." />
      )}

      {last && (
        <div className="on-last gx-panel">
          <small>Último jogo</small>
          <span><OnlineCrest club={last.at_home ? club : last.opp} size={26} /> <b>{last.hg} × {last.ag}</b> <OnlineCrest club={last.at_home ? last.opp : club} size={26} /></span>
          <button type="button" className="gx-btn-ghost" onClick={() => onOpenMatch(last.id)}>Rever</button>
        </div>
      )}
    </section>
  )
}

function FixturesView({ now, onOpenMatch }) {
  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  const [mine, setMine] = useState(true)
  useEffect(() => {
    fetchOnlineCalendar().then(setData).catch((e) => setError(e.message))
  }, [])
  const days = useMemo(() => {
    if (!data) return []
    const clubs = new Map(data.clubs.map((c) => [c.id, c]))
    const groups = new Map()
    for (const f of data.fixtures) {
      if (mine && f.home !== data.my_club && f.away !== data.my_club) continue
      const k = dayKey(f.kickoff)
      if (!groups.has(k)) groups.set(k, { key: k, label: kickoffDay(f.kickoff), comp: f.comp, round: f.round, list: [] })
      groups.get(k).list.push({ ...f, h: clubs.get(f.home), a: clubs.get(f.away) })
    }
    return [...groups.values()]
  }, [data, mine])

  if (!data) return error ? <Notice kind="error">{error}</Notice> : <Skeleton rows={8} />
  return (
    <section className="on-fixtures">
      <div className="on-seg" role="group" aria-label="Filtro de jogos">
        <button type="button" className={mine ? 'is-on' : ''} onClick={() => setMine(true)}>Meus jogos</button>
        <button type="button" className={!mine ? 'is-on' : ''} onClick={() => setMine(false)}>Todos</button>
      </div>
      {days.map((d) => (
        <div key={d.key} className="on-day">
          <h3 className="gx-subtitle">{d.label} · {d.comp === 'C' ? 'Copa' : `Rodada ${d.round}`}</h3>
          <ul className="on-list">
            {d.list.map((f) => {
              const live = f.status !== 'done' && new Date(f.kickoff).getTime() <= now
              const watch = live || f.status === 'done'
              return (
                <li key={f.id}>
                  <button type="button" disabled={!watch} onClick={() => onOpenMatch(f.id)}
                    className={`on-fix ${f.home === data.my_club || f.away === data.my_club ? 'is-mine' : ''} ${live ? 'is-live' : ''}`}>
                    <span className="on-fix-team is-home"><b>{f.h?.name}</b><OnlineCrest club={f.h} size={26} /></span>
                    <span className="on-fix-mid">
                      {f.status === 'done' ? <b>{f.hg} x {f.ag}</b> : live ? <em><Radio size={11} /> ao vivo</em> : <time dateTime={f.kickoff}>{kickoffTime(f.kickoff)}</time>}
                    </span>
                    <span className="on-fix-team"><OnlineCrest club={f.a} size={26} /><b>{f.a?.name}</b></span>
                  </button>
                </li>
              )
            })}
          </ul>
        </div>
      ))}
    </section>
  )
}

function TableView() {
  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  useEffect(() => {
    fetchOnlineStandings().then(setData).catch((e) => setError(e.message))
  }, [])
  if (!data) return error ? <Notice kind="error">{error}</Notice> : <Skeleton rows={8} />
  return (
    <section className="on-table-wrap">
      <table className="on-table">
        <thead>
          <tr><th scope="col">#</th><th scope="col">Clube</th><th scope="col" title="Pontos">P</th><th scope="col" title="Jogos">J</th><th scope="col" title="Vitórias">V</th><th scope="col" title="Empates">E</th><th scope="col" title="Derrotas">D</th><th scope="col" title="Saldo de gols">SG</th></tr>
        </thead>
        <tbody>
          {data.rows.map((r, i) => (
            <tr key={r.club_id} className={`${r.club_id === data.my_club ? 'is-mine' : ''} ${i < 4 ? 'z-top' : i >= data.rows.length - 3 ? 'z-low' : ''}`}>
              <td><span className="on-rank">{i + 1}</span></td>
              <th scope="row"><OnlineCrest club={r} size={22} /><span>{r.name}</span>{!r.bot && <Users size={12} aria-label="Técnico humano" />}</th>
              <td><b>{r.pts}</b></td><td>{r.p}</td><td>{r.w}</td><td>{r.d}</td><td>{r.l}</td><td>{r.gf - r.ga}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <p className="on-hint"><Users size={12} aria-hidden="true" /> clube comandado por um técnico humano. Desempate: pontos, saldo, gols marcados.</p>
    </section>
  )
}

function LeagueTab({ now, onOpenMatch }) {
  const [view, setView] = useState('table')
  return (
    <section className="on-league">
      <div className="on-seg on-seg-3" role="tablist" aria-label="Liga">
        <button type="button" role="tab" aria-selected={view === 'table'} className={view === 'table' ? 'is-on' : ''} onClick={() => setView('table')}><ListOrdered size={15} /> Tabela</button>
        <button type="button" role="tab" aria-selected={view === 'fixtures'} className={view === 'fixtures' ? 'is-on' : ''} onClick={() => setView('fixtures')}><CalendarDays size={15} /> Jogos</button>
        <button type="button" role="tab" aria-selected={view === 'cup'} className={view === 'cup' ? 'is-on' : ''} onClick={() => setView('cup')}><Trophy size={15} /> Copa</button>
      </div>
      {view === 'table' && <TableView />}
      {view === 'fixtures' && <FixturesView now={now} onOpenMatch={onOpenMatch} />}
      {view === 'cup' && <OnlineCup now={now} onOpenMatch={onOpenMatch} />}
    </section>
  )
}

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
  const [tab, setTab] = useState('home')
  const [match, setMatch] = useState(null) // id da partida aberta (ou 'current')
  const [offset, setOffset] = useState(0) // diferença entre o relógio do servidor e o do aparelho
  const [tick, setTick] = useState(() => Date.now())

  const apply = useCallback((s) => {
    if (s?.server_now) setOffset(new Date(s.server_now).getTime() - Date.now())
    setStatus(s)
  }, [])
  const load = useCallback(() => {
    fetchOnlineStatus().then(apply).catch((e) => setError(e.message))
  }, [apply])
  useEffect(() => {
    load()
  }, [load])
  // Só o relógio da tela anda sozinho (contagem até o pontapé); nada vai ao banco.
  useEffect(() => {
    const id = setInterval(() => setTick(Date.now()), 15000)
    return () => clearInterval(id)
  }, [])
  const now = tick + offset

  const join = () => joinOnlineQueue().then(apply).catch((e) => setError(e.message))
  const playing = status?.access === 'playing'
  const drafting = playing && status.club.draft_step < 3
  const openMatch = (id) => setMatch(id)
  const tabs = TABS

  let body
  if (!status) body = error ? null : <Skeleton rows={5} />
  else if (drafting) body = <OnlineDraft onDone={load} />
  else if (playing) {
    body = (
      <>
        {tab === 'home' && <HomeTab status={status} now={now} onRenamed={apply} onOpenMatch={openMatch} />}
        {tab === 'squad' && <OnlineSquad onOpenMatch={openMatch} notify={notify} seasonId={status.season?.id} />}
        {tab === 'league' && <LeagueTab now={now} onOpenMatch={openMatch} />}
        {tab === 'market' && <OnlineMarket notify={notify} onChanged={load} />}
        {tab === 'club' && <OnlineClub notify={notify} onChanged={load} />}
      </>
    )
  } else if (status.access === 'queued') {
    body = <EmptyState icon={Clock} title="Você está na fila" text="Sua vaga está garantida. Você entra na liga quando a próxima temporada começar, no lugar de um clube comandado pelo jogo." />
  } else if (status.access === 'unavailable') {
    body = <EmptyState icon={Swords} title="Modo online em preparação" text="A liga compartilhada ainda não foi aberta. Volte em breve." />
  } else {
    body = (
      <EmptyState
        icon={Swords}
        title={status.season ? 'Temporada em andamento' : 'A primeira temporada vai começar'}
        text="Novos técnicos entram no início de cada temporada. Entre na fila para garantir seu clube na próxima."
        action="Entrar na fila"
        onAction={join}
      />
    )
  }

  return (
    <div className="on">
      <header className="on-top">
        <button type="button" className="on-back" onClick={onBack} aria-label="Voltar"><ArrowLeft size={20} /></button>
        <h1>Modo Online</h1>
        {playing && !drafting && status.next && new Date(status.next.kickoff).getTime() <= now && (
          <button type="button" className="on-top-live" onClick={() => openMatch(status.next.id)}><Radio size={13} /> AO VIVO</button>
        )}
      </header>
      {error && <Notice kind="error" onClose={() => setError('')}>{error}</Notice>}
      <div className="on-body">{body}</div>
      {playing && !drafting && (
        <nav className="on-tabs" aria-label="Seções do modo online" style={{ '--n': tabs.length }}>
          {tabs.map(({ id, label, Icon }) => (
            <button key={id} type="button" className={tab === id ? 'is-on' : ''} aria-current={tab === id ? 'page' : undefined} onClick={() => setTab(id)}>
              <Icon size={19} /> <span>{label}</span>
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
  )
}
