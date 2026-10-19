import { RankingIcon } from '../../../components/ui/icons'
import useRankingRealtime from '../../predictions/hooks/useRankingRealtime'

function Entries({ entries, hidden }) {
  return (
    <div className="ranking-ticker-list" aria-hidden={hidden || undefined}>
      {entries.map((entry) => (
        <span className={`ranking-entry ${entry.position === 1 ? 'is-first' : ''}`} key={entry.id}>
          <span className="ranking-entry-pos">#{entry.position}</span>
          <strong>{entry.nickname}</strong>
          <span className="ranking-entry-pts">{entry.points.toLocaleString('pt-BR')} pts</span>
        </span>
      ))}
    </div>
  )
}

export default function RankingTicker() {
  const { entries, status } = useRankingRealtime()

  let message = null
  if (status === 'loading') message = 'Carregando ranking…'
  else if (status === 'error') message = 'Ranking indisponível no momento'
  else if (entries.length === 0) message = 'Seja o primeiro do ranking de palpites!'

  return (
    <div className="ranking-ticker">
      <span className="ranking-ticker-label">
        <RankingIcon size={13} />
        Ranking
        <span className="live-dot" aria-hidden="true" />
      </span>
      <div className="ranking-ticker-track">
        {message ? (
          <span className="ranking-ticker-empty">{message}</span>
        ) : (
          <div className="ranking-ticker-inner" style={{ '--ticker-duration': `${Math.max(18, entries.length * 4)}s` }}>
            <Entries entries={entries} />
            <Entries entries={entries} hidden />
          </div>
        )}
      </div>
    </div>
  )
}
