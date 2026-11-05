import { useEffect, useMemo, useState } from 'react'
import { CalendarDays, ChevronLeft, ChevronRight, History, ListOrdered, Play, Search } from 'lucide-react'
import MatchRow from '../components/MatchRow'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import CompEmblem from '../ui/CompEmblem'
import { EmptyState } from '../ui/States'
import { fetchCareerCalendar } from '../services/managerApi'
import { buildRounds, defaultRoundIndex, involves, sideResult } from '../utils/seasonSelectors'
import { COMP_NAME, COMP_ORDER, COMP_SHORT, fixtureLabel, seasonLabel } from '../utils/seasonUtils'
import './matches.css'

const VIEWS = [
  { id: 'calendar', label: 'Calendário', icon: CalendarDays },
  { id: 'round', label: 'Rodada', icon: ListOrdered },
  { id: 'results', label: 'Resultados', icon: History },
]
const BADGE = { win: 'V', draw: 'E', loss: 'D' }
const shortDate = (iso) => (iso ? new Date(`${iso.slice(0, 10)}T12:00:00`).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' }) : null)
const clubName = (id) => getClubById(id)?.short_name || getClubById(id)?.name || id

// Seletor de campeonato no estilo CM: caixa azul com a competição e setas.
function CompSelect({ comps, value, onChange }) {
  const i = Math.max(0, comps.indexOf(value))
  return (
    <div className="jg-select">
      <button type="button" aria-label="Campeonato anterior" disabled={comps.length < 2} onClick={() => onChange(comps[(i - 1 + comps.length) % comps.length])}>
        <ChevronLeft size={18} />
      </button>
      <span>
        <CompEmblem comp={value} size={18} />
        {COMP_NAME[value] || COMP_SHORT[value]}
      </span>
      <button type="button" aria-label="Próximo campeonato" disabled={comps.length < 2} onClick={() => onChange(comps[(i + 1) % comps.length])}>
        <ChevronRight size={18} />
      </button>
    </div>
  )
}

// Destaque do próximo jogo: escudos, "Hoje • Fora" e os botões VER ADVERSÁRIO / JOGAR.
function NextMatch({ next, myClub, ctx, actions }) {
  const { hub, busy, canPlay, canGo, blockedText } = ctx
  const m = next.match
  const away = m.venue === 'away'
  const needsRound = Boolean(hub.world && (hub.world.needs_sync || next.days_until > 0))
  const when = next.days_until > 0 ? `Em ${next.days_until} ${next.days_until === 1 ? 'dia' : 'dias'}` : 'Hoje'
  const venue = m.neutral ? 'Neutro' : away ? 'Fora' : 'Casa'
  const enabled = needsRound ? canGo : canPlay
  return (
    <section className="jg-next" aria-label="Próximo jogo">
      <header>
        <CompEmblem comp={next.competition} size={16} />
        <b>{COMP_SHORT[next.competition]}</b>
        <span>{fixtureLabel({ comp: next.competition, stage: next.stage, round_no: next.round, leg: m.leg, group_label: m.group })}</span>
        <em>
          {when} • {venue}
        </em>
      </header>
      <div className="jg-next-vs">
        <span className={m.home === myClub ? 'is-mine' : ''}>
          <ClubCrest clubId={m.home} size={52} />
          <b>{clubName(m.home)}</b>
        </span>
        <i>×</i>
        <span className={m.away === myClub ? 'is-mine' : ''}>
          <ClubCrest clubId={m.away} size={52} />
          <b>{clubName(m.away)}</b>
        </span>
      </div>
      <div className="jg-actions">
        <button type="button" className="gx-btn-ghost" disabled={!!busy} onClick={actions.openPreMatch}>
          <Search size={15} /> Ver adversário
        </button>
        <button type="button" className="gx-btn" disabled={!enabled} onClick={hub.world ? actions.goToMatch : actions.openPreMatch}>
          <Play size={15} /> {busy === 'prepare' ? 'Preparando…' : 'Jogar'}
        </button>
      </div>
      {!enabled && !busy && <small className="jg-blocked">{blockedText}</small>}
    </section>
  )
}

// Tabela Data / Confronto / Placar com o jogo do seu clube em destaque.
function FixtureTable({ rows, myClub, nextId, today, onOpen, showDate = true }) {
  return (
    <table className="sn-table jg-table">
      <thead>
        <tr>
          {showDate && <th>Data</th>}
          <th>Confronto</th>
          <th>Placar</th>
        </tr>
      </thead>
      <tbody>
        {rows.map((f) => {
          const played = f.status === 'played'
          const mine = involves(f, myClub)
          const res = mine ? sideResult(f, myClub) : null
          const isNext = f.id === nextId
          const open = played && onOpen && (f.player_match || mine) ? () => onOpen(f.id) : undefined
          return (
            <tr key={f.id} className={`${mine ? 'jg-mine' : ''} ${isNext ? 'is-next' : ''} ${open ? 'is-link' : ''}`} onClick={open}>
              {showDate && <td className="jg-date">{isNext ? today : played ? shortDate(f.played_at) || `R${f.round_no}` : `R${f.round_no}`}</td>}
              <td className="jg-vs">
                <span className={f.home_club === myClub ? 'is-me' : ''}>
                  <ClubCrest clubId={f.home_club} size={18} />
                  {clubName(f.home_club)}
                </span>
                <span className={f.away_club === myClub ? 'is-me' : ''}>
                  <ClubCrest clubId={f.away_club} size={18} />
                  {clubName(f.away_club)}
                </span>
              </td>
              <td className="jg-score">
                {played ? (
                  <>
                    <b>
                      {f.home_goals}-{f.away_goals}
                    </b>
                    {f.home_pens != null && (
                      <small>
                        ({f.home_pens}-{f.away_pens})
                      </small>
                    )}
                    {res && <i className={`mr-res r-${res}`}>{BADGE[res]}</i>}
                  </>
                ) : (
                  <span className="jg-pending">–</span>
                )}
              </td>
            </tr>
          )
        })}
      </tbody>
    </table>
  )
}

// "PRÓXIMOS JOGOS": a sequência do calendário, alternando campeonatos.
function Upcoming({ calendar, myClub }) {
  const list = calendar.filter((e) => e.kind === 'mine').slice(1, 6)
  if (!list.length) return null
  return (
    <section className="jg-upcoming">
      <h3>Próximos jogos</h3>
      <ul>
        {list.map((e) => {
          const f = e.fixture
          const opp = f.home_club === myClub ? f.away_club : f.home_club
          return (
            <li key={f.id}>
              <CompEmblem comp={e.comp} size={16} />
              <small>{COMP_SHORT[e.comp]}</small>
              <ClubCrest clubId={opp} size={22} />
              <b>{getClubById(opp)?.name}</b>
              <em>{f.home_club === myClub ? 'Casa' : 'Fora'}</em>
            </li>
          )
        })}
      </ul>
    </section>
  )
}

// JOGOS no formato CM: Calendário (seu caminho no campeonato), Rodada (todos os jogos) e Resultados.
export default function MatchesTab({ ctx, actions }) {
  const { hub, byComp, history, calendar, myClub } = ctx
  const next = hub.next_event?.kind === 'mine' ? hub.next_event : null
  const comps = useMemo(() => COMP_ORDER.filter((id) => (byComp[id] || []).length), [byComp])
  const [view, setView] = useState('calendar')
  const [picked, setComp] = useState(() => (next && comps.includes(next.competition) ? next.competition : comps[0]))
  const comp = comps.includes(picked) ? picked : comps[0]
  const [filter, setFilter] = useState('all')
  const fixtures = useMemo(() => byComp[comp] || [], [byComp, comp])
  // No calendário novo a aba Jogos recebe só os seus jogos; a Rodada busca o campeonato inteiro sob demanda.
  const [full, setFull] = useState({})
  const fullKey = `${hub.season.id}:${comp}:${hub.calendar_versions?.[comp] ?? ''}`
  const needsFull = view === 'round' && hub.calendar_versions != null && !!comp && !full[fullKey]
  useEffect(() => {
    if (!needsFull) return undefined
    let alive = true
    fetchCareerCalendar('competition', comp)
      .then((rows) => alive && setFull((m) => ({ ...m, [fullKey]: rows })))
      .catch(() => {})
    return () => {
      alive = false
    }
  }, [needsFull, comp, fullKey])
  const myRounds = useMemo(() => buildRounds(fixtures), [fixtures])
  const rounds = useMemo(() => buildRounds(full[fullKey] || fixtures), [full, fullKey, fixtures])
  const lastKey = useMemo(() => {
    const last = history.find((f) => f.comp === comp)
    return last ? `${last.stage}:${last.round_no}` : null
  }, [history, comp])
  const [roundIdx, setRoundIdx] = useState(null)
  const season = hub.season
  const today = next?.days_until > 0 ? shortDate(next.scheduled_on) || 'Próx.' : 'Hoje'

  const changeComp = (id) => {
    setComp(id)
    setRoundIdx(null)
  }
  const ri = Math.min(roundIdx ?? defaultRoundIndex(rounds, lastKey), Math.max(0, rounds.length - 1))
  const round = rounds[ri]
  const mine = myRounds.flatMap((r) => r.matches.filter((f) => involves(f, myClub)))
  const results = filter === 'all' ? history : history.filter((f) => f.comp === filter)

  return (
    <div className="sn-page jg">
      <div className="sn-seg" role="tablist">
        {VIEWS.map(({ id, label, icon: Icon }) => (
          <button key={id} type="button" role="tab" aria-selected={view === id} className={view === id ? 'is-on' : ''} onClick={() => setView(id)}>
            <Icon size={15} /> {label}
          </button>
        ))}
      </div>

      {view === 'calendar' && (
        <>
          {next && <NextMatch next={next} myClub={myClub} ctx={ctx} actions={actions} />}
          {comps.length > 0 && <CompSelect comps={comps} value={comp} onChange={changeComp} />}
          {mine.length ? (
            <FixtureTable rows={mine} myClub={myClub} nextId={next?.fixture_id} today={today} onOpen={actions.openReport} />
          ) : (
            <EmptyState icon={CalendarDays} title="Sem jogos programados" text="Os jogos do mata-mata aparecem conforme os confrontos são definidos." />
          )}
          <Upcoming calendar={calendar} myClub={myClub} />
        </>
      )}

      {view === 'round' && (
        <>
          {comps.length > 0 && <CompSelect comps={comps} value={comp} onChange={changeComp} />}
          {round ? (
            <>
              <div className="jg-round">
                <button type="button" onClick={() => setRoundIdx(ri - 1)} disabled={ri <= 0} aria-label="Rodada anterior">
                  <ChevronLeft size={20} />
                </button>
                <span>
                  <b>{round.label}</b>
                  <small className={round.done ? '' : 'is-open'}>{round.done ? 'Encerrada' : 'Em aberto'}</small>
                </span>
                <button type="button" onClick={() => setRoundIdx(ri + 1)} disabled={ri >= rounds.length - 1} aria-label="Próxima rodada">
                  <ChevronRight size={20} />
                </button>
              </div>
              <FixtureTable rows={round.matches} myClub={myClub} nextId={next?.fixture_id} today={today} onOpen={actions.openReport} showDate={false} />
            </>
          ) : (
            <EmptyState icon={ListOrdered} title="Sem rodadas ainda" text="O sorteio do campeonato ainda não foi feito." />
          )}
        </>
      )}

      {view === 'results' && (
        <>
          <div className="sn-chips" role="tablist" aria-label="Filtrar por campeonato">
            {['all', ...COMP_ORDER].map((id) => (
              <button key={id} type="button" className={filter === id ? 'is-on' : ''} onClick={() => setFilter(id)}>
                {id !== 'all' && <CompEmblem comp={id} size={14} />}
                {id === 'all' ? 'Todos' : COMP_SHORT[id]}
              </button>
            ))}
          </div>
          {history.length > 0 && (
            <div className="mt-record" aria-label="Sua campanha nesta temporada">
              <small>Temporada {seasonLabel(season.year, season.region)}</small>
              <span className="w">
                <b>{season.wins}</b> V
              </span>
              <span className="d">
                <b>{season.draws}</b> E
              </span>
              <span className="l">
                <b>{season.losses}</b> D
              </span>
            </div>
          )}
          {results.length ? (
            <div className="sn-stack">
              {results.map((f) => (
                <MatchRow key={f.id} f={f} myClub={myClub} onOpen={actions.openReport} />
              ))}
            </div>
          ) : (
            <EmptyState icon={History} title="Nenhum resultado ainda" text="Toque em JOGAR para comandar seu time na primeira partida." />
          )}
        </>
      )}
    </div>
  )
}
