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
      <span className="mg-score">{hits} / 8</span>
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
      <span className="mg-score">{showing ? '•••' : `${pos} / ${seq.length}`}</span>
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
      <span className="mg-score">{goals} / 6</span>
    </button>
  )
}

// 5) Desarme: o atacante desce por uma das três faixas; toque na faixa quando ele chegar à linha do zagueiro. 8 ataques.
function Tackle({ onDone }) {
  const [n, setN] = useState(0)
  const [hits, setHits] = useState(0)
  const [flash, setFlash] = useState(null)
  const run = useRef({ lane: 1, y: 0, speed: 60, live: false })
  const el = useRef(null)
  const done = useRef(false)
  useEffect(() => {
    if (n >= 8) {
      if (!done.current) {
        done.current = true
        onDone(hits / 8)
      }
      return undefined
    }
    run.current = { lane: Math.floor(Math.random() * 3), y: 0, speed: 55 + n * 9 + Math.random() * 25, live: true }
    let raf
    let last = performance.now()
    const step = (t) => {
      const r = run.current
      const dt = (t - last) / 1000
      last = t
      if (r.live) {
        r.y += r.speed * dt
        if (el.current) Object.assign(el.current.style, { left: `${16.6 + r.lane * 33.3}%`, top: `${r.y}%` })
        if (r.y > 96) {
          r.live = false
          setFlash('miss')
          setTimeout(() => setFlash(null), 220)
          setN((x) => x + 1)
          return
        }
      }
      raf = requestAnimationFrame(step)
    }
    raf = requestAnimationFrame(step)
    return () => cancelAnimationFrame(raf)
  }, [n]) // eslint-disable-line react-hooks/exhaustive-deps
  const tap = (lane) => {
    const r = run.current
    if (!r.live) return
    r.live = false
    const ok = lane === r.lane && r.y >= 64 && r.y <= 88
    setFlash(ok ? 'ok' : 'miss')
    setTimeout(() => setFlash(null), 220)
    if (ok) setHits((h) => h + 1)
    setN((x) => x + 1)
  }
  return (
    <div className={`mg-tackle ${flash ? `is-${flash}` : ''}`}>
      <i className="mg-tackle-line" />
      <i className="mg-runner" ref={el} />
      {[0, 1, 2].map((lane) => <button key={lane} type="button" className="mg-lane" onClick={() => tap(lane)} aria-label={`Faixa ${lane + 1}`}><i className="mg-def" /></button>)}
      <span className="mg-score">{hits} / 8</span>
    </div>
  )
}

// 6) Drible: conduza a bola por três faixas desviando dos marcadores. 14 marcadores.
function Dribble({ onDone }) {
  const [lane, setLane] = useState(1)
  const [count, setCount] = useState({ passed: 0, hit: 0 })
  const laneRef = useRef(1)
  const cones = useRef([])
  const box = useRef(null)
  const done = useRef(false)
  useEffect(() => {
    laneRef.current = lane
  }, [lane])
  useEffect(() => {
    let raf
    let last = performance.now()
    let spawned = 0
    let next = 0.4
    let passed = 0
    let hit = 0
    const step = (t) => {
      const dt = Math.min(0.05, (t - last) / 1000)
      last = t
      next -= dt
      if (next <= 0 && spawned < 14) {
        cones.current.push({ lane: Math.floor(Math.random() * 3), y: -8, id: spawned })
        spawned += 1
        next = Math.max(0.42, 0.95 - spawned * 0.035)
      }
      const speed = 70 + spawned * 4
      for (const c of cones.current) {
        c.y += speed * dt
        if (!c.done && c.y > 78 && c.y < 92 && c.lane === laneRef.current) {
          c.done = true
          c.bad = true
          hit += 1
        } else if (!c.done && c.y >= 92) {
          c.done = true
          passed += 1
        }
      }
      cones.current = cones.current.filter((c) => c.y < 108)
      if (box.current) {
        box.current.innerHTML = cones.current.map((c) => `<i class="mg-cone ${c.bad ? 'is-bad' : ''}" style="left:${16.6 + c.lane * 33.3}%;top:${c.y}%"></i>`).join('')
      }
      setCount((k) => (k.passed === passed && k.hit === hit ? k : { passed, hit }))
      if (spawned >= 14 && cones.current.length === 0) {
        if (!done.current) {
          done.current = true
          onDone(passed / 14)
        }
        return
      }
      raf = requestAnimationFrame(step)
    }
    raf = requestAnimationFrame(step)
    return () => cancelAnimationFrame(raf)
  }, []) // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <div className="mg-dribble">
      <div className="mg-cones" ref={box} />
      <i className="mg-me" style={{ left: `${16.6 + lane * 33.3}%` }} />
      {[0, 1, 2].map((l) => <button key={l} type="button" className="mg-lane" onClick={() => setLane(l)} aria-label={`Faixa ${l + 1}`} />)}
      <span className="mg-score">{count.passed} / 14</span>
    </div>
  )
}

