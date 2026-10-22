import { Zap } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import FormDots from './FormDots'
import { COMP_NAME, describeMatch, ordinal, venueLabel } from '../utils/seasonUtils'

function Side({ clubId, mine, report }) {
  return (
    <div className={`sn-nm-side ${mine ? 'is-mine' : ''}`}>
      <ClubCrest clubId={clubId} size={58} />
      <b>{getClubById(clubId)?.name}</b>
      <span className="sn-nm-pos">{report?.pos ? `${ordinal(report.pos)} · ${report.points} pts` : 'Mata-mata'}</span>
      <FormDots form={report?.form} />
    </div>
  )
}

// A ÚNICA partida que dá para jogar agora: a do seu clube. Com um "relatório do adversário" (posição e forma).
export default function NextMatchCard({ comp, myClub, reports, canPlay, playing, blockedText, onPlay }) {
  const m = comp.next
  return (
    <section className={`sn-nm card tone-${comp.id}`}>
      <header>
        <small>Próxima partida</small>
        <b>{COMP_NAME[comp.id]}</b>
        <span>
          {describeMatch(m)} · {venueLabel(m)}
        </span>
      </header>

      <div className="sn-nm-versus">
        <Side clubId={m.home} mine={m.home === myClub} report={reports[m.home]} />
        <span className="sn-nm-x">×</span>
        <Side clubId={m.away} mine={m.away === myClub} report={reports[m.away]} />
      </div>

      <button type="button" className="sn-play sn-play-big" disabled={playing || !canPlay} onClick={onPlay}>
        {playing ? (
          'Simulando…'
        ) : canPlay ? (
          <>
            Jogar partida
            <span className="sn-cost">
              <Zap size={13} fill="currentColor" />1
            </span>
          </>
        ) : (
          blockedText
        )}
      </button>
      <small className="sn-nm-note">Você joga uma partida por vez: a do seu clube. O resto da rodada é simulado junto.</small>
    </section>
  )
}
