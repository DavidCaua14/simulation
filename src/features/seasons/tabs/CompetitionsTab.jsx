import { useMemo, useState } from 'react'
import { ChevronLeft, ChevronRight, Trophy } from 'lucide-react'
import StandingsTable from '../components/StandingsTable'
import Bracket from '../components/Bracket'
import RoundResults from '../components/RoundResults'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import CompEmblem from '../ui/CompEmblem'
import { compStatus } from '../utils/compStatus'
import { EXPECTED_MATCHES, buildRounds, defaultRoundIndex, groupOf, standingsFrom } from '../utils/seasonSelectors'
import { COMP_NAME, COMP_ORDER, COMP_SHORT, COMP_THEME } from '../utils/seasonUtils'

const VIEWS = {
  brasileirao: [
    { id: 'table', label: 'Tabela' },
    { id: 'rounds', label: 'Rodadas' },
  ],
  copa_brasil: [
    { id: 'bracket', label: 'Chaveamento' },
    { id: 'rounds', label: 'Rodadas' },
  ],
  libertadores: [
    { id: 'table', label: 'Grupos' },
    { id: 'bracket', label: 'Mata-mata' },
    { id: 'rounds', label: 'Rodadas' },
  ],
}

function RoundBrowser({ fixtures, myClub, lastKey }) {
  const rounds = useMemo(() => buildRounds(fixtures), [fixtures])
  const [idx, setIdx] = useState(() => defaultRoundIndex(rounds, lastKey))
  if (!rounds.length) return <p className="sn-muted sn-center">Sem rodadas ainda.</p>
  const i = Math.min(idx, rounds.length - 1)
  const r = rounds[i]
  return (
    <div>
      <div className="rb-nav">
        <button type="button" onClick={() => setIdx(i - 1)} disabled={i <= 0} aria-label="Rodada anterior">
          <ChevronLeft size={20} />
        </button>
        <div>
          <b>{r.label}</b>
          <small className={r.done ? '' : 'is-open'}>{r.done ? 'Encerrada' : 'Em aberto'}</small>
        </div>
        <button type="button" onClick={() => setIdx(i + 1)} disabled={i >= rounds.length - 1} aria-label="Próxima rodada">
          <ChevronRight size={20} />
        </button>
      </div>
      <RoundResults matches={r.matches} myClub={myClub} />
    </div>
  )
}

function CompetitionView({ comp, fixtures, myClub, lastKey }) {
  const views = VIEWS[comp.id]
  const [view, setView] = useState(views[0].id)
  const [group, setGroup] = useState(() => groupOf(fixtures, myClub) || 'A')
  const groups = useMemo(() => [...new Set(fixtures.filter((f) => f.group_label).map((f) => f.group_label))].sort(), [fixtures])
  const rows = useMemo(
    () => (comp.id === 'brasileirao' ? standingsFrom(fixtures) : comp.id === 'libertadores' ? standingsFrom(fixtures, group) : []),
    [comp.id, fixtures, group],
  )

  return (
    <>
      <div className="sn-seg">
        {views.map((v) => (
          <button key={v.id} type="button" className={view === v.id ? 'is-on' : ''} onClick={() => setView(v.id)}>
            {v.label}
          </button>
        ))}
      </div>

      {view === 'table' && (
        <>
          {comp.id === 'libertadores' && (
            <div className="sn-groups" role="tablist" aria-label="Grupos">
              {groups.map((g) => (
                <button key={g} type="button" className={g === group ? 'is-on' : ''} onClick={() => setGroup(g)}>
                  {g}
                </button>
              ))}
            </div>
          )}
          <StandingsTable rows={rows} myClub={myClub} mode={comp.id === 'libertadores' ? 'group' : 'league'} />
        </>
      )}
      {view === 'bracket' && <Bracket fixtures={fixtures} myClub={myClub} />}
      {view === 'rounds' && <RoundBrowser key={comp.id} fixtures={fixtures} myClub={myClub} lastKey={lastKey} />}
    </>
  )
}

// TORNEIOS: acompanhar tabela, grupos, chaveamento e rodadas de cada campeonato (só leitura).
export default function CompetitionsTab({ ctx, selected, onSelect }) {
  const { hub, byComp, history, myClub } = ctx
  const comp = hub.competitions.find((c) => c.id === selected) || hub.competitions[0]
  const last = history.find((f) => f.comp === comp.id)
  const lastKey = last ? `${last.stage}:${last.round_no}` : null

  const t = COMP_THEME[comp.id]
  const st = compStatus(comp)
  const inactive = comp.status === 'not_in' || comp.status === 'out'
  const pct = Math.min(100, (comp.played / (EXPECTED_MATCHES[comp.id] || comp.total || 1)) * 100)

  return (
    <div className="sn-page">
      <div className="ct-picker" role="tablist" aria-label="Campeonatos">
        {COMP_ORDER.map((id) => (
          <button key={id} type="button" role="tab" aria-selected={comp.id === id} className={comp.id === id ? 'is-on' : ''} style={{ '--c1': COMP_THEME[id].c1, '--c2': COMP_THEME[id].c2 }} onClick={() => onSelect(id)}>
            <CompEmblem comp={id} size={26} />
            <span>{COMP_SHORT[id]}</span>
          </button>
        ))}
      </div>

      <section className={`ct-banner ${inactive ? 'is-inactive' : ''}`} style={{ '--c1': t.c1, '--c2': t.c2 }}>
        <CompEmblem comp={comp.id} size={58} dim={inactive} />
        <div className="ct-banner-txt">
          <small>{t.kicker}</small>
          <h2>{COMP_NAME[comp.id]}</h2>
          <span className="ct-line">{st.line}</span>
          <span className="ct-goal">
            {comp.status === 'finished' && comp.champion ? (
              <>
                <Trophy size={13} /> Campeão: <ClubCrest clubId={comp.champion} size={16} /> {getClubById(comp.champion)?.name}
              </>
            ) : (
              <>→ {st.goal}</>
            )}
          </span>
          {!inactive && comp.status !== 'finished' && (
            <span className="ct-bar" aria-label={`${comp.played} jogos disputados`}>
              <i style={{ width: `${pct}%` }} />
            </span>
          )}
        </div>
      </section>

      <CompetitionView key={comp.id} comp={comp} fixtures={byComp[comp.id] || []} myClub={myClub} lastKey={lastKey} />
    </div>
  )
}
