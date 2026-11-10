import { useEffect, useRef, useState } from 'react'
import { GAMES } from './miniGamesInfo'

// MINI-GAMES DE TREINO. Cada um devolve um resultado de 0 a 1 por onDone(score).
// O servidor limita o resultado e o ganho; aqui é só a jogabilidade.


// 1) Tempo certo: marcador vai e volta; a faixa verde encolhe.
function Timing({ onDone }) {
  const [round, setRound] = useState(0)
  const [hits, setHits] = useState(0)
  const [flash, setFlash] = useState(null)
  const pos = useRef(0)
  const dir = useRef(1)
  const bar = useRef(null)
  const zone = { w: 22 - round * 1.6, x: 20 + ((round * 37) % 55) }
  useEffect(() => {
    let raf
    let last = performance.now()
    const step = (t) => {
      const dt = (t - last) / 1000
      last = t
      pos.current += dir.current * dt * (70 + round * 12)
      if (pos.current > 100) (pos.current = 100), (dir.current = -1)
      if (pos.current < 0) (pos.current = 0), (dir.current = 1)
      if (bar.current) bar.current.style.left = `${pos.current}%`
      raf = requestAnimationFrame(step)
    }
    raf = requestAnimationFrame(step)
    return () => cancelAnimationFrame(raf)
  }, [round])
  const tap = () => {
    const ok = pos.current >= zone.x && pos.current <= zone.x + zone.w
    setFlash(ok ? 'ok' : 'miss')
    setTimeout(() => setFlash(null), 250)
    const h = hits + (ok ? 1 : 0)
    setHits(h)
    if (round + 1 >= 8) onDone(h / 8)
    else setRound(round + 1)
  }
  return (
    <button type="button" className={`mg-timing ${flash ? `is-${flash}` : ''}`} onClick={tap}>
      <span className="mg-track">
        <i className="mg-zone" style={{ left: `${zone.x}%`, width: `${zone.w}%` }} />
        <i className="mg-marker" ref={bar} />
      </span>
      <span className="mg-score">{hits} / {round} · toque!</span>
    </button>
  )
}

// 2) Reação: alvos em uma grade 3×3; quanto mais rápido, mais pontos. 12 alvos.
function Reaction({ onDone }) {
  const [target, setTarget] = useState(null)
  const [n, setN] = useState(0)
  const total = useRef(0)
  const shown = useRef(0)
  useEffect(() => {
    if (n >= 12) return undefined
    const t = setTimeout(() => {
      setTarget(Math.floor(Math.random() * 9))
      shown.current = performance.now()
    }, 400 + Math.random() * 700)
    return () => clearTimeout(t)
  }, [n])
  useEffect(() => {
    if (target == null) return undefined
    const t = setTimeout(() => {
      setTarget(null)
      setN((x) => x + 1)
    }, 1100)
    return () => clearTimeout(t)
  }, [target])
  useEffect(() => {
    if (n >= 12) onDone(Math.min(1, total.current / 12))
  }, [n, onDone])
  const hit = (e, i) => {
    if (i !== target) return
    const ms = e.timeStamp - shown.current
    total.current += Math.max(0, Math.min(1, (1000 - ms) / 600))
    setTarget(null)
    setN((x) => x + 1)
  }
  return (
    <div className="mg-react">
      {Array.from({ length: 9 }, (_, i) => (
        <button key={i} type="button" className={`mg-cell ${target === i ? 'is-on' : ''}`} onClick={(e) => hit(e, i)} aria-label={target === i ? 'Alvo' : 'Vazio'} />
      ))}
      <span className="mg-score">{n} / 12</span>
    </div>
  )
}

