import { useMemo } from 'react'
import { ArrowLeftRight, CalendarDays, ChevronRight } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import NextMatchHero from '../components/NextMatchHero'
import FreeRoundHero from '../components/FreeRoundHero'
import CalendarRow from '../components/CalendarRow'
import SeasonSummary from '../components/SeasonSummary'
import MatchRow from '../components/MatchRow'
import CompCard from '../components/CompCard'
import { EmptyState } from '../ui/States'
import { clubForm, standingsFrom } from '../utils/seasonSelectors'

// INÍCIO: o evento do dia em destaque (sua partida, rodada de folga ou fim de temporada),
// propostas pendentes, a linha do tempo da temporada e os três campeonatos.
export default function HomeTab({ ctx, onGoTab, onOpenComp, onOpenRound, onPlay, onAdvance, onStartNext }) {
  const { hub, byComp, flat, nextEvent, calendar, history, myClub, canPlay, blockedText, playing, advancing, starting } = ctx
  const finished = hub.season.status === 'finished'
  const mine = nextEvent?.kind === 'mine' ? nextEvent : null
  const free = nextEvent?.kind === 'free' ? nextEvent : null

  // Relatório dos dois clubes: posição na tabela (quando é pontos corridos/grupos) + forma recente
  const reports = useMemo(() => {
    if (!mine) return {}
    const m = mine.match
    const rows = m.stage === 'league' || m.stage === 'group' ? standingsFrom(byComp[mine.competition], m.group || null) : null
    const rep = (id) => {
      const r = rows?.find((x) => x.club_id === id)
      return { pos: r?.pos, points: r?.points, form: clubForm(flat, id) }
    }
    return { [m.home]: rep(m.home), [m.away]: rep(m.away) }
  }, [mine, byComp, flat])

  const last = history[0]
  const upcoming = finished ? [] : calendar.slice(1, 4)
  const firstOffer = hub.offers[0]

  return (
    <div className="sn-page">
      {finished ? (
        <SeasonSummary season={hub.season} starting={starting} onStartNext={onStartNext} />
      ) : mine ? (
        <NextMatchHero
          comp={{ id: mine.competition, next: mine.match }}
          myClub={myClub}
          reports={reports}
          canPlay={canPlay}
          playing={playing}
          blockedText={blockedText}
          onPlay={onPlay}
        />
      ) : free ? (
        <FreeRoundHero event={free} calendar={calendar} advancing={advancing} onAdvance={onAdvance} />
      ) : (
        <EmptyState icon={CalendarDays} title="Nenhuma partida pendente agora" text="Acompanhe os campeonatos na aba Torneios." />
      )}

      {firstOffer && (
        <button type="button" className="sn-offerbar" onClick={() => onGoTab('market')}>
          <span className="sn-offerbar-crest">
            <ClubCrest clubId={firstOffer.club_id} size={34} />
          </span>
          <span className="sn-offerbar-txt">
            <b>
              {hub.offers.length > 1 ? `${hub.offers.length} propostas na mesa` : `O ${getClubById(firstOffer.club_id)?.name} quer você`}
            </b>
            <small>Toda proposta tem prazo. Toque para responder.</small>
          </span>
          <ArrowLeftRight size={18} />
        </button>
      )}

      {(last || upcoming.length > 0) && (
        <section className="sn-sec">
          <div className="sn-sec-head">
            <h2 className="gx-title">Calendário</h2>
            <button type="button" className="sn-link" onClick={() => onGoTab('matches')}>
              Ver tudo <ChevronRight size={14} />
            </button>
          </div>
          <ol className="tl">
            {last && (
              <li className="tl-item is-done">
                <span className="tl-label">Último jogo</span>
                <MatchRow f={last} myClub={myClub} onOpen={onOpenRound} />
              </li>
            )}
            {upcoming.map((e, i) => (
              <li key={`${e.comp}-${e.stage}-${e.round}`} className="tl-item is-future">
                {i === 0 && <span className="tl-label">Depois disso</span>}
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
            <CompCard key={c.id} comp={c} onOpen={onOpenComp} />
          ))}
        </div>
      </section>
    </div>
  )
}
