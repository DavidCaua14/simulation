// Prévia local (somente desenvolvimento) da transmissão 2.5D com dados fictícios. Não entra no build do jogo.
import { useEffect, useMemo, useState } from 'react'
import { createRoot } from 'react-dom/client'
import '../../src/styles/theme.css'
import MatchBroadcast from '../../src/features/match25d/MatchBroadcast'
import formations from './formations.json'
import roster from './players.json'

const catalog = { formations, byId: Object.fromEntries(formations.map((f) => [f.id, f])) }
function lineup(club, side, form) {
  const slots = catalog.byId[form].slots
  const pool = roster.filter((p) => p.club === club)
  const used = new Set()
  return slots.map((s) => {
    const p = pool.find((x) => !used.has(x.id) && x.pos === s.pos) || pool.find((x) => !used.has(x.id) && (s.pos === 'GOL') === (x.pos === 'GOL'))
    used.add(p.id)
    return { id: p.id, name: p.name, number: p.number, side, slot: s.slot, pos: s.pos, status: 'on' }
  })
}
const players = [...lineup('flamengo', 'h', '4-3-3'), ...lineup('palmeiras', 'a', '4-2-3-1')]
const att = (side) => players.filter((p) => p.side === side && ['ATA', 'PD', 'PE', 'MEI'].includes(p.pos))
const SCRIPT = [
  { minute: 0, kind: 'kickoff' },
  { minute: 6, kind: 'shot_off', side: 'a', player: att('a')[0].id },
  { minute: 11, kind: 'save', side: 'h', player: att('h')[0].id },
  { minute: 17, kind: 'goal', side: 'h', player: att('h')[1].id },
  { minute: 24, kind: 'yellow', side: 'a', player: players.find((p) => p.side === 'a' && p.pos === 'ZAG').id },
  { minute: 30, kind: 'offside', side: 'h', player: att('h')[0].id },
  { minute: 38, kind: 'pen_goal', side: 'a', player: att('a')[1].id },
  { minute: 45, kind: 'ht' },
  { minute: 52, kind: 'goal', side: 'a', player: att('a')[0].id },
  { minute: 60, kind: 'sub', side: 'h', player: att('h')[2].id },
  { minute: 70, kind: 'red', side: 'h', player: players.find((p) => p.side === 'h' && p.pos === 'VOL')?.id || att('h')[2].id },
  { minute: 80, kind: 'goal', side: 'h', player: att('h')[0].id },
  { minute: 90, kind: 'ft' },
].map((e, i) => ({ ...e, seq: i + 1, player_name: players.find((p) => p.id === e.player)?.name }))

function App() {
  const params = new URLSearchParams(location.search)
  const ms = Number(params.get('ms') || 700)
  const start = Number(params.get('start') || 0)
  const [clock, setClock] = useState(start)
  useEffect(() => {
    const id = setInterval(() => setClock((c) => Math.min(90, c + 100 / ms)), 100)
    return () => clearInterval(id)
  }, [ms])
  const visible = useMemo(() => SCRIPT.filter((e) => e.minute <= Math.floor(clock)), [clock])
  const score = useMemo(() => {
    const s = { h: 0, a: 0 }
    for (const e of visible) if (e.kind === 'goal' || e.kind === 'pen_goal') s[e.side] += 1
    return s
  }, [visible])
  const data = { home: 'flamengo', away: 'palmeiras', players, formation: ['4-3-3', '4-2-3-1'], stats: { poss: [55, 45] } }
  return (
    <div style={{ maxWidth: params.get('w') ? Number(params.get('w')) : 1200, margin: '0 auto' }}>
      <MatchBroadcast data={data} catalog={catalog} clock={clock} minute={Math.floor(clock)} events={visible} paused={false} speed={1}
        score={score} finished={clock >= 90} clockLabel={`${Math.floor(clock)}'`} userSide="h" />
    </div>
  )
}
createRoot(document.getElementById('root')).render(<App />)
