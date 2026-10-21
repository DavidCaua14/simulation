import { useEffect, useState } from 'react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import { fetchSeasonHistory } from '../services/seasonsApi'
import { fmt } from '../utils/seasonUtils'

function Stat({ label, value, tone }) {
  return (
    <div className={`sn-stat ${tone || ''}`}>
      <b>{fmt(value)}</b>
      <small>{label}</small>
    </div>
  )
}

// Números da carreira (a base do ranking) + histórico de temporadas + regras de prêmio.
export default function CareerPanel({ stats }) {
  const [history, setHistory] = useState([])

  useEffect(() => {
    let cancelled = false
    fetchSeasonHistory()
      .then((d) => !cancelled && setHistory(d))
      .catch(() => {})
    return () => {
      cancelled = true
    }
  }, [stats.matches, stats.seasons_played])

  const winRate = stats.matches ? Math.round((stats.wins / stats.matches) * 100) : 0

  return (
    <div className="sn-career">
      <section className="card sn-stats">
        <h3 className="heading">Carreira</h3>
        <div className="sn-stat-grid">
          <Stat label="Jogos" value={stats.matches} />
          <Stat label="Vitórias" value={stats.wins} tone="win" />
          <Stat label="Empates" value={stats.draws} />
          <Stat label="Derrotas" value={stats.losses} tone="loss" />
          <Stat label="Gols" value={stats.goals} tone="gold" />
          <Stat label="Assistências" value={stats.assists} tone="gold" />
          <Stat label="Títulos" value={stats.titles} tone="gold" />
          <Stat label="Temporadas" value={stats.seasons_played} />
        </div>
        <p className="sn-hint">Aproveitamento: {winRate}% de vitórias.</p>
      </section>

      <section className="card sn-rules">
        <h3 className="heading">Como ganhar XP e moedas</h3>
        <ul>
          <li>Vitória 30 XP · empate 15 · derrota 8 (e moedas na mesma proporção).</li>
          <li>Cada gol seu +10 XP · cada assistência +6 XP.</li>
          <li>Copa do Brasil rende x1,2 e a Libertadores x1,3; mata-mata e final valem ainda mais.</li>
          <li>Terminar um campeonato bem (título, G4, fases avançadas) dá um bônus extra.</li>
          <li>A cada 1.000 XP você sobe de nível, e nível alto melhora seu desempenho em campo.</li>
        </ul>
      </section>

      {history.length > 0 && (
        <section className="card sn-history">
          <h3 className="heading">Temporadas</h3>
          {history.map((s) => (
            <div key={s.id} className="sn-hist-row">
              <ClubCrest clubId={s.club_id} size={28} />
              <div>
                <b>
                  {s.year} · {getClubById(s.club_id)?.name}
                </b>
                <small>
                  {s.matches} jogos · {s.wins}V {s.draws}E {s.losses}D · {s.goals} gols · {s.assists} assist.
                  {s.status === 'active' ? ' · em andamento' : ''}
                </small>
              </div>
            </div>
          ))}
        </section>
      )}
    </div>
  )
}