// 3) Sequência de passes: 5 jogadores no campo piscam em ordem; repita. Até 8 passes.
const SPOTS = [[20, 75], [50, 85], [80, 75], [35, 40], [65, 40]]
function Passing({ onDone }) {
  const [all] = useState(() => Array.from({ length: 9 }, () => Math.floor(Math.random() * 5)))
  const [len, setLen] = useState(2)
  const seq = all.slice(0, len)
  const [showing, setShowing] = useState(true)
  const [lit, setLit] = useState(null)
  const [pos, setPos] = useState(0)
  useEffect(() => {
    if (!showing) return undefined
    let i = 0
    const id = setInterval(() => {
      if (i >= seq.length * 2) {
        clearInterval(id)
        setLit(null)
        setShowing(false)
        return
      }
      setLit(i % 2 === 0 ? seq[i / 2] : null)
      i += 1
    }, 330)
    return () => clearInterval(id)
  }, [showing, len]) // eslint-disable-line react-hooks/exhaustive-deps
  const tap = (k) => {
    if (showing) return
    setLit(k)
    setTimeout(() => setLit(null), 150)
    if (k !== seq[pos]) return onDone(Math.max(0, (seq.length - 2) / 7))
    if (pos + 1 < seq.length) return setPos(pos + 1)
    if (seq.length >= 9) return onDone(1)
    setLen(len + 1)
    setPos(0)
    setShowing(true)
  }
  return (
    <div className="mg-pass">
      {SPOTS.map(([x, y], k) => (
        <button key={k} type="button" className={`mg-dot ${lit === k ? 'is-lit' : ''}`} style={{ left: `${x}%`, top: `${y}%` }} onClick={() => tap(k)} aria-label={`Jogador ${k + 1}`}>
          {k + 1}
        </button>
      ))}
      <span className="mg-score">{showing ? 'Observe…' : `Sua vez: ${pos}/${seq.length}`} · nível {seq.length - 1}</span>
    </div>
  )
}

// 4) Mira de chute: mira e goleiro se movem; gol se a mira estiver longe do goleiro e dentro do gol.
function Aim({ onDone }) {
  const [shots, setShots] = useState(0)
  const [goals, setGoals] = useState(0)
  const [result, setResult] = useState(null)
  const aim = useRef({ x: 50, y: 50 })
  const gk = useRef(50)
  const aimEl = useRef(null)
  const gkEl = useRef(null)
  useEffect(() => {
    let raf
    const t0 = performance.now()
    const step = (t) => {
      const s = (t - t0) / 1000
      aim.current = { x: 50 + 46 * Math.sin(s * (1.9 + shots * 0.25)), y: 45 + 35 * Math.sin(s * (2.7 + shots * 0.2) + 1) }
      gk.current = 50 + 30 * Math.sin(s * 1.3 + shots)
      if (aimEl.current) Object.assign(aimEl.current.style, { left: `${aim.current.x}%`, top: `${aim.current.y}%` })
      if (gkEl.current) gkEl.current.style.left = `${gk.current}%`
      raf = requestAnimationFrame(step)
    }
    raf = requestAnimationFrame(step)
    return () => cancelAnimationFrame(raf)
  }, [shots])
  const shoot = () => {
    const { x, y } = aim.current
    const inside = x > 6 && x < 94 && y > 10 && y < 90
    const goal = inside && Math.abs(x - gk.current) > 18
    setResult(goal ? 'GOL!' : inside ? 'Defendeu' : 'Para fora')
    setTimeout(() => setResult(null), 450)
    const g = goals + (goal ? 1 : 0)
    setGoals(g)
    if (shots + 1 >= 6) onDone(g / 6)
    else setShots(shots + 1)
  }
  return (
    <button type="button" className="mg-aim" onClick={shoot}>
      <span className="mg-goal">
        <i className="mg-gk" ref={gkEl} />
        <i className="mg-cross" ref={aimEl} />
        {result && <b className="mg-result">{result}</b>}
      </span>
      <span className="mg-score">{goals} gols em {shots} chutes · toque para chutar</span>
    </button>
  )
}

export default function MiniGame({ game, onDone }) {
  const [started, setStarted] = useState(false)
  const [count, setCount] = useState(3)
  useEffect(() => {
    if (!started || count <= 0) return undefined
    const t = setTimeout(() => setCount(count - 1), 700)
    return () => clearTimeout(t)
  }, [started, count])
  const G = { timing: Timing, reaction: Reaction, passing: Passing, aim: Aim }[game]
  const info = GAMES[game]
  if (!started)
    return (
      <div className="mg-intro">
        <small>{info.group}</small>
        <h3>{info.title}</h3>
        <p>{info.tip}</p>
        <button type="button" className="gx-btn" onClick={() => setStarted(true)}>Começar</button>
      </div>
    )
  if (count > 0) return <div className="mg-count" aria-live="assertive">{count}</div>
  return <G onDone={onDone} />
}
