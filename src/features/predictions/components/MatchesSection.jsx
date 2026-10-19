import { useCallback, useEffect, useMemo, useState } from 'react'
import useMatches from '../hooks/useMatches'
import { fetchCompetitions } from '../services/predictionsApi'
import { addDays, dayKeyOf, formatDayChip, isLocked } from '../utils/matchUtils'
import MatchCard from './MatchCard'
import MatchDetailsSheet from './MatchDetailsSheet'
import { BetSlipBar, BetSlipSheet } from './BetSlip'
import { TrophyIcon } from './PredIcons'

export default function MatchesSection({ slip, now, balance, notify, onWalletChange }) {
  const today = dayKeyOf(new Date(now))
  const [view, setView] = useState(today)
  const [selectedId, setSelectedId] = useState(null)
  const [slipOpen, setSlipOpen] = useState(false)
  const [competitions, setCompetitions] = useState({})

  useEffect(() => {
    fetchCompetitions()
      .then((list) => setCompetitions(Object.fromEntries(list.map((c) => [c.id, c]))))
      .catch(() => {})
  }, [])

  const handleEvent = useCallback(
    ({ type, match }) => {
      const name = `${match.home_team} x ${match.away_team}`
      if (type === 'started') notify(`Começou: ${name}`, 'start')
      else {
        const score = match.home_score != null ? ` ${match.home_score} x ${match.away_score}` : ''
        notify(`Fim de jogo: ${name}${score}`, 'finish')
        setTimeout(onWalletChange, 4000) // dá tempo do servidor liquidar os bilhetes
      }
    },
    [notify, onWalletChange],
  )

  const { matches, loading, error, reload } = useMatches(view, handleEvent)

  const chips = useMemo(
    () => [
      { key: 'live', label: 'Ao vivo', sub: '' },
      { key: today, label: 'Hoje', sub: formatDayChip(today).date },
      ...[1, 2, 3, 4, 5, 6].map((n) => {
        const key = addDays(today, n)
        const { weekday, date } = formatDayChip(key)
        return { key, label: weekday, sub: date }
      }),
    ],
    [today],
  )

  // Agrupa por campeonato, na ordem definida em competitions.sort_order
  const groups = useMemo(() => {
    const map = new Map()
    for (const m of matches) map.set(m.competition_id, [...(map.get(m.competition_id) ?? []), m])
    return [...map.entries()]
      .map(([id, list]) => ({ id, comp: competitions[id], list }))
      .sort((a, b) => (a.comp?.sort_order ?? 100) - (b.comp?.sort_order ?? 100) || a.id - b.id)
  }, [matches, competitions])

  const selected = matches.find((m) => m.id === selectedId)
  const nameOf = (id) => competitions[id]?.name || 'Campeonato'

  function pickResult(match, result) {
    if (!slip.toggleResult(match, result)) notify('O bilhete já está cheio (máx. 10 jogos).', 'alert')
  }
  function pickBtts(match, value) {
    if (!slip.toggleBtts(match, value)) notify('O bilhete já está cheio (máx. 10 jogos).', 'alert')
  }

  return (
    <>
      <div className="pred-chips-row">
        {chips.map((c) => (
          <button
            key={c.key}
            type="button"
            className={`pred-day ${view === c.key ? 'is-on' : ''} ${c.key === 'live' ? 'is-live-tab' : ''}`}
            onClick={() => setView(c.key)}
          >
            <b>{c.key === 'live' && <i className="pred-dot" />}{c.label}</b>
            {c.sub && <small>{c.sub}</small>}
          </button>
        ))}
      </div>

      <div className="pred-list">
        {loading && <p className="pred-empty">Carregando jogos…</p>}
        {!loading && error && (
          <div className="pred-empty">
            <p>{error}</p>
            <button type="button" className="pred-btn" onClick={reload}>Tentar de novo</button>
          </div>
        )}
        {!loading && !error && matches.length === 0 && (
          <div className="pred-empty">
            <p>{view === 'live' ? 'Nenhum jogo acontecendo agora.' : 'Nenhum jogo neste dia.'}</p>
            {view === 'live' && (
              <button type="button" className="pred-btn" onClick={() => setView(today)}>Ver jogos de hoje</button>
            )}
          </div>
        )}

        {!loading &&
          groups.map((g) => (
            <section key={g.id} className="pred-group">
              <header className="pred-group-head">
                <span className="pred-group-logo">
                  {g.comp?.emblem ? <img src={g.comp.emblem} alt="" loading="lazy" /> : <TrophyIcon />}
                </span>
                <h4>{nameOf(g.id)}</h4>
                <small>{g.list.length} {g.list.length === 1 ? 'jogo' : 'jogos'}</small>
              </header>
              {g.list.map((m) => (
                <MatchCard
                  key={m.id}
                  match={m}
                  now={now}
                  pick={slip.picks[m.id]}
                  locked={isLocked(m, now)}
                  onPickResult={pickResult}
                  onOpen={setSelectedId}
                />
              ))}
            </section>
          ))}
      </div>

      <BetSlipBar count={slip.count} multiplier={slip.multiplier} onOpen={() => setSlipOpen(true)} />

      {selected && (
        <MatchDetailsSheet
          match={selected}
          competitionName={nameOf(selected.competition_id)}
          now={now}
          pick={slip.picks[selected.id]}
          locked={isLocked(selected, now)}
          onResult={pickResult}
          onBtts={pickBtts}
          onClose={() => setSelectedId(null)}
        />
      )}

      {slipOpen && slip.count > 0 && (
        <BetSlipSheet
          slip={slip}
          balance={balance}
          onClose={() => setSlipOpen(false)}
          onPlaced={() => {
            setSlipOpen(false)
            onWalletChange()
            notify('Bilhete criado! Acompanhe em "Meus bilhetes".', 'ticket')
          }}
        />
      )}
    </>
  )
}
