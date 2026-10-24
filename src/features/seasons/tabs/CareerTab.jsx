import { useEffect, useState } from 'react'
import CareerHero from '../components/CareerHero'
import CareerStats from '../components/CareerStats'
import TrophyCabinet from '../components/TrophyCabinet'
import SeasonHistory from '../components/SeasonHistory'
import RewardsGuide from '../components/RewardsGuide'
import { fetchSeasonHistory } from '../services/seasonsApi'

const VIEWS = [
  { id: 'summary', label: 'Resumo' },
  { id: 'history', label: 'Histórico' },
  { id: 'evolve', label: 'Evolução' },
]

// CARREIRA: destaque do atleta e três áreas reais — resumo (desempenho + troféus), histórico de temporadas
// e evolução (como ganhar XP, moedas e bônus).
export default function CareerTab({ ctx, onRecharged }) {
  const { hub } = ctx
  const [view, setView] = useState('summary')
  const [history, setHistory] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let cancelled = false
    fetchSeasonHistory()
      .then((d) => !cancelled && setHistory(d || []))
      .catch(() => {})
      .finally(() => !cancelled && setLoading(false))
    return () => {
      cancelled = true
    }
  }, [hub.stats.matches, hub.stats.seasons_played])

  return (
    <div className="sn-page">
      <CareerHero career={hub.career} stats={hub.stats} season={hub.season} onRecharged={onRecharged} />

      <div className="sn-seg" role="tablist" aria-label="Áreas da carreira">
        {VIEWS.map((v) => (
          <button key={v.id} type="button" role="tab" aria-selected={view === v.id} className={view === v.id ? 'is-on' : ''} onClick={() => setView(v.id)}>
            {v.label}
          </button>
        ))}
      </div>

      {view === 'summary' && (
        <>
          <section className="sn-sec">
            <h2 className="gx-title">
              Desempenho <small>{hub.stats.seasons_played} temporada{hub.stats.seasons_played === 1 ? '' : 's'} completa{hub.stats.seasons_played === 1 ? '' : 's'}</small>
            </h2>
            <CareerStats stats={hub.stats} />
          </section>
          <section className="sn-sec">
            <h2 className="gx-title">Conquistas</h2>
            <TrophyCabinet history={history} titles={hub.stats.titles} />
          </section>
        </>
      )}
      {view === 'history' && <SeasonHistory history={history} loading={loading} />}
      {view === 'evolve' && <RewardsGuide career={hub.career} />}
    </div>
  )
}
