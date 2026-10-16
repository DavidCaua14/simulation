import { useCallback, useEffect, useMemo, useState } from 'react'
import useMatches from '../hooks/useMatches'
import { fetchCompetitions } from '../services/predictionsApi'
import { addDays, dayKeyOf, formatDayChip, isLocked } from '../utils/matchUtils'
import MatchCard from './MatchCard'
import MatchDetailsSheet from './MatchDetailsSheet'
import { BetSlipBar, BetSlipSheet } from './BetSlip'

export default function MatchesSection({ slip, now, balance, notify, onWalletChange }) {
  const today = dayKeyOf(new Date(now))
  const [view, setView] = useState(today)
  const [selectedId, setSelectedId] = useState(null)
  const [slipOpen, setSlipOpen] = useState(false)
  const [competitions, setCompetitions] = useState({})

  useEffect(() => {
    fetchCompetitions()
      .then((list) => setCompetitions(Object.fromEntries(list.map((c) => [c.id, c.name]))))
      .catch(() => {})
  }, [])

  const handleEvent = useCallback(
    ({ type, match }) => {
      const name = `${match.home_team} x ${match.away_team}`
      if (type === 'started') notify(`⚽ Começou: ${name}`)
      else {
        notify(`🏁 Fim de jogo: ${name} ${match.home_score ?? 0}–${match.away_score ?? 0}`)
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

  const selected = matches.find((m) => m.id === selectedId)

  function pickResult(match, result) {
    if (!slip.toggleResult(match, result)) notify('O bilhete já está cheio (máx. 10 jogos).')
  }
  function pickBtts(match, value) {
    if (!slip.toggleBtts(match, value)) notify('O bilhete já está cheio (máx. 10 jogos).')
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
          <p className="pred-empty">
            {view === 'live' ? 'Nenhum jogo acontecendo agora.' : 'Nenhum jogo neste dia nas Séries A, B e C.'}
          </p>
        )}
        {!loading &&
          matches.map((m) => (
            <MatchCard
              key={m.id}
              match={m}
              competitionName={competitions[m.competition_id] || 'Brasileirão'}
              pick={slip.picks[m.id]}
              locked={isLocked(m, now)}
              onPickResult={pickResult}
              onOpen={setSelectedId}
            />
          ))}
      </div>

      <BetSlipBar count={slip.count} multiplier={slip.multiplier} onOpen={() => setSlipOpen(true)} />

      {selected && (
        <MatchDetailsSheet
          match={selected}
          competitionName={competitions[selected.competition_id] || 'Brasileirão'}
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
            notify('🎟️ Bilhete criado! Acompanhe em "Meus bilhetes".')
          }}
        />
      )}
    </>
  )
}
