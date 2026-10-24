import { Trophy } from 'lucide-react'
import useRankingRealtime from '../../predictions/hooks/useRankingRealtime'

function Entries({ entries, me, hidden }) {
  return (
    <div className="hm-rank-list" aria-hidden={hidden || undefined}>
      {entries.map((entry) => (
        <span className={`hm-rank-entry ${entry.position <= 3 ? `is-top${entry.position}` : ''} ${entry.nickname === me ? 'is-me' : ''}`} key={entry.id}>
          <b>#{entry.position}</b>
          <strong>{entry.nickname}</strong>
          <span>{entry.points.toLocaleString('pt-BR')} pts</span>
        </span>
      ))}
    </div>
  )
}

// Ranking de palpites ao vivo + a posição do próprio jogador (se estiver no top 10).
export default function RankingTicker({ me, onOpen }) {
  const { entries, status } = useRankingRealtime()
  const mine = entries.find((e) => e.nickname === me)

  let message = null
  if (status === 'loading') message = 'Carregando ranking…'
  else if (status === 'error') message = 'Ranking indisponível no momento'
  else if (entries.length === 0) message = 'Seja o primeiro do ranking de palpites!'

  return (
    <div className="hm-rank">
      <button type="button" className="hm-rank-me" onClick={onOpen} aria-label="Ver ranking de palpites">
        <Trophy size={16} />
        <span>
          <small>Ranking</small>
          <b>{mine ? `#${mine.position}` : '—'}</b>
        </span>
      </button>
      <div className="hm-rank-track">
        {message ? (
          <span className="hm-rank-empty">{message}</span>
        ) : (
          <div className="hm-rank-inner" style={{ '--ticker-duration': `${Math.max(18, entries.length * 4)}s` }}>
            <Entries entries={entries} me={me} />
            <Entries entries={entries} me={me} hidden />
          </div>
        )}
      </div>
    </div>
  )
}
