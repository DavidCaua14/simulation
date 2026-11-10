import { useEffect, useState } from 'react'
import { Crown, History, Radio, Trophy } from 'lucide-react'
import { EmptyState, Notice, Skeleton } from '../../components/ui/feedback'
import OnlineCrest from './components/OnlineCrest'
import { fetchOnlineCup } from './services/onlineApi'
import { kickoffDay, kickoffTime } from './onlineUtils'

const STAGES = [
  [1, 'Primeira fase', 'Dia 6'],
  [2, 'Quartas', 'Dia 12'],
  [3, 'Semifinal', 'Dia 18'],
  [4, 'Final', 'Dia 24 · campo neutro'],
]

function Tie({ f, me, now, onOpenMatch }) {
  const live = f.status !== 'done' && new Date(f.kickoff).getTime() <= now
  const side = (c, g, p) => (
    <span className={`on-tie-team ${f.winner === c.id ? 'is-win' : f.winner ? 'is-out' : ''} ${c.id === me ? 'is-mine' : ''}`}>
      <OnlineCrest club={c} size={22} />
      <b>{c.name}</b>
      {f.status === 'done' && <em>{g}{f.pens ? <small> ({p})</small> : null}</em>}
    </span>
  )
  return (
    <button type="button" className={`on-tie ${live ? 'is-live' : ''}`} disabled={f.status !== 'done' && !live} onClick={() => onOpenMatch(f.id)}>
      {side(f.home, f.hg, f.pens?.[0])}
      {side(f.away, f.ag, f.pens?.[1])}
      <small className="on-tie-when">{live ? <><Radio size={11} /> ao vivo</> : f.status === 'done' ? (f.pens ? 'nos pênaltis' : 'encerrado') : `${kickoffDay(f.kickoff)} · ${kickoffTime(f.kickoff)}`}</small>
    </button>
  )
}

// COPA: chave da temporada (12 clubes; os 4 primeiros da liga folgam na primeira fase) e histórico.
export default function OnlineCup({ now, onOpenMatch }) {
  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  useEffect(() => {
    fetchOnlineCup().then(setData).catch((e) => setError(e.message))
  }, [])
  if (!data) return error ? <Notice kind="error">{error}</Notice> : <Skeleton rows={6} />
  const final = data.rounds.find((f) => f.round === 4 && f.status === 'done')
  const champ = final && (final.winner === final.home.id ? final.home : final.away)
  return (
    <section className="on-cup">
      {champ && (
        <div className="on-champ">
          <Trophy size={34} />
          <OnlineCrest club={champ} size={54} />
          <div><small>Campeão da Copa</small><b>{champ.name}</b></div>
        </div>
      )}
      {data.rounds.length === 0 && (
        <EmptyState compact icon={Trophy} title="A copa começa no dia 6" text="Depois da 5ª rodada, os 4 primeiros da liga folgam e os outros 8 se enfrentam em jogo único. Empate vai para a prorrogação e os pênaltis." />
      )}
      {STAGES.filter(([r]) => data.rounds.some((f) => f.round === r)).map(([r, label, when]) => (
        <div key={r} className="on-cup-stage">
          <h3 className="gx-subtitle">{label} <small>{when}</small></h3>
          <div className="on-ties">
            {data.rounds.filter((f) => f.round === r).map((f) => <Tie key={f.id} f={f} me={data.my_club} now={now} onOpenMatch={onOpenMatch} />)}
          </div>
          {r === 1 && data.byes?.length > 0 && (
            <p className="on-hint"><Crown size={13} /> Folgam e entram nas quartas: {data.byes.map((c) => c.short).join(', ')}</p>
          )}
        </div>
      ))}
      {data.history.length > 0 && (
        <>
          <h3 className="gx-subtitle"><History size={13} /> Temporadas anteriores</h3>
          <ul className="on-list">
            {data.history.map((h) => (
              <li key={h.season} className="on-hist">
                <b>T{h.season}</b>
                <span>Liga: <strong>{h.champion}</strong> · Copa: <strong>{h.cup || '—'}</strong></span>
                {h.me && <em>Você: {h.me.pos}º · {h.me.pts} pts</em>}
              </li>
            ))}
          </ul>
        </>
      )}
    </section>
  )
}
