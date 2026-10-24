import { useState } from 'react'
import { CalendarDays, History } from 'lucide-react'
import MatchRow from '../components/MatchRow'
import CalendarRow from '../components/CalendarRow'
import CompEmblem from '../ui/CompEmblem'
import { EmptyState } from '../ui/States'
import { COMP_ORDER, COMP_SHORT } from '../utils/seasonUtils'

// JOGOS: resultados (tudo o que você jogou) e calendário (o que vem pela frente). Tocar num resultado abre a rodada.
export default function MatchesTab({ ctx, onOpenRound }) {
  const { history, calendar, myClub } = ctx
  const [view, setView] = useState('results')
  const [filter, setFilter] = useState('all')

  const source = view === 'results' ? history : calendar
  const list = filter === 'all' ? source : source.filter((f) => f.comp === filter)
  const season = ctx.hub.season

  return (
    <div className="sn-page">
      <div className="sn-seg" role="tablist">
        <button type="button" role="tab" aria-selected={view === 'results'} className={view === 'results' ? 'is-on' : ''} onClick={() => setView('results')}>
          <History size={15} /> Resultados <em>{history.length}</em>
        </button>
        <button type="button" role="tab" aria-selected={view === 'upcoming'} className={view === 'upcoming' ? 'is-on' : ''} onClick={() => setView('upcoming')}>
          <CalendarDays size={15} /> Calendário
        </button>
      </div>

      <div className="sn-chips" role="tablist" aria-label="Filtrar por campeonato">
        {['all', ...COMP_ORDER].map((id) => (
          <button key={id} type="button" className={filter === id ? 'is-on' : ''} onClick={() => setFilter(id)}>
            {id !== 'all' && <CompEmblem comp={id} size={14} />}
            {id === 'all' ? 'Todos' : COMP_SHORT[id]}
          </button>
        ))}
      </div>

      {view === 'results' && history.length > 0 && (
        <div className="mt-record" aria-label="Sua campanha nesta temporada">
          <small>Temporada {season.year}</small>
          <span className="w">
            <b>{season.wins}</b> V
          </span>
          <span className="d">
            <b>{season.draws}</b> E
          </span>
          <span className="l">
            <b>{season.losses}</b> D
          </span>
        </div>
      )}

      {list.length === 0 ? (
        view === 'results' ? (
          <EmptyState icon={History} title="Nenhum resultado ainda" text="Volte ao Início e jogue sua primeira partida." />
        ) : (
          <EmptyState icon={CalendarDays} title="Sem jogos programados" text="Os jogos do mata-mata aparecem conforme os confrontos são definidos." />
        )
      ) : view === 'results' ? (
        <div className="sn-stack">
          {list.map((f) => (
            <MatchRow key={f.id} f={f} myClub={myClub} onOpen={onOpenRound} />
          ))}
        </div>
      ) : (
        <ol className="tl">
          {list.map((e) => (
            <li key={`${e.comp}-${e.stage}-${e.round}`} className={`tl-item ${e === calendar[0] ? 'is-now' : 'is-future'}`}>
              <CalendarRow event={e} myClub={myClub} highlight={e === calendar[0]} />
            </li>
          ))}
        </ol>
      )}
      {view === 'upcoming' && list.length > 0 && (
        <p className="sn-hint">Os campeonatos se intercalam. Nos dias de folga do seu clube, o botão "Avançar" no Início simula a rodada sem gastar energia.</p>
      )}
    </div>
  )
}
