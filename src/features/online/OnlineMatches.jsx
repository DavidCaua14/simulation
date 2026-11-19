import { useEffect, useMemo, useState } from 'react'
import { CalendarDays, ChevronLeft, ChevronRight, Crown, ListOrdered, Radio, Shield, Trophy, User } from 'lucide-react'
import { Notice, Skeleton } from '../../components/ui/feedback'
import OnlineCrest from './components/OnlineCrest'
import OnlineCup from './OnlineCup'
import { CUP, DIVS, SERIES, STAGE, ZONE_LABEL, compOf, zoneOf, zonesFor } from './competitions'
import { fetchOnlineCalendar, fetchOnlineCup, fetchOnlineRound, fetchOnlineStandings } from './services/onlineApi'
import { kickoffTime, untilKickoff } from './onlineUtils'
import './matches.css'

const WEEK = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S']
const MONTHS = ['Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho', 'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro']
const WEEKDAY = new Intl.DateTimeFormat('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' })
const localKey = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
const isLive = (f, now) => f.status !== 'done' && new Date(f.kickoff).getTime() <= now

// Carrega dados de uma RPC; troca quando `deps` muda (série, rodada).
function useLoad(fn, deps) {
  const key = JSON.stringify(deps)
  const [state, setState] = useState({ key: null, data: null, error: '' })
  useEffect(() => {
    let alive = true
    fn().then((data) => alive && setState({ key, data, error: '' })).catch((e) => alive && setState({ key, data: null, error: e.message }))
    return () => { alive = false }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key])
  return state.key === key ? state : { data: null, error: '' }
}

// Escolha da série (logos)
function DivPicker({ value, mine, onChange }) {
  return (
    <div className="mt-divs" role="tablist" aria-label="Série">
      {DIVS.map((d) => (
        <button key={d} type="button" role="tab" aria-selected={value === d} className={`mt-div ${value === d ? 'is-on' : ''}`} style={{ '--sc': SERIES[d].color, '--sd': SERIES[d].deep }} onClick={() => onChange(d)}>
          <img src={SERIES[d].logo} alt="" width={34} height={34} />
          <span>Série {d}</span>
          {mine === d && <i aria-label="Sua série" />}
        </button>
      ))}
    </div>
  )
}

// Placar ou horário no meio de uma linha de jogo
function Score({ f, now }) {
  if (f.status === 'done') {
    return <b className="mt-score">{f.hg}<i>×</i>{f.ag}{f.pens && <small>({f.pens[0]}-{f.pens[1]} pên.)</small>}</b>
  }
  if (isLive(f, now)) return <em className="mt-live"><Radio size={11} /> {f.live?.minute != null ? `${f.live.minute}'` : 'ao vivo'}{f.live?.score && <b>{f.live.score[0]}×{f.live.score[1]}</b>}</em>
  return <time className="mt-time" dateTime={f.kickoff}>{kickoffTime(f.kickoff)}</time>
}

function MatchRow({ f, now, me, onOpenMatch }) {
  const live = isLive(f, now)
  const done = f.status === 'done'
  const mine = f.home.id === me || f.away.id === me
  const win = done && (f.hg !== f.ag ? (f.hg > f.ag ? 'h' : 'a') : f.pens ? (f.pens[0] > f.pens[1] ? 'h' : 'a') : null)
  return (
    <button type="button" className={`mt-row ${mine ? 'is-mine' : ''} ${live ? 'is-live' : ''}`} disabled={!live && !done} onClick={() => onOpenMatch(f.id)}>
      <span className={`mt-team is-home ${win === 'a' ? 'is-lost' : ''}`}><b>{f.home.name}</b><OnlineCrest club={f.home} size={26} /></span>
      <Score f={f} now={now} />
      <span className={`mt-team ${win === 'h' ? 'is-lost' : ''}`}><OnlineCrest club={f.away} size={26} /><b>{f.away.name}</b></span>
    </button>
  )
}

