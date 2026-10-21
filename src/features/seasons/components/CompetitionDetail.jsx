import { useEffect, useMemo, useState } from 'react'
import { fetchFixtures, fetchStandings } from '../services/seasonsApi'
import StandingsTable from './StandingsTable'
import FixtureList from './FixtureList'
import Bracket from './Bracket'

const TABS_BY_COMP = {
  brasileirao: [
    { id: 'table', label: 'Tabela' },
    { id: 'mine', label: 'Meus jogos' },
  ],
  libertadores: [
    { id: 'table', label: 'Grupos' },
    { id: 'mine', label: 'Meus jogos' },
    { id: 'bracket', label: 'Mata-mata' },
  ],
  copa_brasil: [
    { id: 'bracket', label: 'Mata-mata' },
    { id: 'mine', label: 'Meus jogos' },
  ],
}

// Detalhes de um campeonato: classificação, seus jogos e o chaveamento.
// `version` muda a cada partida simulada, para recarregar os dados.
export default function CompetitionDetail({ seasonId, comp, myClub, version }) {
  const tabs = TABS_BY_COMP[comp.id] || TABS_BY_COMP.brasileirao
  const [tab, setTab] = useState(tabs[0].id)
  const [fixtures, setFixtures] = useState([])
  const [rows, setRows] = useState([])
  const [group, setGroup] = useState(comp.table?.group || 'A')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  const groups = useMemo(() => [...new Set(fixtures.filter((f) => f.group_label).map((f) => f.group_label))].sort(), [fixtures])

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    fetchFixtures(seasonId, comp.id)
      .then((data) => !cancelled && (setFixtures(data), setError('')))
      .catch((e) => !cancelled && setError(e.message))
      .finally(() => !cancelled && setLoading(false))
    return () => {
      cancelled = true
    }
  }, [seasonId, comp.id, version])

  const needsTable = comp.id === 'brasileirao' || comp.id === 'libertadores'
  useEffect(() => {
    if (!needsTable) return undefined
    let cancelled = false
    fetchStandings(seasonId, comp.id, comp.id === 'libertadores' ? group : null)
      .then((data) => !cancelled && setRows(data))
      .catch((e) => !cancelled && setError(e.message))
    return () => {
      cancelled = true
    }
  }, [seasonId, comp.id, group, version, needsTable])

  return (
    <div className="sn-detail">
      <div className="pred-seg sn-seg">
        {tabs.map((t) => (
          <button key={t.id} type="button" className={tab === t.id ? 'is-on' : ''} onClick={() => setTab(t.id)}>
            {t.label}
          </button>
        ))}
      </div>

      {error && <p className="sn-error">{error}</p>}
      {loading && !fixtures.length ? (
        <p className="sn-muted">Carregando…</p>
      ) : (
        <>
          {tab === 'table' && (
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
          {tab === 'mine' && <FixtureList fixtures={fixtures} myClub={myClub} />}
          {tab === 'bracket' && <Bracket fixtures={fixtures} myClub={myClub} />}
        </>
      )}
    </div>
  )
}
