import { Whistle } from './Whistle'
import ClubCrest from '../../club/components/ClubCrest'
import ClubName from '../../club/components/ClubName'
import { getClubById } from '../../club/data/clubs'
import CompEmblem from '../ui/CompEmblem'
import { sideResult } from '../utils/seasonSelectors'
import { COMP_SHORT, fixtureLabel } from '../utils/seasonUtils'

const BADGE = { win: 'V', draw: 'E', loss: 'D' }

// Uma partida do seu clube, como um "placar" compacto. Jogada: resultado colorido do ponto de vista do
// clube que você comandava NAQUELE jogo (o histórico não muda se você trocar de clube). Tocar abre a súmula.
export default function MatchRow({ f, myClub, onOpen, highlight }) {
  const played = f.status === 'played'
  const me = f.player_match && f.coach_club ? f.coach_club : myClub
  const res = sideResult(f, me)
  const Tag = onOpen ? 'button' : 'div'
  return (
    <Tag
      type={onOpen ? 'button' : undefined}
      className={`mr ${played ? 'is-played' : 'is-future'} ${res ? `r-${res}` : ''} ${highlight ? 'is-next' : ''}`}
      onClick={onOpen ? () => onOpen(f) : undefined}
    >
      <span className="mr-meta">
        <CompEmblem comp={f.comp} size={14} />
        <b>{COMP_SHORT[f.comp]}</b>
        <span>{fixtureLabel(f)}</span>
        {highlight && <em className="gx-tag is-live">Próxima</em>}
        {res && <i className={`mr-res r-${res}`}>{BADGE[res]}</i>}
      </span>
      <span className="mr-teams">
        <span className={`mr-t home ${f.home_club === me ? 'is-mine' : ''}`}>
          <ClubName clubId={f.home_club} />
          <ClubCrest clubId={f.home_club} size={26} />
        </span>
        <span className="mr-score">{played ? `${f.home_goals} – ${f.away_goals}` : 'x'}</span>
        <span className={`mr-t away ${f.away_club === me ? 'is-mine' : ''}`}>
          <ClubCrest clubId={f.away_club} size={26} />
          <ClubName clubId={f.away_club} />
        </span>
      </span>
      {played && f.home_pens != null && (
        <small className="mr-note">
          Pênaltis {f.home_pens} – {f.away_pens}
        </small>
      )}
      {played && f.player_match && f.coach_club !== myClub && (
        <small className="mr-note">
          <Whistle /> No comando: {getClubById(f.coach_club)?.name}
        </small>
      )}
    </Tag>
  )
}
