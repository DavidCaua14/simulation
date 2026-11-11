import { useEffect, useMemo, useState } from 'react'
import { CalendarDays, ChevronLeft, ChevronRight, ListOrdered, Radio, Trophy, User } from 'lucide-react'
import { Notice, Skeleton } from '../../components/ui/feedback'
import OnlineCrest from './components/OnlineCrest'
import OnlineCup from './OnlineCup'
import { fetchOnlineCalendar, fetchOnlineStandings } from './services/onlineApi'
import { kickoffDay, kickoffTime } from './onlineUtils'

const CUP_STAGE = { r1: 'Copa · 1ª fase', qf: 'Copa · Quartas', sf: 'Copa · Semifinal', final: 'Copa · Final' }

function TableView() {
  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  useEffect(() => {
    fetchOnlineStandings().then(setData).catch((e) => setError(e.message))
  }, [])
  if (!data) return error ? <Notice kind="error">{error}</Notice> : <Skeleton rows={8} />
  return (
    <div className="on-table-wrap">
      <table className="on-table">
        <thead>
          <tr><th scope="col">#</th><th scope="col" className="is-club">Clube</th><th scope="col">J</th><th scope="col">V</th><th scope="col">E</th><th scope="col">D</th><th scope="col">SG</th><th scope="col">PTS</th></tr>
        </thead>
        <tbody>
          {data.rows.map((r, i) => (
            <tr key={r.club_id} className={`${r.club_id === data.my_club ? 'is-mine' : ''} ${i === 0 ? 'z-lead' : i < 4 ? 'z-top' : ''}`}>
              <td><span className="on-rank">{i + 1}</span></td>
              <th scope="row"><OnlineCrest club={r} size={22} /><span>{r.name}</span>{!r.bot && <User size={11} aria-label="Técnico" />}</th>
              <td>{r.p}</td><td>{r.w}</td><td>{r.d}</td><td>{r.l}</td><td>{r.gf - r.ga > 0 ? `+${r.gf - r.ga}` : r.gf - r.ga}</td><td><b>{r.pts}</b></td>
            </tr>
          ))}
        </tbody>
      </table>
      <p className="on-legend"><i className="z-top" /> Vaga direta nas quartas da copa</p>
    </div>
  )
}

function FixtureRow({ f, mine, now, onOpenMatch }) {
  const live = f.status !== 'done' && new Date(f.kickoff).getTime() <= now
  const done = f.status === 'done'
  return (
    <button type="button" disabled={!live && !done} onClick={() => onOpenMatch(f.id)} className={`on-fix ${mine ? 'is-mine' : ''} ${live ? 'is-live' : ''} ${done ? 'is-done' : ''}`}>
      <span className="on-fix-team is-home"><b>{f.h?.name}</b><OnlineCrest club={f.h} size={24} /></span>
      <span className="on-fix-mid">
        {done ? <b>{f.hg}<i>-</i>{f.ag}</b> : live ? <em><Radio size={11} /> ao vivo</em> : <time dateTime={f.kickoff}>{kickoffTime(f.kickoff)}</time>}
      </span>
      <span className="on-fix-team"><OnlineCrest club={f.a} size={24} /><b>{f.a?.name}</b></span>
    </button>
  )
}

function FixturesView({ now, onOpenMatch }) {
  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  const [mine, setMine] = useState(false)
  const [idx, setIdx] = useState(null)
  useEffect(() => {
    fetchOnlineCalendar().then(setData).catch((e) => setError(e.message))
  }, [])
  const { days, mineList } = useMemo(() => {
    if (!data) return { days: [], mineList: [] }
    const clubs = new Map(data.clubs.map((c) => [c.id, c]))
    const groups = new Map()
    const all = data.fixtures.map((f) => ({ ...f, h: clubs.get(f.home), a: clubs.get(f.away) }))
    for (const f of all) {
      const k = `${f.comp}${f.round}`
      if (!groups.has(k)) groups.set(k, { key: k, label: f.comp === 'C' ? CUP_STAGE[f.stage] || 'Copa' : `Rodada ${f.round}`, day: kickoffDay(f.kickoff), first: f.kickoff, list: [] })
      groups.get(k).list.push(f)
    }
    return { days: [...groups.values()].sort((a, b) => a.first.localeCompare(b.first)), mineList: all.filter((f) => f.home === data.my_club || f.away === data.my_club) }
  }, [data])

  if (!data) return error ? <Notice kind="error">{error}</Notice> : <Skeleton rows={8} />
  const current = days.findIndex((d) => d.list.some((f) => f.status !== 'done'))
  const at = Math.min(days.length - 1, idx ?? (current === -1 ? days.length - 1 : current))
  const day = days[at]
  const isMine = (f) => f.home === data.my_club || f.away === data.my_club
  return (
    <div className="on-fixtures">
      <div className="on-seg" role="group" aria-label="Jogos">
        <button type="button" className={!mine ? 'is-on' : ''} onClick={() => setMine(false)}>Rodada</button>
        <button type="button" className={mine ? 'is-on' : ''} onClick={() => setMine(true)}>Meus jogos</button>
      </div>
      {!mine && day && (
        <>
          <div className="on-round-nav">
            <button type="button" disabled={at <= 0} onClick={() => setIdx(at - 1)} aria-label="Anterior"><ChevronLeft size={18} /></button>
            <span><b>{day.label}</b><small>{day.day}</small></span>
            <button type="button" disabled={at >= days.length - 1} onClick={() => setIdx(at + 1)} aria-label="Próxima"><ChevronRight size={18} /></button>
          </div>
          <div className="on-fix-list">
            {day.list.map((f) => <FixtureRow key={f.id} f={f} mine={isMine(f)} now={now} onOpenMatch={onOpenMatch} />)}
          </div>
        </>
      )}
      {mine && (
        <div className="on-fix-list">
          {mineList.map((f) => {
            const home = f.home === data.my_club
            const done = f.status === 'done'
            const res = !done ? null : f.hg === f.ag ? 'D' : (f.hg > f.ag) === home ? 'W' : 'L'
            const live = !done && new Date(f.kickoff).getTime() <= now
            return (
              <button key={f.id} type="button" className={`on-myfix ${live ? 'is-live' : ''}`} disabled={!done && !live} onClick={() => onOpenMatch(f.id)}>
                <span className="on-myfix-when"><b>{f.comp === 'C' ? 'Copa' : `R${f.round}`}</b><small>{kickoffDay(f.kickoff)}</small></span>
                <OnlineCrest club={home ? f.a : f.h} size={26} />
                <span className="on-myfix-opp"><strong>{(home ? f.a : f.h)?.name}</strong><small>{home ? 'Casa' : 'Fora'}</small></span>
                {done ? <span className={`on-myfix-res is-${res}`}>{f.hg}-{f.ag}</span> : live ? <em><Radio size={11} /> ao vivo</em> : <time>{kickoffTime(f.kickoff)}</time>}
              </button>
            )
          })}
        </div>
      )}
    </div>
  )
}

export default function OnlineLeague({ now, onOpenMatch }) {
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
