import { FastForward } from 'lucide-react'
import MatchRow from './MatchRow'
import { COMP_NAME } from '../utils/seasonUtils'

// Uma linha do calendário: partida do seu clube ("mine") ou rodada de outro campeonato ("free").
export default function CalendarRow({ event, myClub, highlight }) {
  if (event.kind === 'mine') return <MatchRow f={event.fixture} myClub={myClub} highlight={highlight} />
  return (
    <div className={`sn-free-row ${highlight ? 'is-next' : ''}`}>
      <span className="sn-free-ico">
        <FastForward size={14} />
      </span>
      <div>
        <b>{COMP_NAME[event.comp]}</b>
        <small>{event.label} · seu clube não joga</small>
      </div>
      {highlight && <em>PRÓXIMO</em>}
    </div>
  )
}
