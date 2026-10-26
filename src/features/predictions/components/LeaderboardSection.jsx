import { useEffect, useState } from 'react'
import { fetchLeaderboard, fetchMyRank } from '../services/predictionsApi'
import { formatMult } from '../data/predictionRules'
import { MedalIcon } from './PredIcons'
import { Skeleton } from '../../../components/ui/feedback'

export default function LeaderboardSection({ nickname }) {
  const [rows, setRows] = useState([])
  const [mine, setMine] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    Promise.all([fetchLeaderboard(), fetchMyRank().catch(() => null)])
      .then(([list, rank]) => {
        setRows(list)
        setMine(rank)
      })
      .catch(() => setError('Não foi possível carregar o ranking.'))
      .finally(() => setLoading(false))
  }, [])

  return (
    <div className="pred-list">
      {!loading && !error && (
        <div className="pred-mine">
          {mine ? (
            <>
              <span className="pred-mine-pos">{mine.position}º</span>
              <div>
                <strong>Sua posição</strong>
                <small>{mine.points} pts · maior odd {formatMult(Number(mine.best_multiplier))}</small>
              </div>
            </>
          ) : (
            <p>Ganhe seu primeiro bilhete para entrar no ranking.</p>
          )}
        </div>
      )}
      <p className="pred-hint">
        Ranking por pontos de palpites. Só aparece quem já ganhou algum bilhete, e odds maiores valem mais pontos.
      </p>
      {loading && <Skeleton rows={5} variant="line" />}
      {!loading && error && <p className="pred-empty">{error}</p>}
      {!loading && !error && rows.length === 0 && <p className="pred-empty">Ninguém pontuou ainda. Seja o primeiro!</p>}
      {rows.map((r) => {
        const me = nickname && r.nickname.toLowerCase() === nickname.toLowerCase()
        return (
          <div key={r.career_id} className={`pred-rank ${me ? 'is-me' : ''} ${r.position <= 3 ? `top top${r.position}` : ''}`}>
            <span className="pred-rank-pos">{r.position <= 3 ? <MedalIcon position={r.position} /> : `${r.position}º`}</span>
            <div>
              <strong>{r.nickname}{me ? ' (você)' : ''}</strong>
              <small>Nível {r.level} · {r.tickets_won} bilhete(s) ganho(s)</small>
            </div>
            <b>{r.points} pts</b>
          </div>
        )
      })}
    </div>
  )
}
