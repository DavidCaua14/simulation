// Prévia local (somente desenvolvimento) do campo 2D tático com dados fictícios. Não entra no build do jogo.
// Reproduz a lógica de relógio do MatchLive: o relógio espera o lance em campo (onHold) e o placar conta
// o lance assim que ele é mostrado (onReveal). Inclui dois gols no mesmo minuto (17') e gols seguidos (52', 53').
import { useCallback, useEffect, useMemo, useState } from 'react'
import { createRoot } from 'react-dom/client'
import '../../src/styles/theme.css'
import MatchTactical2D from '../../src/features/match2d/MatchTactical2D'
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
  { minute: 17, kind: 'goal', side: 'a', player: att('a')[0].id },
  { minute: 24, kind: 'yellow', side: 'a', player: players.find((p) => p.side === 'a' && p.pos === 'ZAG').id },
  { minute: 30, kind: 'offside', side: 'h', player: att('h')[0].id },
  { minute: 38, kind: 'pen_goal', side: 'a', player: att('a')[1].id },
  { minute: 45, kind: 'ht' },
  { minute: 52, kind: 'goal', side: 'a', player: att('a')[0].id },
  { minute: 53, kind: 'goal', side: 'h', player: att('h')[0].id },
  { minute: 60, kind: 'sub', side: 'h', player: att('h')[2].id },
  { minute: 80, kind: 'goal', side: 'h', player: att('h')[0].id },
  { minute: 90, kind: 'ft' },
].map((e, i) => ({ ...e, seq: i + 1, player_name: players.find((p) => p.id === e.player)?.name }))
const isGoal = (e) => e.kind === 'goal' || e.kind === 'pen_goal'

// mesmas velocidades do MatchLive
const SPEEDS = [
  { id: 1, ms: 700 },
  { id: 2, ms: 330 },
  { id: 4, ms: 140 },
]

function App() {
  const params = new URLSearchParams(location.search)
  const [speed, setSpeed] = useState(Number(params.get('speed') || 1))
  const ms = Number(params.get('ms')) || SPEEDS.find((s) => s.id === speed)?.ms || 700
  const start = Number(params.get('start') || 0)
  const [clock, setClock] = useState(start)
  // "servidor": etapas de 5 minutos; enquanto a próxima etapa carrega, o campo fica pausado (como no MatchLive)
  const [server, setServer] = useState(() => ({ minute: Math.min(90, start - (start % 5) + 5), players }))
  const [holdAt, setHoldAt] = useState(null)
  const [revealed, setRevealed] = useState(() => new Set())
  const onReveal = useCallback((seqs) => setRevealed((prev) => new Set([...prev, ...seqs])), [])
  useEffect(() => {
    const cap = holdAt != null ? Math.max(clock, holdAt - 0.01) : Infinity
    if (clock >= server.minute || clock >= cap) return undefined
    const id = setInterval(() => setClock((c) => Math.min(server.minute, cap, c + 100 / ms)), 100)
    return () => clearInterval(id)
  }, [clock, holdAt, ms, server.minute])
  useEffect(() => {
    if (clock < server.minute || server.minute >= 90) return undefined
    const id = setTimeout(() => setServer((s) => ({ minute: Math.min(90, s.minute + 5), players: s.players.map((p) => ({ ...p })) })), 600)
    return () => clearTimeout(id)
  }, [clock, server.minute])
  const shown = Math.floor(clock)
  const upcoming = useMemo(() => SCRIPT.filter((e) => e.minute <= shown + 1), [shown])
  const visible = useMemo(() => SCRIPT.filter((e) => e.minute <= shown || revealed.has(e.seq)), [shown, revealed])
  const score = useMemo(() => {
    const s = { h: 0, a: 0 }
    for (const e of visible) if (isGoal(e)) s[e.side] += 1
    return s
  }, [visible])
  useEffect(() => {
    window.__preview = { clock, holdAt, score, revealed: [...revealed] }
  }, [clock, holdAt, score, revealed])
  const data = { home: 'flamengo', away: 'palmeiras', players: server.players, formation: ['4-3-3', '4-2-3-1'], stats: { poss: [55, 45] }, minute: server.minute }
  return (
    <div style={{ maxWidth: params.get('w') ? Number(params.get('w')) : 1100, margin: '0 auto' }}>
      <MatchTactical2D data={data} catalog={catalog} clock={clock} minute={shown} events={upcoming} paused={clock >= server.minute} speed={speed}
        score={score} finished={clock >= 90} clockLabel={`${shown}'`} userSide="h" onHold={setHoldAt} onReveal={onReveal} />
      <div style={{ display: 'flex', gap: 8, padding: 8 }}>
        {SPEEDS.map((s) => (
          <button key={s.id} type="button" aria-pressed={speed === s.id} onClick={() => setSpeed(s.id)}>
            {s.id}x
          </button>
        ))}
      </div>
      <ol style={{ color: '#cbd5e1', font: '13px Inter, sans-serif' }}>
        {[...visible].reverse().map((e) => (
          <li key={e.seq}>{e.minute}' {e.kind} {e.player_name || ''}</li>
        ))}
      </ol>
    </div>
  )
}

createRoot(document.getElementById('root')).render(<App />)