// ── CALENDÁRIO: mês com os jogos do técnico (dois por dia: manhã e tarde) ──
function CalendarView({ now, onOpenMatch }) {
  const { data, error } = useLoad(fetchOnlineCalendar, [])
  const [month, setMonth] = useState(null)
  const [sel, setSel] = useState(null)
  const byDay = useMemo(() => {
    const m = new Map()
    if (!data) return m
    const clubs = new Map((data.clubs || []).map((c) => [c.id, c]))
    for (const f of data.fixtures) {
      const k = localKey(new Date(f.kickoff))
      const home = f.home === data.my_club
      const g = { ...f, opp: clubs.get(home ? f.away : f.home), home: home, c: compOf(f) }
      if (!m.has(k)) m.set(k, [])
      m.get(k).push(g)
    }
    return m
  }, [data])
  if (!data) return error ? <Notice kind="error">{error}</Notice> : <Skeleton rows={8} />

  const next = data.fixtures.find((f) => f.status !== 'done')
  const anchor = new Date(next?.kickoff || data.fixtures.at(-1)?.kickoff || now)
  const cur = month || { y: anchor.getFullYear(), m: anchor.getMonth() }
  const first = new Date(cur.y, cur.m, 1)
  const days = new Date(cur.y, cur.m + 1, 0).getDate()
  const cells = [...Array(first.getDay()).fill(null), ...Array.from({ length: days }, (_, i) => new Date(cur.y, cur.m, i + 1))]
  while (cells.length % 7) cells.push(null)
  const today = localKey(new Date(now))
  const selKey = sel || (byDay.has(today) ? today : next ? localKey(new Date(next.kickoff)) : today)
  const selList = byDay.get(selKey) || []
  const shift = (d) => {
    const x = new Date(cur.y, cur.m + d, 1)
    setMonth({ y: x.getFullYear(), m: x.getMonth() })
  }
  const total = data.fixtures.length
  const played = data.fixtures.filter((f) => f.status === 'done').length

  return (
    <div className="mt-cal">
      <div className="mt-cal-head">
        <button type="button" onClick={() => shift(-1)} aria-label="Mês anterior"><ChevronLeft size={18} /></button>
        <span><b>{MONTHS[cur.m]}</b><small>{cur.y} · {played} de {total} jogos</small></span>
        <button type="button" onClick={() => shift(1)} aria-label="Próximo mês"><ChevronRight size={18} /></button>
      </div>
      <div className="mt-grid" role="grid" aria-label={`Calendário de ${MONTHS[cur.m]}`}>
        {WEEK.map((w, i) => <span key={i} className="mt-wd" role="columnheader">{w}</span>)}
        {cells.map((d, i) => {
          if (!d) return <span key={i} className="mt-day is-empty" />
          const k = localKey(d)
          const list = byDay.get(k) || []
          const past = k < today
          return (
            <button key={i} type="button" role="gridcell" aria-selected={k === selKey}
              className={`mt-day ${list.length ? 'has-games' : ''} ${k === today ? 'is-today' : ''} ${k === selKey ? 'is-sel' : ''} ${past ? 'is-past' : ''}`}
              onClick={() => setSel(k)}>
              <span className="mt-dn">{d.getDate()}</span>
              {list.map((f) => {
                const res = f.status === 'done' ? (f.hg === f.ag && !f.pens ? 'D' : ((f.hg > f.ag || (f.hg === f.ag && f.pens?.[0] > f.pens?.[1])) === f.home ? 'W' : 'L')) : null
                return (
                  <span key={f.id} className={`mt-chip ${f.home ? 'is-h' : 'is-a'} ${f.comp === 'C' ? 'is-cup' : ''} ${res ? `r-${res}` : ''} ${isLive(f, now) ? 'is-live' : ''}`} style={{ '--cc': f.c.color }}>
                    <OnlineCrest club={f.opp} size={13} />
                    <small>{res ? `${f.home ? f.hg : f.ag}-${f.home ? f.ag : f.hg}` : kickoffTime(f.kickoff)}</small>
                  </span>
                )
              })}
            </button>
          )
        })}
      </div>
      <div className="mt-cal-legend">
        <span><i className="is-h" /> Casa</span><span><i className="is-a" /> Fora</span><span><i className="is-cup" /> Copa</span>
      </div>

      <section className="mt-dayview" aria-live="polite">
        <h3>{WEEKDAY.format(new Date(`${selKey}T12:00:00`))}</h3>
        {selList.length === 0 && <p className="mt-rest">Dia de descanso. Bom para treinar e recuperar o elenco.</p>}
        {selList.map((f) => {
          const live = isLive(f, now)
          const done = f.status === 'done'
          return (
            <button key={f.id} type="button" className={`mt-ticket ${live ? 'is-live' : ''}`} style={{ '--cc': f.c.color, '--cd': f.c.deep }} disabled={!live && !done} onClick={() => onOpenMatch(f.id)}>
              <span className="mt-ticket-comp"><img src={f.c.logo} alt="" width={26} height={26} /><b>{f.c.name}</b><small>{f.c.detail}</small></span>
              <span className="mt-ticket-body">
                <span className="mt-ticket-time">
                  <b>{kickoffTime(f.kickoff)}</b>
                  <small>{new Date(f.kickoff).getHours() < 12 ? 'Manhã' : 'Tarde'}</small>
                </span>
                <OnlineCrest club={f.opp} size={36} />
                <span className="mt-ticket-opp"><strong>{f.opp?.name}</strong><small>{f.home ? 'Em casa' : 'Fora de casa'}</small></span>
                {done ? <b className="mt-ticket-res">{f.home ? f.hg : f.ag}<i>×</i>{f.home ? f.ag : f.hg}</b>
                  : live ? <em className="mt-live"><Radio size={11} /> ao vivo</em>
                    : <small className="mt-ticket-left">{untilKickoff(f.kickoff, now)}</small>}
              </span>
            </button>
          )
        })}
      </section>
    </div>
  )
}

