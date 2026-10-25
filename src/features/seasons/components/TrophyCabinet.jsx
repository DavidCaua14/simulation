import { Trophy } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import CompEmblem from '../ui/CompEmblem'
import { COMP_NAME } from '../utils/seasonUtils'

// Sala de troféus: títulos e campanhas de destaque tirados do resumo das temporadas encerradas.
export default function TrophyCabinet({ history, titles }) {
  const items = history
    .filter((s) => s.status === 'finished')
    .flatMap((s) => (Array.isArray(s.summary) ? s.summary : s.summary?.competitions || []).filter((x) => x.player_result).map((x) => ({ ...x, year: s.year, club: x.player_club || s.club_id })))
  const wins = items.filter((x) => x.player_result === 'Campeão')
  const podium = items.filter((x) => x.player_result === 'Vice-campeão' || /^[234]º lugar$/.test(x.player_result || ''))

  return (
    <section className="tc">
      <div className="tc-shelf">
        {wins.length ? (
          wins.map((x) => (
            <div key={`${x.year}-${x.competition}`} className="tc-cup">
              <span className="tc-cup-icon">
                <Trophy size={30} />
              </span>
              <CompEmblem comp={x.competition} size={18} />
              <b>{COMP_NAME[x.competition]}</b>
              <small>
                <ClubCrest clubId={x.club} size={12} /> {x.year}
              </small>
            </div>
          ))
        ) : (
          <div className="tc-empty">
            <span className="tc-cup-icon is-empty">
              <Trophy size={30} />
            </span>
            <b>{titles > 0 ? `${titles} título${titles > 1 ? 's' : ''} na carreira` : 'Prateleira esperando a primeira taça'}</b>
            <small>Títulos aparecem aqui ao fim de cada temporada.</small>
          </div>
        )}
      </div>
      {podium.length > 0 && (
        <ul className="tc-podium">
          {podium.map((x) => (
            <li key={`${x.year}-${x.competition}`}>
              <CompEmblem comp={x.competition} size={16} />
              <span>
                {COMP_NAME[x.competition]} {x.year}
              </span>
              <b>{x.player_result}</b>
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}
