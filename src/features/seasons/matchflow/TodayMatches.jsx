import { useEffect, useState } from 'react'
import { Play } from 'lucide-react'
import { getClubById } from '../../club/data/clubs'
import { Jersey } from '../components/Pitch'
import { fetchCareerCalendar } from '../services/managerApi'
import { COMP_NAME, roundTitle } from '../utils/seasonUtils'
import { isSessionError } from '../../../lib/sessionRecovery'

// PARTIDAS DE HOJE (CM17): todos os jogos da rodada, com as camisas dos clubes, antes de ir para a escalação.
export default function TodayMatches({ next, myClub, onPlay }) {
  const [rows, setRows] = useState(null)
  useEffect(() => {
    let alive = true
    const mine = [{ id: next.fixture_id, home_club: next.match.home, away_club: next.match.away }]
    fetchCareerCalendar('competition', next.competition)
      .then((list) => {
        if (!alive) return
        const round = (list || []).filter((f) => f.stage === next.stage && f.round_no === next.round && (!next.match.group || f.group_label === next.match.group || next.stage !== 'group'))
        setRows(round.length ? round : mine)
      })
      .catch((e) => alive && !isSessionError(e) && setRows(mine))
    return () => {
      alive = false
    }
  }, [next])

  const name = (id) => getClubById(id)?.name || id
  const ordered = rows ? [...rows].sort((a, b) => (b.home_club === myClub || b.away_club === myClub) - (a.home_club === myClub || a.away_club === myClub)) : []
  return (
    <div className="td">
      <h2 className="cm-screen-title">Partidas de hoje</h2>
      <p className="td-sub">
        {COMP_NAME[next.competition] || next.competition} · {roundTitle(next.stage, next.round, next.competition)}
      </p>
      {!rows ? (
        <div className="st-sk hero" />
      ) : (
        <table className="td-table">
          <thead>
            <tr>
              <th>Início</th>
              <th>Placar</th>
              <th>Vis.</th>
            </tr>
          </thead>
          <tbody>
            {ordered.map((f) => {
              const mine = f.home_club === myClub || f.away_club === myClub
              const played = f.status === 'played'
              return (
                <tr key={f.id} className={mine ? 'is-mine' : ''}>
                  <td className="td-home">
                    <span>{name(f.home_club)}</span>
                    <i className="td-kit">
                      <Jersey colors={getClubById(f.home_club)?.colors} />
                    </i>
                  </td>
                  <td className="td-score">{played ? `${f.home_goals} - ${f.away_goals}` : 'V'}</td>
                  <td className="td-away">
                    <i className="td-kit">
                      <Jersey colors={getClubById(f.away_club)?.colors} />
                    </i>
                    <span>{name(f.away_club)}</span>
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      )}
      <button type="button" className="gx-btn td-play" onClick={onPlay}>
        <Play size={17} fill="currentColor" /> Jogar
      </button>
    </div>
  )
}