// 7) Pênaltis (treino individual). Toque no gol para escolher o canto e segure CHUTAR para dar força.
// Força baixa: chute fraco, fácil de defender. Força demais: a bola sobe e abre, podendo ir para fora.
// O goleiro escolhe um lado; quando acerta, ainda precisa alcançar a bola (cantos altos e chutes fortes são mais difíceis).
const GOAL = { x0: 12, x1: 88, y0: 8, y1: 44 }
const SPOT = { x: 50, y: 88 }
const clampN = (v, a, b) => Math.max(a, Math.min(b, v))

function Keeper({ pose }) {
  // pose: { x, y, rot } em % do campo; nulo = parado no meio, balançando
  const style = pose ? { left: `${pose.x}%`, top: `${pose.y}%`, transform: `translate(-50%, -100%) rotate(${pose.rot}deg)` } : undefined
  return (
    <div className={`pk-keeper ${pose ? 'is-dive' : ''}`} style={style} aria-hidden="true">
      <svg viewBox="0 0 80 110" width="100%" height="100%">
        <ellipse cx="40" cy="106" rx="20" ry="3" fill="rgba(0,0,0,.35)" />
        <path d="M30 70 26 102h8l6-26 6 26h8l-4-32Z" fill="#0f172a" />
        <path d="M24 100h11v5H22ZM45 100h11l2 5H45Z" fill="#f8fafc" />
        <path d="M22 34c4-5 32-5 36 0l3 38H19Z" fill="#16a34a" />
        <path d="M22 34c4-5 32-5 36 0l1 8H21Z" fill="#15803d" />
        <path d="M23 36 6 14l6-5 18 20ZM57 36 74 14l-6-5-18 20Z" fill="#16a34a" />
        <circle cx="8" cy="9" r="8" fill="#fde047" stroke="#a16207" strokeWidth="1.5" />
        <circle cx="72" cy="9" r="8" fill="#fde047" stroke="#a16207" strokeWidth="1.5" />
        <rect x="35" y="26" width="10" height="8" fill="#e2b488" />
        <circle cx="40" cy="19" r="10" fill="#e2b488" />
        <path d="M30 17c0-9 20-9 20 0-3-4-17-4-20 0Z" fill="#2b1d14" />
        <text x="40" y="60" textAnchor="middle" fontSize="16" fontWeight="900" fill="#fff" fontFamily="var(--font-heading, sans-serif)">1</text>
      </svg>
    </div>
  )
}