// ── RODADA: todos os jogos de uma rodada da série ──
function RoundView({ now, me, myDiv, onOpenMatch }) {
  const [div, setDiv] = useState(myDiv || 'D')
  const [round, setRound] = useState(null)
  const { data, error } = useLoad(() => fetchOnlineRound(div, round), [div, round])
  const pick = (d) => { setDiv(d); setRound(null) }
  const groups = useMemo(() => {
    const m = new Map()
    for (const f of data?.fixtures || []) {
      const k = f.grp ? `Grupo ${f.grp}` : f.stage && f.stage !== 'quad' ? STAGE[f.stage] : ''
      if (!m.has(k)) m.set(k, [])
      m.get(k).push(f)
    }
    return [...m.entries()]
  }, [data])
  const r = data?.round || round || 1
  const first = data?.fixtures?.[0]
  return (
    <div className="mt-round">
      <DivPicker value={div} mine={myDiv} onChange={pick} />
      <div className="mt-cal-head">
        <button type="button" disabled={r <= 1} onClick={() => setRound(r - 1)} aria-label="Rodada anterior"><ChevronLeft size={18} /></button>
        <span>
          <b>{first?.stage && first.stage !== 'quad' ? STAGE[first.stage] + (first.leg ? ` · ${first.leg === 1 ? 'ida' : 'volta'}` : '') : `Rodada ${r}`}</b>
          <small>{first ? new Intl.DateTimeFormat('pt-BR', { weekday: 'short', day: '2-digit', month: '2-digit' }).format(new Date(first.kickoff)) + ` · ${kickoffTime(first.kickoff)}` : SERIES[div].name}</small>
        </span>
        <button type="button" disabled={!data || r >= (data.last_round || 1)} onClick={() => setRound(r + 1)} aria-label="Próxima rodada"><ChevronRight size={18} /></button>
      </div>
      {!data && (error ? <Notice kind="error">{error}</Notice> : <Skeleton rows={8} />)}
      {data && data.fixtures.length === 0 && <p className="mt-rest">Essa fase ainda não foi definida.</p>}
      {data && groups.map(([label, list]) => (
        <div key={label || 'all'} className="mt-block">
          {label && <h4 className="mt-sub">{label}</h4>}
          <div className="mt-rows">{list.map((f) => <MatchRow key={f.id} f={f} now={now} me={me} onOpenMatch={onOpenMatch} />)}</div>
        </div>
      ))}
    </div>
  )
}

