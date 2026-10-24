import { FastForward } from 'lucide-react'
import MatchRow from './MatchRow'
import CompEmblem from '../ui/CompEmblem'
import { COMP_SHORT } from '../utils/seasonUtils'

// Item do calendário: partida do seu clube ("mine") ou rodada de outro campeonato em que você folga ("free").
export default function CalendarRow({ event, myClub, highlight }) {
  if (event.kind === 'mine') return <MatchRow f={event.fixture} myClub={myClub} highlight={highlight} />
  return (
    <div className={`fr ${highlight ? 'is-next' : ''}`}>
      <CompEmblem comp={event.comp} size={18} dim />
      <span className="fr-txt">
        <b>{COMP_SHORT[event.comp]}</b> · {event.label}
      </span>
      <span className="fr-tag">
        <FastForward size={11} /> folga
      </span>
    </div>
  )
}
