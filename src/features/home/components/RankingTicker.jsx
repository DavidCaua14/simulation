import { useEffect, useState } from 'react'
import { Trophy } from 'lucide-react'
import { fetchRanking } from '../../ranking/rankingApi'

// Ranking geral dos treinadores (nível, Temporadas, reputação, eventos). Atualiza a cada minuto.
function useCoachRanking() {
  const [state, setState] = useState({ entries: [], me: null, status: 'loading' })
  useEffect(() => {
    let alive = true
    const load = () => fetchRanking(10)
      .then((d) => { if (alive) setState({ entries: d?.entries || [], me: d?.me || null, status: 'ready' }) })
      .catch(() => { if (alive) setState((s) => ({ ...s, status: s.entries.length ? 'ready' : 'error' })) })
    load()
    const timer = setInterval(() => { if (!document.hidden) load() }, 60000)
    return () => { alive = false; clearInterval(timer) }
  }, [])
  return state
}

function Entries({ entries, me, hidden }) {
  return (
    <div className="hm-rank-list" aria-hidden={hidden || undefined}>
      {entries.map((entry) => (
        <span className={`hm-rank-entry ${entry.position <= 3 ? `is-top${entry.position}` : ''} ${entry.is_me || entry.nickname === me ? 'is-me' : ''}`} key={entry.position}>
          <b>#{entry.position}</b>
          <strong>{entry.nickname}</strong>
          <span>{entry.points.toLocaleString('pt-BR')} pts</span>
        </span>
      ))}
    </div>
  )
}

// Faixa da tela inicial: top 10 do ranking geral + a sua posição (mesmo fora do top 10).
export default function RankingTicker({ me, onOpen }) {
  const { entries, me: mine, status } = useCoachRanking()

  let message = null
  if (status === 'loading') message = 'Carregando ranking…'
  else if (status === 'error') message = 'Ranking indisponível no momento'
  else if (entries.length === 0) message = 'Jogue e evolua para entrar no ranking!'

  return (
    <div className="hm-rank">
      <button type="button" className="hm-rank-me" onClick={onOpen} aria-label="Ver ranking dos treinadores">
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