// ── TABELA da série, com zonas de acesso e rebaixamento e o mata-mata ──
function Form({ list }) {
  return <span className="mt-form">{(list || []).map((r, i) => <i key={i} className={`r-${r}`} />)}</span>
}

function TieCard({ t, me }) {
  const [a, b] = t.clubs || []
  if (!a || !b) return null
  const agg = (id) => t.legs.reduce((s, l) => s + (l.status === 'done' ? (l.home === id ? l.hg : l.ag) : 0), 0)
  const done = t.legs.every((l) => l.status === 'done')
  return (
    <div className={`mt-tie ${[a.id, b.id].includes(me) ? 'is-mine' : ''}`}>
      {[a, b].map((c) => (
        <span key={c.id} className={`mt-tie-team ${t.winner === c.id ? 'is-win' : t.winner ? 'is-out' : ''}`}>
          <OnlineCrest club={c} size={22} /><b>{c.name}</b>
          {t.adv === c.id && <small title="Melhor campanha: avança com empate no agregado">vantagem</small>}
          <em>{t.legs.some((l) => l.status === 'done') ? agg(c.id) : ''}</em>
        </span>
      ))}
      <small className="mt-tie-legs">
        {t.legs.map((l) => (l.status === 'done' ? `${l.leg === 1 ? 'Ida' : 'Volta'} ${l.hg}-${l.ag}` : `${l.leg === 1 ? 'Ida' : 'Volta'} ${new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: '2-digit' }).format(new Date(l.kickoff))} ${kickoffTime(l.kickoff)}`)).join(' · ')}
        {done && t.winner && ' · classificado'}
      </small>
    </div>
  )
}

