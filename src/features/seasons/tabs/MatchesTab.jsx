import { useState } from 'react'
import MatchRow from '../components/MatchRow'
import { COMP_ORDER, COMP_SHORT } from '../utils/seasonUtils'

// JOGOS: histórico completo (resultados) e calendário (próximos jogos). Tocar num resultado abre a rodada.
export default function MatchesTab({ ctx, onOpenRound }) {
  const { history, upcoming, myClub } = ctx
  const [view, setView] = useState('results')
  const [filter, setFilter] = useState('all')

  const source = view === 'results' ? history : upcoming
  const list = filter === 'all' ? source : source.filter((f) => f.comp === filter)
  const nextId = upcoming[0]?.id

  return (
    <div className="sn-page">
      <div className="sn-seg">
        <button type="button" className={view === 'results' ? 'is-on' : ''} onClick={() => setView('results')}>
          Resultados <em className="plain">{history.length}</em>
        </button>
        <button type="button" className={view === 'upcoming' ? 'is-on' : ''} onClick={() => setView('upcoming')}>
          Calendário
        </button>
      </div>

      <div className="sn-chipbar" role="tablist" aria-label="Filtrar por campeonato">
        {['all', ...COMP_ORDER].map((id) => (
          <button key={id} type="button" className={filter === id ? 'is-on' : ''} onClick={() => setFilter(id)}>
            {id === 'all' ? 'Todos' : COMP_SHORT[id]}
          </button>
        ))}
      </div>

      {list.length === 0 ? (
        <div className="sn-empty card">
          <p>{view === 'results' ? 'Você ainda não jogou nenhuma partida.' : 'Sem jogos programados.'}</p>
          <small>{view === 'results' ? 'Volte ao Início e jogue sua primeira partida.' : 'Os próximos jogos do mata-mata aparecem conforme você avança.'}</small>
        </div>
      ) : (
        <div className="sn-stack">
          {list.map((f) => (
            <MatchRow key={f.id} f={f} myClub={myClub} onOpen={view === 'results' ? onOpenRound : undefined} highlight={view === 'upcoming' && f.id === nextId} />
          ))}
        </div>
      )}
      {view === 'upcoming' && <p className="sn-hint">A ordem dos jogos intercala os campeonatos. O Início sempre mostra o próximo.</p>}
    </div>
  )
}
