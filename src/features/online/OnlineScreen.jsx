import { useCallback, useEffect, useMemo, useState } from 'react'
import { ArrowLeft, CalendarDays, Clock, Home, ListOrdered, Pencil, Shirt, Swords, Users } from 'lucide-react'
import { EmptyState, Notice, Skeleton } from '../../components/ui/feedback'
import OnlineDraft from './OnlineDraft'
import OnlineSquad from './OnlineSquad'
import { fetchOnlineCalendar, fetchOnlineStandings, fetchOnlineStatus, joinOnlineQueue, renameOnlineClub } from './services/onlineApi'
import { dayKey, kickoffDay, kickoffTime, money, untilKickoff } from './onlineUtils'
import './online.css'

// MODO ONLINE: liga compartilhada com um jogo por dia em horário real.
// Fase 1: entrada no modo (fila), escolha dos craques, elenco, calendário e classificação.
const TABS = [
  { id: 'home', label: 'Início', Icon: Home },
  { id: 'squad', label: 'Elenco', Icon: Shirt },
  { id: 'fixtures', label: 'Jogos', Icon: CalendarDays },
  { id: 'table', label: 'Tabela', Icon: ListOrdered },
]

function Crest({ club, size = 34 }) {
  return (
    <span className="on-crest" style={{ '--a': club?.colors?.a || '#334155', '--b': club?.colors?.b || '#fff', '--size': `${size}px` }} aria-hidden="true">
      {club?.short || '?'}
    </span>
  )
}

function HomeTab({ status, now, onRenamed }) {
  const { club, next, season } = status
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
  return (
    <section className="on-home">
      <div className="on-club gx-panel">
        <Crest club={club} size={56} />
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
        <dl className="on-club-money">
          <div><dt>Caixa</dt><dd>{money(club.cash)}</dd></div>
          <div><dt>Em lances</dt><dd>{money(club.reserved)}</dd></div>
        </dl>
      </div>
      {error && <Notice kind="error" onClose={() => setError('')}>{error}</Notice>}
      {season?.kind === 'sandbox' && <Notice kind="info">Temporada de teste: os jogos acontecem em sequência rápida.</Notice>}

      <h3 className="gx-subtitle">Próximo jogo</h3>
      {next ? (
        <div className="on-next gx-panel">
          <span className="gx-tag">{next.comp === 'C' ? 'Copa' : `Liga · rodada ${next.round}`}</span>
          <div className="on-next-teams">
            <span><Crest club={next.at_home ? club : next.opp} /><b>{next.at_home ? club.name : next.opp.name}</b></span>
            <Swords size={18} aria-hidden="true" />
            <span><Crest club={next.at_home ? next.opp : club} /><b>{next.at_home ? next.opp.name : club.name}</b></span>
          </div>
          <p className="on-next-when">
            <Clock size={15} aria-hidden="true" />
            {kickoffDay(next.kickoff)} às {kickoffTime(next.kickoff)} · <b>{untilKickoff(next.kickoff, now)}</b>
          </p>
          <small>{next.at_home ? 'Você joga em casa.' : 'Você joga fora.'} {next.opp.bot ? 'Adversário comandado pelo jogo.' : 'Adversário comandado por outro técnico.'}</small>
        </div>
      ) : (
        <EmptyState compact icon={CalendarDays} title="Sem jogos pela frente" text="A temporada chegou ao fim." />
      )}
    </section>
  )
}

function FixturesTab({ now }) {
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
              return (
                <li key={f.id} className={`on-fix ${f.home === data.my_club || f.away === data.my_club ? 'is-mine' : ''}`}>
                  <span className="on-fix-team is-home"><b>{f.h?.name}</b><Crest club={f.h} size={26} /></span>
                  <span className="on-fix-mid">
                    {f.status === 'done' ? <b>{f.hg} x {f.ag}</b> : live ? <em>ao vivo</em> : <time dateTime={f.kickoff}>{kickoffTime(f.kickoff)}</time>}
                  </span>
                  <span className="on-fix-team"><Crest club={f.a} size={26} /><b>{f.a?.name}</b></span>
                </li>
              )
            })}
          </ul>
        </div>
      ))}
    </section>
  )
}

function TableTab() {
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
            <tr key={r.club_id} className={r.club_id === data.my_club ? 'is-mine' : ''}>
              <td>{i + 1}</td>
              <th scope="row"><Crest club={r} size={22} /><span>{r.name}</span>{!r.bot && <Users size={12} aria-label="Técnico humano" />}</th>
              <td><b>{r.pts}</b></td><td>{r.p}</td><td>{r.w}</td><td>{r.d}</td><td>{r.l}</td><td>{r.gf - r.ga}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <p className="on-hint"><Users size={12} aria-hidden="true" /> clube comandado por um técnico humano.</p>
    </section>
  )
}

export default function OnlineScreen({ onBack }) {
  const [status, setStatus] = useState(null)
  const [error, setError] = useState('')
  const [tab, setTab] = useState('home')
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
    const id = setInterval(() => setTick(Date.now()), 30000)
    return () => clearInterval(id)
  }, [])
  const now = tick + offset

  const join = () => joinOnlineQueue().then(apply).catch((e) => setError(e.message))
  const playing = status?.access === 'playing'
  const drafting = playing && status.club.draft_step < 3

  let body
  if (!status) body = error ? null : <Skeleton rows={5} />
  else if (drafting) body = <OnlineDraft onDone={load} />
  else if (playing) {
    body = (
      <>
        {tab === 'home' && <HomeTab status={status} now={now} onRenamed={apply} />}
        {tab === 'squad' && <OnlineSquad />}
        {tab === 'fixtures' && <FixturesTab now={now} />}
        {tab === 'table' && <TableTab />}
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
      </header>
      {error && <Notice kind="error" onClose={() => setError('')}>{error}</Notice>}
      {playing && !drafting && (
        <nav className="on-tabs" aria-label="Seções do modo online">
          {TABS.map(({ id, label, Icon }) => (
            <button key={id} type="button" className={tab === id ? 'is-on' : ''} aria-current={tab === id ? 'page' : undefined} onClick={() => setTab(id)}>
              <Icon size={16} /> {label}
            </button>
          ))}
        </nav>
      )}
      {body}
    </div>
  )
}