function TableView({ me, myDiv }) {
  const [div, setDiv] = useState(myDiv || 'D')
  const { data, error } = useLoad(() => fetchOnlineStandings(div), [div])
  const s = SERIES[div]
  const ties = data?.ties || []
  const byStage = ties.reduce((m, t) => ((m[t.stage] = m[t.stage] || []).push(t), m), {})
  return (
    <div className="mt-tables">
      <DivPicker value={div} mine={myDiv} onChange={setDiv} />
      <div className="mt-format" style={{ '--sc': s.color, '--sd': s.deep }}>
        <img src={s.logo} alt="" width={44} height={44} />
        <p><b>{s.name}</b>{s.format}</p>
      </div>
      {!data && (error ? <Notice kind="error">{error}</Notice> : <Skeleton rows={10} />)}
      {['qf', 'po', 'sf', 'final'].filter((k) => byStage[k]).reverse().map((k) => (
        <div key={k} className="mt-block">
          <h4 className="mt-sub">{STAGE[k]}</h4>
          <div className="mt-ties">{byStage[k].map((t) => <TieCard key={t.tie} t={t} me={me} />)}</div>
        </div>
      ))}
      {data?.tables?.slice().sort((x, y) => y.phase - x.phase || x.grp - y.grp).map((t) => (
        <div key={`${t.phase}-${t.grp}`} className="mt-block">
          {(t.grp > 0 || t.phase > 1) && <h4 className="mt-sub">{t.phase > 1 ? `Quadrangular · Grupo ${t.grp}` : `Grupo ${t.grp}`}</h4>}
          <div className="mt-table-wrap">
            <table className="mt-table">
              <thead><tr><th>#</th><th className="is-club">Clube</th><th>P</th><th>J</th><th>V</th><th>SG</th><th className="is-form">Últimos</th></tr></thead>
              <tbody>
                {t.rows.map((r) => {
                  const z = zoneOf(div, t.phase, r.pos, t.phase > 1 ? 4 : t.rows.length)
                  return (
                    <tr key={r.id} className={`${r.id === me ? 'is-mine' : ''} ${z ? `z-${z}` : ''}`}>
                      <td><span className="mt-pos">{r.pos}</span></td>
                      <th scope="row"><OnlineCrest club={r} size={20} /><span>{r.name}</span>{!r.bot && <User size={11} aria-label="Técnico" />}</th>
                      <td><b>{r.pts}</b></td><td>{r.p}</td><td>{r.w}</td><td>{r.gf - r.ga > 0 ? `+${r.gf - r.ga}` : r.gf - r.ga}</td>
                      <td className="is-form"><Form list={r.form} /></td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
          <p className="mt-zones">{zonesFor(div, t.phase).map((z) => <span key={z}><i className={`z-${z}`} /> {ZONE_LABEL[z]}</span>)}</p>
        </div>
      ))}
    </div>
  )
}

// ── COPA ONLINE (todas as séries) ──
const CUP_ORDER = ['f1', 'f2', 'f3', 'r16', 'qf', 'sf', 'final']
function CupView({ now, me, onOpenMatch }) {
  const { data, error } = useLoad(fetchOnlineCup, [])
  const [stage, setStage] = useState(null)
  if (!data) return error ? <Notice kind="error">{error}</Notice> : <Skeleton rows={8} />
  if (!data.series) return <OnlineCup now={now} onOpenMatch={onOpenMatch} />
  const stages = (data.stages || []).slice().sort((a, b) => CUP_ORDER.indexOf(a.stage) - CUP_ORDER.indexOf(b.stage))
  const mineAt = [...stages].reverse().find((s) => s.ties.some((t) => t.mine))
  const cur = stage || mineAt?.stage || stages.at(-1)?.stage
  const st = stages.find((s) => s.stage === cur)
  const finalTie = stages.find((s) => s.stage === 'final')?.ties?.[0]
  const champ = finalTie?.winner && [finalTie.home, finalTie.away].find((c) => c.id === finalTie.winner)
  const out = stages.some((s) => s.ties.some((t) => t.mine && t.winner && t.winner !== me))
  return (
    <div className="mt-cup">
      <div className="mt-format is-cup" style={{ '--sc': CUP.color, '--sd': CUP.deep }}>
        <img src={CUP.logo} alt="" width={48} height={48} />
        <p><b>Copa Online</b>{champ ? <span className="mt-champ"><Crown size={14} /> Campeão: {champ.name}</span>
          : 'Todas as séries. 1ª fase: Séries C e D e os 6 piores da B; A e o resto da B entram na 2ª. Oitavas em diante, ida e volta. Empate: pênaltis.'}</p>
      </div>
      {mineAt && <p className={`mt-path ${out ? 'is-out' : ''}`}><Shield size={14} /> {out ? `Seu clube caiu na ${STAGE[mineAt.stage].toLowerCase()}.` : `Seu clube está na ${STAGE[mineAt.stage].toLowerCase()}.`}</p>}
      <div className="mt-stages" role="tablist" aria-label="Fases da copa">
        {stages.map((s) => <button key={s.stage} type="button" role="tab" aria-selected={s.stage === cur} className={s.stage === cur ? 'is-on' : ''} onClick={() => setStage(s.stage)}>{STAGE[s.stage]}</button>)}
      </div>
      {st && (
        <div className="mt-ties">
          {st.ties.map((t) => {
            const legs = t.legs || []
            const agg = (id) => legs.reduce((s, l) => s + (l.status === 'done' ? (l.home === id ? l.hg : l.ag) : 0), 0)
            const pens = legs.at(-1)?.pens
            const liveLeg = legs.find((l) => isLive(l, now))
            const open = liveLeg || legs.slice().reverse().find((l) => l.status === 'done')
            return (
              <button key={t.tie} type="button" className={`mt-tie ${t.mine ? 'is-mine' : ''} ${liveLeg ? 'is-live' : ''}`} disabled={!open} onClick={() => open && onOpenMatch(open.id)}>
                {[t.home, t.away].map((c, i) => (
                  <span key={c.id} className={`mt-tie-team ${t.winner === c.id ? 'is-win' : t.winner ? 'is-out' : ''}`}>
                    <OnlineCrest club={c} size={22} /><b>{c.name}</b>{c.div && <small className="mt-tag">{c.div}</small>}
                    <em>{legs.some((l) => l.status === 'done') ? agg(c.id) : ''}{pens ? <small> ({pens[legs.at(-1).home === c.id ? 0 : 1]})</small> : null}</em>
                    {i === 0 && null}
                  </span>
                ))}
                <small className="mt-tie-legs">
                  {liveLeg ? <><Radio size={11} /> ao vivo</> : legs.map((l) => (l.status === 'done' ? `${legs.length > 1 ? (l.leg === 1 ? 'Ida ' : 'Volta ') : ''}${l.hg}-${l.ag}`
                    : `${legs.length > 1 ? (l.leg === 1 ? 'Ida ' : 'Volta ') : ''}${new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: '2-digit' }).format(new Date(l.kickoff))} ${kickoffTime(l.kickoff)}`)).join(' · ')}
                  {pens && ' · pênaltis'}
                </small>
              </button>
            )
          })}
        </div>
      )}
      {data.history?.length > 0 && (
        <div className="mt-block">
          <h4 className="mt-sub">Galeria de campeões</h4>
          <ul className="mt-hall">
            {data.history.map((h) => (
              <li key={h.season}>
                <b>T{h.season}</b>
                <span>{h.series ? DIVS.filter((d) => h.series[d]).map((d) => <span key={d}><img src={SERIES[d].logo} alt={`Série ${d}`} width={16} height={16} />{h.series[d]}</span>) : <span><small>Liga</small>{h.champion}</span>}</span>
                <span><img src={CUP.logo} alt="Copa" width={16} height={16} />{h.cup || '—'}</span>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  )
}

const VIEWS = [
  { id: 'cal', label: 'Calendário', Icon: CalendarDays },
  { id: 'round', label: 'Rodada', Icon: Radio },
  { id: 'table', label: 'Tabela', Icon: ListOrdered },
  { id: 'cup', label: 'Copa', Icon: Trophy },
]

// PARTIDAS: calendário do técnico, rodadas e tabelas de todas as séries e a copa.
export default function OnlineMatches({ now, onOpenMatch, status }) {
  const [view, setView] = useState('cal')
  const lg = status?.league
  const me = status?.club?.id
  const s = SERIES[lg?.div]
  const next = status?.next
  const nc = compOf(next)
  return (
    <section className="mt">
      {s && (
        <header className="mt-hero" style={{ '--sc': s.color, '--sd': s.deep }}>
          <span className="mt-lights" aria-hidden="true" />
          <img src={s.logo} alt={s.name} width={76} height={76} />
          <div>
            <small>Temporada {lg.season}{lg.grp ? ` · Grupo ${lg.grp}` : ''}</small>
            <b>{s.name}</b>
            <span className="mt-hero-stats">
              {status.position && <span><em>{status.position}º</em> lugar</span>}
              {status.day && <span>Rodada <em>{Math.min(status.day.n, status.day.of)}</em>/{status.day.of}</span>}
              {status.standing && <span><em>{status.standing.pts}</em> pts</span>}
            </span>
          </div>
        </header>
      )}
      {next && nc && (
        <button type="button" className={`mt-next ${isLive(next, now) ? 'is-live' : ''}`} style={{ '--cc': nc.color }} onClick={() => isLive(next, now) && onOpenMatch(next.id)}>
          <span className="mt-next-label">{isLive(next, now) ? <><Radio size={12} /> Ao vivo agora</> : 'Próximo jogo'}</span>
          <span className="mt-next-body">
            <OnlineCrest club={next.opp} size={30} />
            <span><b>{next.at_home ? 'x' : '@'} {next.opp?.name}</b><small>{nc.name} · {nc.detail}</small></span>
            <span className="mt-next-when"><b>{kickoffTime(next.kickoff)}</b><small>{untilKickoff(next.kickoff, now)}</small></span>
          </span>
        </button>
      )}
      <div className="mt-tabs" role="tablist" aria-label="Partidas">
        {VIEWS.map(({ id, label, Icon }) => (
          <button key={id} type="button" role="tab" aria-selected={view === id} className={view === id ? 'is-on' : ''} onClick={() => setView(id)}><Icon size={15} /> {label}</button>
        ))}
      </div>
      {view === 'cal' && <CalendarView now={now} onOpenMatch={onOpenMatch} />}
      {view === 'round' && <RoundView now={now} me={me} myDiv={lg?.div} onOpenMatch={onOpenMatch} />}
      {view === 'table' && <TableView me={me} myDiv={lg?.div} />}
      {view === 'cup' && <CupView now={now} me={me} onOpenMatch={onOpenMatch} />}
    </section>
  )
}
