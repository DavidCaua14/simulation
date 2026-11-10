import ClubFundingCard from '../components/ClubFundingCard'
import GameIcon from '../../../components/ui/GameIcon'
import ExitModeButton from '../components/ExitModeButton'
import ClubCentral from '../components/ClubCentral'
import { useMemo } from 'react'
import { CalendarDays, ChevronRight, Inbox, Target } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import { AdvanceHero, LiveHero, MatchdayHero, UnemployedHero } from '../components/CoachHeroes'
import CoachStatusCard from '../components/CoachStatusCard'
import SeasonEnd from '../components/SeasonEnd'
import CalendarRow from '../components/CalendarRow'
import MatchRow from '../components/MatchRow'
import CompCard from '../components/CompCard'
import { EmptyState } from '../ui/States'
import { MSG_CATEGORIES, MSG_KIND, msgCategory, objectiveProgress } from '../utils/managerUtils'

const RISK_TEXT = {
  ok: () => 'Dentro da meta.',
  attention: () => 'Abaixo da meta, mas ainda dentro da margem aceita pela diretoria.',
  danger: () => 'Muito abaixo da meta. A continuidade do trabalho está em risco.',
}

// Meta da liga e risco: principal critério da diretoria; copas mexem com a confiança e o prêmio.
function LeagueRisk({ status }) {
  if (!status || status.pos == null) return null
  return (
    <div className={`ob-risk is-${status.risk}`} role="status">
      <b>
        Meta da liga: até o {status.target}º · hoje {status.pos}º
      </b>
      <small>
        {RISK_TEXT[status.risk]?.() || ''} A campanha na liga é o principal critério de avaliação da diretoria.
      </small>
    </div>
  )
}

// INÍCIO: o que acontece HOJE (jogo, folga, sem clube, fim de temporada), a situação do treinador
// (diretoria, torcida, reputação), objetivos, caixa de mensagens, calendário e campeonatos.
export default function HomeTab({ ctx, actions }) {
  const { hub, nextEvent, calendar, history, myClub, canPlay, canGo, blockedText, busy } = ctx
  const coach = hub.coach
  const finished = hub.season.status === 'finished'
  const nextStart = `${hub.season.year + 1}-${hub.season.region === 'ENG' ? '07' : '01'}-01`
  const waitNext = hub.world && hub.world.today < nextStart
  const unemployed = coach.status === 'unemployed'
  const mine = nextEvent?.kind === 'mine' ? nextEvent : null
  const free = nextEvent?.kind === 'free' ? nextEvent : null
  // Próxima partida do seu clube: sempre em destaque (rodada a rodada, como no CM). Com o mundo paralelo,
  // JOGAR resolve a rodada até a data do jogo e abre o pré-jogo.
  const matchday = mine
  const needsRound = Boolean(hub.world && mine && (hub.world.needs_sync || mine.days_until > 0))
  const myTable = useMemo(() => hub.competitions.find((c) => c.id === matchday?.competition)?.table, [hub.competitions, matchday])
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
        onWait={() => actions.advance(true)}
        onOffers={() => actions.goTab('career', 'offers')}
      />
    )
  else if (matchday)
    hero = (
      <MatchdayHero
        next={matchday}
        myClub={myClub}
        myPos={myPos}
        lineup={hub.lineup}
        canPlay={needsRound ? canGo : canPlay}
        blockedText={blockedText}
        busy={busy === 'start' || busy === 'prepare'}
        busyText={busy === 'prepare' ? (ctx.prepareProgress ? `Preparando a rodada… ${ctx.prepareProgress}` : 'Preparando a rodada…') : null}
        upcoming={needsRound}
        onPlay={hub.world ? actions.goToMatch : actions.openPreMatch}
        onLineup={() => actions.goTab('team')}
      />
    )
  else if (hub.world || free || mine)
    hero = <AdvanceHero busy={!!busy} progress={ctx.prepareProgress} onAdvance={hub.world ? actions.prepareNext : () => actions.advance(false)} />
  else hero = <EmptyState icon={CalendarDays} title="Nenhum jogo pendente agora" text="Acompanhe os campeonatos na aba Torneios." />

  return (
    <div className="sn-page">
      {hub.attention && (
        <section className="sn-attention" role="status">
          <h2>Uma decisão precisa da sua atenção</h2>
          <p>Há uma proposta, resposta de negociação ou vencimento de contrato próximo. O calendário foi pausado para você decidir.</p>
          <button type="button" className="gx-btn" disabled={!!busy} onClick={actions.openAttention}>Ver decisão</button>
          <p>Se continuar sem responder, o prazo seguirá contando e a proposta poderá expirar.</p>
          <button type="button" className="sn-link" disabled={!!busy} onClick={actions.deferAttention}>Continuar sem responder</button>
        </section>
      )}
      {hero}
      <ClubCentral embedded hub={hub} actions={actions} />
      {!unemployed && <ClubFundingCard signal={hub.world?.investment?.signal} actions={actions} disabled={!!busy} />}

      {firstOffer && !unemployed && (
        <button type="button" className="sn-offerbar" onClick={() => actions.goTab('career', 'offers')}>
          <span className="sn-offerbar-crest">
            <ClubCrest clubId={firstOffer.club_id} size={34} />
          </span>
          <span className="sn-offerbar-txt">
            <b>{hub.offers.length > 1 ? `${hub.offers.length} propostas de trabalho` : `${getClubById(firstOffer.club_id)?.name} quer você como treinador`}</b>
            <small>Prazo: {firstOffer.days_left > 0 ? `${firstOffer.days_left} dia(s)` : 'último dia'}. Toque para responder.</small>
          </span>
          <GameIcon name="transfer" size={18} />
        </button>
      )}

      <CoachStatusCard coach={coach} season={hub.season} onOpen={() => actions.goTab('career')} />

      {hub.objectives.length > 0 && !unemployed && (
        <section className="sn-sec">
          <h2 className="gx-title">
            <Target size={16} /> Objetivos da diretoria
          </h2>
          <LeagueRisk status={hub.league_status} />
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
          {hub.messages.length > 0 && (
            <button type="button" className="sn-link" onClick={actions.openInbox}>
              Ver todas <ChevronRight size={14} />
            </button>
          )}
        </div>
        {hub.messages.length > 0 && (
          <div className="ib-cats is-home" aria-label="Mensagens por assunto">
            {MSG_CATEGORIES.filter((c) => c.id !== 'all').map((c) => {
              const unread = hub.messages.filter((m) => !m.read && msgCategory(m) === c.id).length
              return (
                <button key={c.id} type="button" className={unread ? 'has-new' : ''} onClick={() => actions.openInbox(c.id)}>
                  {c.label}
                  {unread > 0 && <em>{unread}</em>}
                </button>
              )
            })}
          </div>
        )}
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
      <ExitModeButton onExit={actions.exit} />
    </div>
  )
}
