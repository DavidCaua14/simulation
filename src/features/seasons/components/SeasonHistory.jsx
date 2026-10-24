import { History } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import CompEmblem from '../ui/CompEmblem'
import { EmptyState } from '../ui/States'
import { fmt } from '../utils/seasonUtils'

// Linha do tempo das temporadas (mais recente primeiro), com clube, campanha e prêmios.
export default function SeasonHistory({ history, loading }) {
  if (loading && !history.length) return <p className="sn-muted sn-center">Carregando histórico…</p>
  if (!history.length) return <EmptyState icon={History} title="Sem temporadas ainda" text="Sua primeira temporada aparece aqui assim que começar." />
  return (
    <ol className="sh-list">
      {history.map((s) => {
        const club = getClubById(s.club_id)
        return (
          <li key={s.id} className={`shc ${s.status === 'active' ? 'is-active' : ''}`} style={{ '--c1': club?.colors?.[0] || '#33415c' }}>
            <div className="shc-head">
              <ClubCrest clubId={s.club_id} size={34} />
              <div>
                <b>
                  {s.year} · {club?.name}
                </b>
                <small>{s.status === 'active' ? 'Em andamento' : `Temporada ${s.season_no}`}</small>
              </div>
              {s.status === 'active' && <span className="gx-tag is-live">Atual</span>}
            </div>
            <div className="shc-stats">
              <span>
                <b>{s.matches}</b> jogos
              </span>
              <span className="w">
                <b>{s.wins}</b>V
              </span>
              <span className="d">
                <b>{s.draws}</b>E
              </span>
              <span className="l">
                <b>{s.losses}</b>D
              </span>
              <span>
                <b>{s.goals}</b> gols
              </span>
              <span>
                <b>{s.assists}</b> assist.
              </span>
            </div>
            {(s.summary || []).length > 0 && (
              <ul className="shc-comps">
                {s.summary.map((x) => (
                  <li key={x.competition} className={x.player_result === 'Campeão' ? 'is-title' : ''}>
                    <CompEmblem comp={x.competition} size={16} />
                    <span>{x.player_result || 'Não disputou'}</span>
                  </li>
                ))}
              </ul>
            )}
            <div className="shc-earn">
              +{fmt(s.xp_earned)} XP · +{fmt(s.coins_earned)} moedas
            </div>
          </li>
        )
      })}
    </ol>
  )
}
