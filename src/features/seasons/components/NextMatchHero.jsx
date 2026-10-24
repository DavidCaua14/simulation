import { Lock, Play, Zap } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import CompEmblem from '../ui/CompEmblem'
import FormDots from './FormDots'
import stadium from '../../home/assets/temporadas.webp'
import { COMP_NAME, COMP_THEME, describeMatch, ordinal, venueLabel } from '../utils/seasonUtils'

function Side({ clubId, mine, report, align }) {
  const club = getClubById(clubId)
  return (
    <div className={`nm-side ${align} ${mine ? 'is-mine' : ''}`}>
      <span className="nm-crest" style={{ '--cc': club?.colors?.[0] || '#33415c' }}>
        <ClubCrest clubId={clubId} size={62} />
      </span>
      <b className="nm-club">{club?.name}</b>
      {mine && <span className="nm-you">Seu clube</span>}
      <span className="nm-pos">{report?.pos ? `${ordinal(report.pos)} · ${report.points} pts` : 'Mata-mata'}</span>
      <FormDots form={report?.form} />
    </div>
  )
}

// A partida do seu clube = o evento principal da tela. Estado: disponível, simulando ou bloqueado (sem energia).
export default function NextMatchHero({ comp, myClub, reports, canPlay, playing, blockedText, onPlay }) {
  const m = comp.next
  const t = COMP_THEME[comp.id]
  const venue = venueLabel(m)
  return (
    <section className="nm" style={{ '--c1': t.c1, '--c2': t.c2 }} aria-label="Próxima partida">
      <img className="nm-bg" src={stadium} alt="" />
      <span className="nm-shade" aria-hidden="true" />
      <span className="nm-lights" aria-hidden="true" />

      <header className="nm-head">
        <CompEmblem comp={comp.id} size={30} />
        <span className="nm-head-txt">
          <small>Próxima partida</small>
          <b>{COMP_NAME[comp.id]}</b>
        </span>
        <span className="nm-round">{describeMatch(m)}</span>
      </header>

      <div className="nm-versus">
        <Side clubId={m.home} mine={m.home === myClub} report={reports[m.home]} align="left" />
        <div className="nm-mid">
          <span className="nm-vs">VS</span>
          {venue && <span className={`nm-venue ${m.venue === 'home' && !m.neutral ? 'is-home' : ''}`}>{venue}</span>}
        </div>
        <Side clubId={m.away} mine={m.away === myClub} report={reports[m.away]} align="right" />
      </div>

      <div className="nm-cta">
        <button type="button" className={`gx-btn nm-play ${canPlay ? 'is-ready' : ''}`} disabled={playing || !canPlay} onClick={onPlay}>
          {playing ? (
            <>
              <span className="nm-spin" /> Simulando partida…
            </>
          ) : canPlay ? (
            <>
              <Play size={20} fill="currentColor" /> Jogar partida
              <span className="nm-cost" title="Custa 1 de energia">
                <Zap size={13} fill="currentColor" />1
              </span>
            </>
          ) : (
            <>
              <Lock size={17} /> {blockedText}
            </>
          )}
        </button>
        <small>Você joga uma partida por vez: a do seu clube. O resto da rodada é simulado junto.</small>
      </div>
    </section>
  )
}
