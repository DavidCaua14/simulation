import { Target, Users } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import { sideResult } from '../utils/seasonSelectors'
import { COMP_SHORT, fixtureLabel, ratingTone } from '../utils/seasonUtils'

const BADGE = { win: 'V', draw: 'E', loss: 'D' }

// Uma partida sua (jogada ou por jogar). Tocar abre os "Jogos da rodada".
export default function MatchRow({ f, myClub, onOpen, highlight }) {
  const played = f.status === 'played'
  const res = sideResult(f, myClub)
  const Tag = onOpen ? 'button' : 'div'
  return (
    <Tag type={onOpen ? 'button' : undefined} className={`sn-mr ${highlight ? 'is-next' : ''}`} onClick={onOpen ? () => onOpen(f) : undefined}>
      <span className="sn-mr-meta">
        <b>{COMP_SHORT[f.comp]}</b> · {fixtureLabel(f)}
        {highlight && <em>PRÓXIMA</em>}
      </span>
      <span className="sn-mr-teams">
        <span className="t right">
          <b>{getClubById(f.home_club)?.name}</b>
          <ClubCrest clubId={f.home_club} size={22} />
        </span>
        <span className={`sn-mr-score ${res ? `r-${res}` : ''}`}>{played ? `${f.home_goals} × ${f.away_goals}` : '× '}</span>
        <span className="t">
          <ClubCrest clubId={f.away_club} size={22} />
          <b>{getClubById(f.away_club)?.name}</b>
        </span>
      </span>
      {played && f.home_pens != null && (
        <small className="sn-mr-note">
          Pênaltis: {f.home_pens} × {f.away_pens}
        </small>
      )}
      {played && f.player_match && (
        <span className="sn-mr-me">
          {res && <i className={`sn-badge r-${res}`}>{BADGE[res]}</i>}
          <i className={`sn-rate ${ratingTone(Number(f.player_rating))}`}>{Number(f.player_rating).toFixed(1)}</i>
          <span>
            <Target size={12} /> {f.player_goals}
          </span>
          <span>
            <Users size={12} /> {f.player_assists}
          </span>
        </span>
      )}
    </Tag>
  )
}
