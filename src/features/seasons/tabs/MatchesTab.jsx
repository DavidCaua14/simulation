import { useState } from 'react'
import MatchRow from '../components/MatchRow'
import CalendarRow from '../components/CalendarRow'
import { COMP_ORDER, COMP_SHORT } from '../utils/seasonUtils'

// JOGOS: histórico completo (resultados) e calendário (próximos jogos). Tocar num resultado abre a rodada.
export default function MatchesTab({ ctx, onOpenRound }) {
  const { history, calendar, myClub } = ctx
  const [view, setView] = useState('results')
  const [filter, setFilter] = useState('all')

  const source = view === 'results' ? history : calendar
  const list = filter === 'all' ? source : source.filter((f) => f.comp === filter)

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
          {view === 'results'
            ? list.map((f) => <MatchRow key={f.id} f={f} myClub={myClub} onOpen={onOpenRound} />)
            : list.map((e) => <CalendarRow key={`${e.comp}-${e.stage}-${e.round}`} event={e} myClub={myClub} highlight={e === calendar[0]} />)}
        </div>
      )}
      {view === 'upcoming' && (
        <p className="sn-hint">
          Os campeonatos se intercalam. Nos dias em que seu clube não joga, o botão "Próximo" no Início simula a rodada, sem gastar energia.
        </p>
      )}
    </div>
  )
}
