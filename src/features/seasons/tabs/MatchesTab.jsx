import { useState } from 'react'
import { CalendarDays, History } from 'lucide-react'
import MatchRow from '../components/MatchRow'
import CalendarRow from '../components/CalendarRow'
import CompEmblem from '../ui/CompEmblem'
import { EmptyState } from '../ui/States'
import { COMP_ORDER, COMP_SHORT, seasonLabel } from '../utils/seasonUtils'

// JOGOS: resultados (tudo o que você comandou, inclusive em clubes anteriores) e calendário.
// Tocar num resultado abre a súmula da partida.
export default function MatchesTab({ ctx, onOpenReport }) {
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
          <small>Temporada {seasonLabel(season.year, season.region)}</small>
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
          <EmptyState icon={History} title="Nenhum resultado ainda" text="Volte ao Início e comande seu time na primeira partida." />
        ) : (
          <EmptyState icon={CalendarDays} title="Sem jogos programados" text="Os jogos do mata-mata aparecem conforme os confrontos são definidos." />
        )
      ) : view === 'results' ? (
        <div className="sn-stack">
          {list.map((f) => (
            <MatchRow key={f.id} f={f} myClub={myClub} onOpen={onOpenReport} />
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
        <p className="sn-hint">Os campeonatos se intercalam. Nos dias sem jogo do seu clube, "Avançar" no Início simula as rodadas sem gastar energia — e o elenco recupera a condição física.</p>
      )}
    </div>
  )
}
