import { Target, Users } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import CompEmblem from '../ui/CompEmblem'
import { sideResult } from '../utils/seasonSelectors'
import { COMP_SHORT, fixtureLabel, ratingTone } from '../utils/seasonUtils'

const BADGE = { win: 'V', draw: 'E', loss: 'D' }

// Uma partida do seu clube, como um "placar" compacto. Jogada: resultado colorido + sua nota, gols e assistências.
// Por jogar: sem placar. Tocar (quando onOpen existe) abre os "Jogos da rodada".
export default function MatchRow({ f, myClub, onOpen, highlight }) {
  const played = f.status === 'played'
  const res = sideResult(f, myClub)
  const Tag = onOpen ? 'button' : 'div'
  const home = getClubById(f.home_club)
  const away = getClubById(f.away_club)
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
        <span className={`mr-t home ${f.home_club === myClub ? 'is-mine' : ''}`}>
          <b>{home?.name}</b>
          <ClubCrest clubId={f.home_club} size={26} />
        </span>
        <span className="mr-score">{played ? `${f.home_goals} – ${f.away_goals}` : 'x'}</span>
        <span className={`mr-t away ${f.away_club === myClub ? 'is-mine' : ''}`}>
          <ClubCrest clubId={f.away_club} size={26} />
          <b>{away?.name}</b>
        </span>
      </span>
      {played && f.home_pens != null && (
        <small className="mr-note">
          Pênaltis {f.home_pens} – {f.away_pens}
        </small>
      )}
      {played && f.player_match && (
        <span className="mr-me">
          <i className={`mr-rate ${ratingTone(Number(f.player_rating))}`} title="Sua nota">
            {Number(f.player_rating).toFixed(1)}
          </i>
          <span title="Seus gols">
            <Target size={13} /> {f.player_goals}
          </span>
          <span title="Suas assistências">
            <Users size={13} /> {f.player_assists}
          </span>
        </span>
      )}
    </Tag>
  )
}
