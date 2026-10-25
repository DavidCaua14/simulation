import { useEffect, useMemo, useState } from 'react'
import { ChevronLeft, ChevronRight, Trophy } from 'lucide-react'
import StandingsTable from '../components/StandingsTable'
import Bracket from '../components/Bracket'
import RoundResults from '../components/RoundResults'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import CompEmblem from '../ui/CompEmblem'
import { compStatus } from '../utils/compStatus'
import { EXPECTED_MATCHES, buildRounds, defaultRoundIndex, groupOf } from '../utils/seasonSelectors'
import useStandings from '../hooks/useStandings'
import { fetchTopScorers } from '../services/managerApi'
import { COMPETITIONS, COMP_NAME, COMP_ORDER, COMP_SHORT, COMP_THEME } from '../utils/seasonUtils'

const SCORERS = { id: 'scorers', label: 'Artilharia' }
// Abas de cada competição a partir do formato configurado (liga, grupos, fase de liga, mata-mata, playoff)
function viewsFor(compId) {
  const phases = COMPETITIONS[compId]?.phases || []
  const types = new Set(phases.map((p) => p.type))
  const out = []
  if (types.has('league')) out.push({ id: 'table', label: 'Tabela' })
  if (types.has('swiss')) out.push({ id: 'table', label: 'Tabela' })
  if (types.has('groups')) out.push({ id: 'table', label: 'Grupos' })
  if (types.has('knockout')) out.push({ id: 'bracket', label: types.has('league') ? 'Playoff' : 'Chave' })
  if (!out.length) out.push({ id: 'table', label: 'Tabela' })
  return [...out, { id: 'rounds', label: 'Rodadas' }, SCORERS]
}

// Artilheiros e garçons da competição (todas as partidas simuladas pelo motor contam)
function Scorers({ comp, version, myClub }) {
  const [data, setData] = useState(null)
  const [kind, setKind] = useState('scorers')
  useEffect(() => {
    let alive = true
    fetchTopScorers(comp)
      .then((d) => alive && setData(d))
      .catch(() => alive && setData({ scorers: [], assists: [] }))
    return () => {
      alive = false
    }
  }, [comp, version])
  if (!data) return <div className="st-sk row" />
  const list = data[kind] || []
  return (
    <div className="ts">
      <div className="sn-chips">
        <button type="button" className={kind === 'scorers' ? 'is-on' : ''} onClick={() => setKind('scorers')}>
          Gols
        </button>
        <button type="button" className={kind === 'assists' ? 'is-on' : ''} onClick={() => setKind('assists')}>
          Assistências
        </button>
      </div>
      {list.length === 0 ? (
        <p className="sn-muted sn-center">Ninguém marcou ainda.</p>
      ) : (
        <ol className="ts-list">
          {list.map((p, i) => (
            <li key={p.id + p.club_id} className={p.club_id === myClub ? 'is-mine' : ''}>
              <span className="ts-pos">{i + 1}</span>
              <ClubCrest clubId={p.club_id} size={20} />
              <span className="ts-name">
                <b>{p.name}</b>
                <small>{getClubById(p.club_id)?.name}</small>
              </span>
              <b className="ts-val">{kind === 'scorers' ? p.goals : p.assists}</b>
            </li>
          ))}
        </ol>
      )}
    </div>
  )
}

function RoundBrowser({ fixtures, myClub, lastKey, onOpenReport }) {
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
      <RoundResults matches={r.matches} myClub={myClub} onOpen={onOpenReport} />
      {onOpenReport && r.done && <p className="sn-hint">Toque num jogo para ver a súmula.</p>}
    </div>
  )
}

function CompetitionView({ comp, fixtures, myClub, lastKey, seasonId, onOpenReport }) {
  const views = viewsFor(comp.id)
  const [view, setView] = useState(views[0].id)
  const phases = COMPETITIONS[comp.id]?.phases || []
  const isGroups = phases.some((p) => p.type === 'groups')
  const [group, setGroup] = useState(() => groupOf(fixtures, myClub) || 'A')
  const groups = useMemo(() => [...new Set(fixtures.filter((f) => f.group_label).map((f) => f.group_label))].sort(), [fixtures])
  const version = useMemo(() => fixtures.filter((f) => f.status === 'played').length, [fixtures])
  const hasTable = views.some((v) => v.id === 'table')
  const { rows } = useStandings(hasTable ? seasonId : null, comp.id, isGroups ? group : null, version)

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
          {isGroups && (
            <div className="sn-groups" role="tablist" aria-label="Grupos">
              {groups.map((g) => (
                <button key={g} type="button" className={g === group ? 'is-on' : ''} onClick={() => setGroup(g)}>
                  {g}
                </button>
              ))}
            </div>
          )}
          <StandingsTable rows={rows} myClub={myClub} mode={isGroups ? 'group' : 'league'} zones={isGroups ? null : COMPETITIONS[comp.id]?.rules?.zones} />
        </>
      )}
      {view === 'bracket' && <Bracket comp={comp.id} fixtures={fixtures} myClub={myClub} />}
      {view === 'rounds' && <RoundBrowser key={comp.id} fixtures={fixtures} myClub={myClub} lastKey={lastKey} onOpenReport={onOpenReport} />}
      {view === 'scorers' && <Scorers comp={comp.id} version={version} myClub={myClub} />}
    </>
  )
}

// TORNEIOS: tabela (critérios de desempate oficiais, calculada no banco), grupos, chaveamento,
// rodadas com súmula e artilharia de cada campeonato.
export default function CompetitionsTab({ ctx, selected, onSelect, onOpenReport }) {
  const { hub, byComp, history, myClub } = ctx
  const comp = hub.competitions.find((c) => c.id === selected) || hub.competitions[0]
  const last = history.find((f) => f.comp === comp.id)
  const lastKey = last ? `${last.stage}:${last.round_no}` : null

  const t = COMP_THEME[comp.id] || { c1: '#333', c2: '#999', kicker: '' }
  const st = compStatus(comp)
  const inactive = comp.status === 'not_in' || comp.status === 'out'
  const pct = Math.min(100, (comp.played / (EXPECTED_MATCHES[comp.id] || comp.total || 1)) * 100)

  return (
    <div className="sn-page">
      <div className="ct-picker" role="tablist" aria-label="Campeonatos">
        {COMP_ORDER.map((id) => (
          <button key={id} type="button" role="tab" aria-selected={comp.id === id} className={comp.id === id ? 'is-on' : ''} style={{ '--c1': COMP_THEME[id]?.c1, '--c2': COMP_THEME[id]?.c2 }} onClick={() => onSelect(id)}>
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

      <CompetitionView key={comp.id} comp={comp} fixtures={byComp[comp.id] || []} myClub={myClub} lastKey={lastKey} seasonId={hub.season.id} onOpenReport={onOpenReport} />
    </div>
  )
}