function Penalty({ onDone }) {
  const [n, setN] = useState(0)
  const [goals, setGoals] = useState(0)
  const [aim, setAim] = useState({ x: 50, y: 30 })
  const [power, setPower] = useState(0)
  const [shot, setShot] = useState(null) // { x, y, result, keeper:{x,y,rot}, ms }
  const [log, setLog] = useState([])
  const box = useRef(null)
  const aiming = useRef(false)
  const charge = useRef(null)
  const powerRef = useRef(0)
  const done = useRef(false)
  const busy = Boolean(shot) || n >= 5

  const toAim = (e) => {
    const r = box.current.getBoundingClientRect()
    setAim({
      x: clampN(((e.clientX - r.left) / r.width) * 100, GOAL.x0 + 3, GOAL.x1 - 3),
      y: clampN(((e.clientY - r.top) / r.height) * 100, GOAL.y0 + 3, GOAL.y1 - 2),
    })
  }
  const aimDown = (e) => {
    if (busy) return
    aiming.current = true
    e.currentTarget.setPointerCapture?.(e.pointerId)
    toAim(e)
  }
  const aimMove = (e) => aiming.current && !busy && toAim(e)
  const aimUp = () => {
    aiming.current = false
  }

  const stopCharge = () => {
    if (charge.current) cancelAnimationFrame(charge.current)
    charge.current = null
  }
  useEffect(() => stopCharge, [])
  const chargeDown = (e) => {
    if (busy || charge.current) return
    e.currentTarget.setPointerCapture?.(e.pointerId)
    const t0 = performance.now()
    const step = (t) => {
      // sobe em 1,1 s e fica oscilando perto do máximo
      const k = (t - t0) / 1100
      const v = k <= 1 ? k * 100 : 100 - Math.abs(Math.sin((k - 1) * 4)) * 14
      powerRef.current = v
      setPower(v)
      charge.current = requestAnimationFrame(step)
    }
    charge.current = requestAnimationFrame(step)
  }
  const chargeUp = () => {
    if (!charge.current) return
    stopCharge()
    shoot(Math.max(8, powerRef.current))
  }

  const shoot = (pw) => {
    // desvio: força acima de 78 levanta e abre a bola; abaixo disso, pequeno erro natural
    const over = Math.max(0, pw - 78)
    const side = aim.x >= 50 ? 1 : -1
    const x = aim.x + side * over * 0.55 + (Math.random() - 0.5) * 3
    const y = aim.y - over * 1.35 + (Math.random() - 0.5) * 3
    const inside = x > GOAL.x0 + 1.5 && x < GOAL.x1 - 1.5 && y > GOAL.y0 + 1.5
    const zone = x < 38 ? 0 : x > 62 ? 2 : 1
    const weak = pw < 38
    // o goleiro escolhe um lado; chute fraco dá tempo de ele ler a batida
    const read = Math.random() < (weak ? 0.85 : 0.5)
    const guess = read ? zone : [0, 1, 2].filter((z) => z !== zone)[Math.floor(Math.random() * 2)]
    const topCorner = y < GOAL.y0 + 11 && Math.abs(x - 50) > 26
    const reach = guess === zone && Math.random() < (topCorner ? 0.12 : weak ? 0.95 : 0.78 - ((pw - 38) / 62) * 0.38)
    const result = !inside ? 'out' : reach ? 'save' : 'goal'
    const kx = reach ? x : [22, 50, 78][guess] + (Math.random() - 0.5) * 6
    const ky = reach ? Math.max(y + 9, GOAL.y0 + 14) : guess === 1 ? GOAL.y1 : GOAL.y1 - 6
    const rot = guess === 1 && !reach ? 0 : clampN((kx - 50) * 2.4, -78, 78)
    const end = result === 'out' ? { x: clampN(x, -6, 106), y: Math.max(-8, y - 4) } : result === 'save' ? { x: kx + (kx - 50) * 0.08, y: ky - 12 } : { x, y }
    setShot({ ...end, result, keeper: { x: kx, y: ky, rot }, ms: Math.round(520 - pw * 2.6) })
    const g = goals + (result === 'goal' ? 1 : 0)
    setGoals(g)
    setLog((l) => [...l, result])
    setTimeout(() => {
      setShot(null)
      setPower(0)
      powerRef.current = 0
      if (n + 1 >= 5 && !done.current) {
        done.current = true
        onDone(g / 5)
      }
      setN(n + 1)
    }, 1500)
  }

  const zoneClass = power < 38 ? 'is-weak' : power > 78 ? 'is-over' : 'is-good'
  return (
    <div className={`pk ${shot ? `is-${shot.result}` : ''}`}>
      <div className="pk-field" ref={box} onPointerDown={aimDown} onPointerMove={aimMove} onPointerUp={aimUp} onPointerCancel={aimUp}>
        <div className="pk-crowd" />
        <div className="pk-goal"><i className="pk-net" /></div>
        <i className="pk-spot" />
        <Keeper pose={shot?.keeper} />
        {!shot && n < 5 && <i className="pk-aim" style={{ left: `${aim.x}%`, top: `${aim.y}%` }} />}
        <i
          className={`pk-ball ${shot ? 'is-shot' : ''}`}
          style={shot ? { left: `${shot.x}%`, top: `${shot.y}%`, transitionDuration: `${shot.ms}ms` } : { left: `${SPOT.x}%`, top: `${SPOT.y}%` }}
        />
        {shot && <b className="pk-call">{shot.result === 'goal' ? 'GOL!' : shot.result === 'save' ? 'DEFENDEU!' : 'PRA FORA!'}</b>}
        <ol className="pk-log">{[0, 1, 2, 3, 4].map((k) => <li key={k} className={log[k] ? `is-${log[k]}` : k === n ? 'is-now' : ''} />)}</ol>
      </div>
      <div className="pk-ctrl">
        <div className={`pk-power ${zoneClass}`} aria-label="Força do chute">
          <i className="pk-power-good" />
          <em style={{ width: `${power}%` }} />
        </div>
        <button type="button" className="pk-kick" disabled={busy} onPointerDown={chargeDown} onPointerUp={chargeUp} onPointerCancel={chargeUp} onContextMenu={(e) => e.preventDefault()}>
          {power > 0 && !shot ? 'SOLTE!' : 'SEGURE PARA CHUTAR'}
        </button>
      </div>
    </div>
  )
}

export default function MiniGame({ game, onDone }) {
  const [count, setCount] = useState(3)
  useEffect(() => {
    if (count <= 0) return undefined
    const t = setTimeout(() => setCount(count - 1), 700)
    return () => clearTimeout(t)
  }, [count])
  const G = { timing: Timing, reaction: Reaction, passing: Passing, aim: Aim, tackle: Tackle, dribble: Dribble, penalty: Penalty }[game]
  if (count > 0) return <div className="mg-count" aria-live="assertive"><small>{GAMES[game].title}</small>{count}</div>
  return <G onDone={onDone} />
}
