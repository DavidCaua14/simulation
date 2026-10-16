import { useEffect, useState } from 'react'
import { fetchLeaderboard } from '../services/predictionsApi'

const MEDALS = ['🥇', '🥈', '🥉']

export default function LeaderboardSection({ nickname }) {
  const [rows, setRows] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    fetchLeaderboard()
      .then(setRows)
      .catch(() => setError('Não foi possível carregar o ranking.'))
      .finally(() => setLoading(false))
  }, [])

  return (
    <div className="pred-list">
      <p className="pred-hint">
        Ranking por pontos de palpites. Só aparece quem já ganhou algum bilhete — e bilhetes com mais
        jogos e multiplicador maior valem mais pontos.
      </p>
      {loading && <p className="pred-empty">Carregando…</p>}
      {!loading && error && <p className="pred-empty">{error}</p>}
      {!loading && !error && rows.length === 0 && (
        <p className="pred-empty">Ninguém pontuou ainda. Seja o primeiro! 🏆</p>
      )}
      {rows.map((r) => {
        const me = nickname && r.nickname.toLowerCase() === nickname.toLowerCase()
        return (
          <div key={r.career_id} className={`pred-rank card ${me ? 'is-me' : ''}`}>
            <span className="pred-rank-pos">{MEDALS[r.position - 1] || `${r.position}º`}</span>
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
