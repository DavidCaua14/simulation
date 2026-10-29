import { useMemo } from 'react'
import { WorldStrip } from '../world/WorldPanel'
import { ArrowLeftRight, CalendarDays, ChevronRight, Inbox, Target } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import { FreeDayHero, LiveHero, MatchdayHero, UnemployedHero } from '../components/CoachHeroes'
import CoachStatusCard from '../components/CoachStatusCard'
import SeasonEnd from '../components/SeasonEnd'
import CalendarRow from '../components/CalendarRow'
import MatchRow from '../components/MatchRow'
import CompCard from '../components/CompCard'
import { EmptyState } from '../ui/States'
import { MSG_KIND, objectiveProgress } from '../utils/managerUtils'
import { upcomingMatch } from '../utils/seasonSelectors'

// INÍCIO: o que acontece HOJE (jogo, folga, sem clube, fim de temporada), a situação do treinador
// (diretoria, torcida, reputação), objetivos, caixa de mensagens, calendário e campeonatos.
export default function HomeTab({ ctx, actions }) {
  const { hub, byComp, nextEvent, calendar, history, myClub, canPlay, blockedText, busy } = ctx
  const coach = hub.coach
  const finished = hub.season.status === 'finished'
  const nextStart = `${hub.season.year + 1}-${hub.season.region === 'ENG' ? '07' : '01'}-01`
  const waitNext = hub.world && hub.world.today < nextStart
  const unemployed = coach.status === 'unemployed'
  const mine = nextEvent?.kind === 'mine' ? nextEvent : null
  const free = nextEvent?.kind === 'free' ? nextEvent : null
  // Hoje não é dia de jogo do seu clube: mostra o seu próximo confronto e o botão para avançar até ele
  const ahead = useMemo(
    () => (!mine && !hub.live_match && !finished && !unemployed ? upcomingMatch(calendar, byComp, myClub) : null),
    [mine, hub.live_match, finished, unemployed, calendar, byComp, myClub],
  )
  const focus = mine || ahead
  const myTable = useMemo(() => hub.competitions.find((c) => c.id === focus?.competition)?.table, [hub.competitions, focus])
  const myPos = myTable?.played ? myTable.pos : null
  const leaguePlayed = hub.competitions.find((c) => c.kind === 'league' && c.table)?.table?.played ?? null

  const last = history[0]
  const upcoming = finished ? [] : calendar.slice(mine ? 1 : 0, mine ? 4 : 3)
  const firstOffer = hub.offers[0]
  const msgs = hub.messages.slice(0, 4)

  let hero
  if (hub.live_match) hero = <LiveHero busy={busy === 'start'} onResume={actions.play} />
  else if (finished) hero = <SeasonEnd season={hub.season} coach={coach} objectives={hub.objectives} starting={busy === 'next'} nextStartsOn={waitNext ? nextStart : null} onStartNext={actions.startNext} onOffers={() => actions.goTab('career')} offers={hub.offers.length} />
  else if (unemployed)
    hero = (
      <UnemployedHero
        coach={coach}
        offersCount={hub.offers.length}
        advancing={busy === 'advance'}
        onAdvanceDay={() => actions.advance(false)}
        onWait={() => actions.advance(true)}
        onOffers={() => actions.goTab('career', 'offers')}
      />
    )
  else if (mine)
    hero = (
      <MatchdayHero
        needsAdvance={!!hub.world && (hub.world.needs_sync || mine.days_until > 0)}
        onAdvance={actions.prepareNext}
        next={mine}
        myClub={myClub}
        myPos={myPos}
        lineup={hub.lineup}
        canPlay={canPlay}
        blockedText={blockedText}
        busy={busy === 'start' || busy === 'prepare'}
        onPlay={actions.openPreMatch}
        onLineup={() => actions.goTab('team')}
      />
    )
  else if (ahead)
    hero = (
      <MatchdayHero
        needsAdvance
        onAdvance={hub.world ? actions.prepareNext : () => actions.advance(false)}
        next={ahead}
        myClub={myClub}
        myPos={myPos ?? ahead.my_position}
        lineup={hub.lineup}
        canPlay={canPlay}
        blockedText={blockedText}
        busy={!!busy}
        onPlay={actions.openPreMatch}
        onLineup={() => actions.goTab('team')}
      />
    )
  else if (hub.world) hero = <section className="sn-sec"><h2 className="gx-title">Preparar a próxima partida</h2><p className="sn-hint">As outras competições avançam junto com a sua carreira.</p><button type="button" className="gx-btn" disabled={!!busy} onClick={actions.prepareNext}>{busy === 'prepare' ? 'Avançando…' : 'Avançar para a próxima partida'}</button></section>
  else if (free) hero = <FreeDayHero event={free} calendar={calendar} advancing={busy === 'advance'} onAdvance={() => actions.advance(false)} />
  else hero = <EmptyState icon={CalendarDays} title="Nenhum jogo pendente agora" text="Acompanhe os campeonatos na aba Torneios." />

  return (
    <div className="sn-page">
      {hero}
      <WorldStrip ctx={ctx} actions={actions} />

      {firstOffer && !unemployed && (
        <button type="button" className="sn-offerbar" onClick={() => actions.goTab('career', 'offers')}>
          <span className="sn-offerbar-crest">
            <ClubCrest clubId={firstOffer.club_id} size={34} />
          </span>
          <span className="sn-offerbar-txt">
            <b>{hub.offers.length > 1 ? `${hub.offers.length} propostas de trabalho` : `${getClubById(firstOffer.club_id)?.name} quer você como treinador`}</b>
            <small>Prazo: {firstOffer.days_left > 0 ? `${firstOffer.days_left} dia(s)` : 'último dia'}. Toque para responder.</small>
          </span>
          <ArrowLeftRight size={18} />
        </button>
      )}

      <CoachStatusCard coach={coach} season={hub.season} onOpen={() => actions.goTab('career')} />

      {hub.objectives.length > 0 && !unemployed && (
        <section className="sn-sec">
          <h2 className="gx-title">
            <Target size={16} /> Objetivos da diretoria
          </h2>
          <ul className="ob-list">
            {hub.objectives.map((o) => {
              const pr = objectiveProgress(o, o.kind === 'league_pos' ? hub.competitions.find((c) => c.id === o.competition)?.table?.played ?? leaguePlayed : null)
              return (
                <li key={o.id} className={`ob is-${o.status} t-${pr.tone}`}>
                  <span className="ob-prio" title="Importância">
                    {'●'.repeat(o.priority)}
                  </span>
                  <span className="ob-txt">
                    <b>{o.label}</b>
                    <small>{pr.text}</small>
                  </span>
                </li>
              )
            })}
          </ul>
        </section>
      )}

      <section className="sn-sec">
        <div className="sn-sec-head">
          <h2 className="gx-title">
            <Inbox size={16} /> Mensagens {hub.unread > 0 && <em className="sn-badge">{hub.unread}</em>}
          </h2>
          {hub.messages.length > msgs.length && (
            <button type="button" className="sn-link" onClick={actions.openInbox}>
              Ver todas <ChevronRight size={14} />
            </button>
          )}
        </div>
        {msgs.length === 0 ? (
          <p className="sn-muted">Nenhuma mensagem ainda.</p>
        ) : (
          <ul className="ib-list">
            {msgs.map((m) => (
              <li key={m.id}>
                <button type="button" className={`ib ${m.read ? '' : 'is-new'} k-${MSG_KIND[m.kind]?.tone || 'system'}`} onClick={() => actions.openInbox(m.id)}>
                  {m.club_id ? <ClubCrest clubId={m.club_id} size={26} /> : <span className="ib-dot" />}
                  <span className="ib-txt">
                    <small>
                      {MSG_KIND[m.kind]?.label || 'Clube'} · dia {m.day_no}
                    </small>
                    <b>{m.title}</b>
                  </span>
                </button>
              </li>
            ))}
          </ul>
        )}
      </section>

      {(last || upcoming.length > 0) && (
        <section className="sn-sec">
          <div className="sn-sec-head">
            <h2 className="gx-title">Calendário</h2>
            <button type="button" className="sn-link" onClick={() => actions.goTab('matches')}>
              Ver tudo <ChevronRight size={14} />
            </button>
          </div>
          <ol className="tl">
            {last && (
              <li className="tl-item is-done">
                <span className="tl-label">Último jogo</span>
                <MatchRow f={last} myClub={myClub} onOpen={actions.openReport} />
              </li>
            )}
            {upcoming.map((e, i) => (
              <li key={`${e.comp}-${e.stage}-${e.round}`} className="tl-item is-future">
                {i === 0 && <span className="tl-label">Em seguida</span>}
                <CalendarRow event={e} myClub={myClub} />
              </li>
            ))}
          </ol>
        </section>
      )}

      <section className="sn-sec">
        <h2 className="gx-title">
          Competições <small>toque para ver tabela e chaves</small>
        </h2>
        <div className="sn-stack">
          {hub.competitions.map((c) => (
            <CompCard key={c.id} comp={c} onOpen={actions.openComp} />
          ))}
        </div>
      </section>
    </div>
  )
}
