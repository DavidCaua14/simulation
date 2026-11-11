import { useEffect, useState } from 'react'
import { Crown, Radio, Trophy } from 'lucide-react'
import { Notice, Skeleton } from '../../components/ui/feedback'
import OnlineCrest from './components/OnlineCrest'
import { fetchOnlineCup } from './services/onlineApi'
import { kickoffDay, kickoffTime } from './onlineUtils'

const STAGES = [
  [1, '1ª fase'],
  [2, 'Quartas de final'],
  [3, 'Semifinal'],
  [4, 'Final'],
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
      <small className="on-tie-when">{live ? <><Radio size={11} /> ao vivo</> : f.status === 'done' ? (f.pens ? 'Pênaltis' : 'Encerrado') : `${kickoffDay(f.kickoff)} · ${kickoffTime(f.kickoff)}`}</small>
    </button>
  )
}

// COPA: chave da temporada e galeria de campeões.
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
    <div className="on-cup">
      <div className="on-cup-hero">
        <Trophy size={40} />
        <div>
          <small>Copa Online</small>
          {champ ? <b><OnlineCrest club={champ} size={22} /> {champ.name}</b> : <b>{data.rounds.length ? STAGES.filter(([r]) => data.rounds.some((f) => f.round === r)).at(-1)[1] : 'Sorteio após a 5ª rodada'}</b>}
        </div>
        {champ && <Crown size={22} className="on-cup-crown" />}
      </div>
      {STAGES.filter(([r]) => data.rounds.some((f) => f.round === r)).reverse().map(([r, label]) => (
        <div key={r} className={`on-cup-stage s-${r}`}>
          <h3 className="on-h">{label}</h3>
          <div className="on-ties">
            {data.rounds.filter((f) => f.round === r).map((f) => <Tie key={f.id} f={f} me={data.my_club} now={now} onOpenMatch={onOpenMatch} />)}
          </div>
          {r === 1 && data.byes?.length > 0 && (
            <div className="on-byes">{data.byes.map((c) => <OnlineCrest key={c.id} club={c} size={24} />)}<small>aguardam nas quartas</small></div>
          )}
        </div>
      ))}
      {data.history.length > 0 && (
        <div className="on-block">
          <h3 className="on-h">Galeria de campeões</h3>
          <ul className="on-hall">
            {data.history.map((h) => (
              <li key={h.season}>
                <b>T{h.season}</b>
                <span><small>Liga</small>{h.champion}</span>
                <span><small>Copa</small>{h.cup || '—'}</span>
                {h.me && <em>{h.me.pos}º</em>}
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  )
}
