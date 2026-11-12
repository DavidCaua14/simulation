import { useEffect, useState } from 'react'
import { Coins } from 'lucide-react'
import { fetchPrizeTable } from '../services/managerApi'
import './prize-table.css'

// PREMIAÇÃO da competição em moedas (tabela sim_prizes; 1 moeda ≈ R$ 10 mil do prêmio real).
// Liga: por posição final. Copa: acumulado até a fase em que o clube parou. Vitória e empate pagam por jogo.
const STAGES = [['champion', 'Campeão'], ['runner_up', 'Vice-campeão'], ['sf', 'Semifinal'], ['qf', 'Quartas de final'], ['r16', 'Oitavas de final'], ['group', 'Fase de grupos']]
const fmt = (n) => Number(n || 0).toLocaleString('pt-BR')
let cache = null

export default function PrizeTable({ comp, myPos }) {
  const [table, setTable] = useState(cache)
  useEffect(() => {
    if (cache) return undefined
    let alive = true
    fetchPrizeTable().then((t) => { cache = t; if (alive) setTable(t) }).catch(() => alive && setTable([]))
    return () => { alive = false }
  }, [])
  if (!table) return <div className="st-sk row" />
  const row = table.find((x) => x.id === comp)
  if (!row) return <p className="sn-muted sn-center">Sem premiação cadastrada.</p>
  const league = (row.league || []).map((coins, i) => [i + 1, coins]).filter(([, coins]) => coins > 0)
  const stages = STAGES.map(([id, label]) => [label, row.stages?.[id] || 0]).filter(([, coins]) => coins > 0)
  return (
    <section className="pz">
      <div className="pz-match">
        <span><small>Vitória</small><b><Coins size={14} /> {fmt(row.win)}</b></span>
        <span><small>Empate</small><b><Coins size={14} /> {fmt(row.draw)}</b></span>
      </div>
      <ol className="pz-list">
        {league.map(([pos, coins]) => (
          <li key={pos} className={pos === myPos ? 'is-me' : ''}><span>{pos}º</span><b><Coins size={13} /> {fmt(coins)}</b></li>
        ))}
        {stages.map(([label, coins]) => (
          <li key={label}><span>{label}</span><b><Coins size={13} /> {fmt(coins)}</b></li>
        ))}
      </ol>
    </section>
  )
}
