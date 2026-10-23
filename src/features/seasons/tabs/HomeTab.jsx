import { useMemo } from 'react'
import { ArrowLeftRight, ChevronRight } from 'lucide-react'
import NextMatchCard from '../components/NextMatchCard'
import FreeRoundCard from '../components/FreeRoundCard'
import CalendarRow from '../components/CalendarRow'
import SeasonSummary from '../components/SeasonSummary'
import MatchRow from '../components/MatchRow'
import { EXPECTED_MATCHES, clubForm, standingsFrom } from '../utils/seasonSelectors'
import { COMP_NAME, STAGE_LABEL, ordinal } from '../utils/seasonUtils'

function campaignText(c) {
  if (c.status === 'finished') return c.player_result || 'Encerrado'
  if (c.status === 'out') return 'Eliminado'
  if (c.status === 'not_in') return 'Seu clube não disputa'
  const pos = c.table ? ` · ${c.table.group ? `Grupo ${c.table.group} · ` : ''}${ordinal(c.table.pos)} · ${c.table.points} pts` : ''
  return `${STAGE_LABEL[c.stage]}${pos}`
}

// INÍCIO: o que fazer agora (jogar a SUA partida ou tocar em "Próximo"), o último jogo, o calendário e a campanha.
export default function HomeTab({ ctx, onGoTab, onOpenComp, onOpenRound, onPlay, onAdvance, onStartNext }) {
  const { hub, byComp, flat, nextEvent, calendar, history, myClub, canPlay, blockedText, playing, advancing, starting } = ctx
  const finished = hub.season.status === 'finished'
  const mine = nextEvent?.kind === 'mine' ? nextEvent : null
  const free = nextEvent?.kind === 'free' ? nextEvent : null

  // Relatório do adversário: posição na tabela + forma recente dos dois clubes
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

  return (
    <div className="sn-page">
      {finished ? (
        <SeasonSummary season={hub.season} starting={starting} onStartNext={onStartNext} />
      ) : mine ? (
        <NextMatchCard
          comp={{ id: mine.competition, next: mine.match }}
          myClub={myClub}
          reports={reports}
          canPlay={canPlay}
          playing={playing}
          blockedText={blockedText}
          onPlay={onPlay}
        />
      ) : free ? (
        <FreeRoundCard event={free} calendar={calendar} advancing={advancing} onAdvance={onAdvance} />
      ) : (
        <div className="sn-empty card">
          <p>Nenhuma partida pendente agora.</p>
          <small>Abra a aba Torneios para acompanhar os campeonatos.</small>
        </div>
      )}

      {hub.offers.length > 0 && (
        <button type="button" className="sn-offer-alert" onClick={() => onGoTab('market')}>
          <ArrowLeftRight size={18} />
          <span>
            Você tem <b>{hub.offers.length}</b> proposta{hub.offers.length > 1 ? 's' : ''} de clube com prazo para responder. Toque para ver.
          </span>
        </button>
      )}

      {last && (
        <section>
          <h3 className="sn-h">Último jogo</h3>
          <MatchRow f={last} myClub={myClub} onOpen={onOpenRound} />
        </section>
      )}

      {!finished && calendar.length > 1 && (
        <section>
          <div className="sn-h-row">
            <h3 className="sn-h">Depois disso</h3>
            <button type="button" className="sn-link" onClick={() => onGoTab('matches')}>
              Calendário <ChevronRight size={14} />
            </button>
          </div>
          <div className="sn-stack">
            {calendar.slice(1, 4).map((e) => (
              <CalendarRow key={`${e.comp}-${e.stage}-${e.round}`} event={e} myClub={myClub} />
            ))}
          </div>
        </section>
      )}

      <section>
        <h3 className="sn-h">Sua campanha</h3>
        <div className="sn-stack">
          {hub.competitions.map((c) => (
            <button key={c.id} type="button" className={`sn-camp status-${c.status}`} onClick={() => onOpenComp(c.id)}>
              <span className="sn-camp-main">
                <b>{COMP_NAME[c.id]}</b>
                <small>{campaignText(c)}</small>
              </span>
              {c.status === 'active' && (
                <span className="sn-camp-bar" aria-hidden="true">
                  <i style={{ width: `${Math.min(100, (c.played / (EXPECTED_MATCHES[c.id] || c.total || 1)) * 100)}%` }} />
                </span>
              )}
              <ChevronRight size={16} />
            </button>
          ))}
        </div>
      </section>
    </div>
  )
}
