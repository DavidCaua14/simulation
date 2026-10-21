import { Target, Users } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import { STAGE_LABEL, ratingTone, resultOf } from '../utils/seasonUtils'

function label(f) {
  if (f.stage === 'league') return `Rodada ${f.round_no}`
  if (f.stage === 'group') return `Grupo ${f.group_label} · R${f.round_no}`
  if (f.stage === 'final') return 'Final'
  return `${STAGE_LABEL[f.stage]} · ${f.leg === 1 ? 'Ida' : 'Volta'}`
}

// Todos os jogos do SEU clube no campeonato, com o seu desempenho nas partidas simuladas.
export default function FixtureList({ fixtures, myClub }) {
  const mine = fixtures.filter((f) => f.home_club === myClub || f.away_club === myClub)
  if (!mine.length) return <p className="sn-muted">Seu clube ainda não tem jogos aqui.</p>
  const nextId = mine.find((f) => f.status === 'pending')?.id

  return (
    <ul className="sn-fixtures">
      {mine.map((f) => {
        const home = f.home_club === myClub
        const played = f.status === 'played'
        const res = played ? resultOf(home ? f.home_goals : f.away_goals, home ? f.away_goals : f.home_goals) : null
        return (
          <li key={f.id} className={`sn-fx ${f.id === nextId ? 'is-next' : ''}`}>
            <span className="sn-fx-label">{label(f)}</span>
            <div className="sn-fx-row">
              <span className="sn-fx-team right">
                <b>{getClubById(f.home_club)?.name}</b>
                <ClubCrest clubId={f.home_club} size={22} />
              </span>
              <span className={`sn-fx-score ${res ? `r-${res}` : ''}`}>
                {played ? `${f.home_goals} × ${f.away_goals}` : f.id === nextId ? 'próximo' : '—'}
              </span>
              <span className="sn-fx-team">
                <ClubCrest clubId={f.away_club} size={22} />
                <b>{getClubById(f.away_club)?.name}</b>
              </span>
            </div>
            {played && f.home_pens != null && (
              <small className="sn-fx-note">
                Pênaltis: {f.home_pens} × {f.away_pens}
              </small>
            )}
            {played && f.player_match && (
              <div className="sn-fx-me">
                <span className={`sn-rate ${ratingTone(Number(f.player_rating))}`}>{Number(f.player_rating).toFixed(1)}</span>
                <span title="Gols">
                  <Target size={12} /> {f.player_goals}
                </span>
                <span title="Assistências">
                  <Users size={12} /> {f.player_assists}
                </span>
              </div>
            )}
          </li>
        )
      })}
    </ul>
  )
}
