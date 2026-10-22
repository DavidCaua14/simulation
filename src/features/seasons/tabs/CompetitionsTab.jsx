import { useMemo, useState } from 'react'
import { ChevronLeft, ChevronRight } from 'lucide-react'
import StandingsTable from '../components/StandingsTable'
import Bracket from '../components/Bracket'
import RoundResults from '../components/RoundResults'
import { getClubById } from '../../club/data/clubs'
import { buildRounds, defaultRoundIndex, groupOf, standingsFrom } from '../utils/seasonSelectors'
import { COMP_NAME, COMP_ORDER, COMP_SHORT, STAGE_LABEL, ordinal } from '../utils/seasonUtils'

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
  if (!rounds.length) return <p className="sn-muted">Sem rodadas ainda.</p>
  const i = Math.min(idx, rounds.length - 1)
  const r = rounds[i]
  return (
    <div>
      <div className="sn-rb-nav">
        <button type="button" onClick={() => setIdx(i - 1)} disabled={i <= 0} aria-label="Rodada anterior">
          <ChevronLeft size={20} />
        </button>
        <div>
          <b>{r.label}</b>
          <small>{r.done ? 'Encerrada' : 'Em aberto'}</small>
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
            <div className="sn-groups">
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

function statusLine(c) {
  if (c.status === 'finished') return `Sua campanha: ${c.player_result || 'encerrado'}`
  if (c.status === 'out') return 'Seu clube foi eliminado'
  if (c.status === 'not_in') return 'Seu clube não disputa este torneio'
  const t = c.table
  return `${STAGE_LABEL[c.stage]}${t ? ` · ${t.group ? `Grupo ${t.group} · ` : ''}${ordinal(t.pos)} · ${t.points} pts` : ''}`
}

// TORNEIOS: acompanhar tabela, grupos, chaveamento e rodadas de cada campeonato (só leitura).
export default function CompetitionsTab({ ctx, selected, onSelect }) {
  const { hub, byComp, history, myClub } = ctx
  const comp = hub.competitions.find((c) => c.id === selected) || hub.competitions[0]
  const last = history.find((f) => f.comp === comp.id)
  const lastKey = last ? `${last.stage}:${last.round_no}` : null

  return (
    <div className="sn-page">
      <div className="sn-chipbar">
        {COMP_ORDER.map((id) => (
          <button key={id} type="button" className={comp.id === id ? 'is-on' : ''} onClick={() => onSelect(id)}>
            {COMP_SHORT[id]}
          </button>
        ))}
      </div>

      <div className={`sn-campaign card tone-${comp.id}`}>
        <b>{COMP_NAME[comp.id]}</b>
        <span>{statusLine(comp)}</span>
        {comp.status === 'finished' && comp.champion && <small>Campeão da edição: {getClubById(comp.champion)?.name}</small>}
      </div>

      <CompetitionView key={comp.id} comp={comp} fixtures={byComp[comp.id] || []} myClub={myClub} lastKey={lastKey} />
    </div>
  )
}
