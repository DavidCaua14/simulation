import { useEffect, useRef, useState } from 'react'
import { Check, Sparkles } from 'lucide-react'
import GameIcon from '../../../components/ui/GameIcon'
import { useAudio } from '../../audio/AudioContext'
import { COMP_LOGO, HONOR_ART, honorOf } from '../honors'
import GoldenWhistle from './GoldenWhistle'
import './champion.css'

const fmt = (n) => Number(n || 0).toLocaleString('pt-BR')
const COLORS = ['#facc15', '#fde68a', '#ffffff', '#22c55e', '#38bdf8', '#f97316', '#e11d48']

// Confete caindo e girando (canvas), com rajadas laterais como os canhões de papel picado do estádio.
function useConfetti(ref, on) {
  useEffect(() => {
    const cv = ref.current
    if (!cv || !on) return undefined
    if (window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) return undefined
    const ctx = cv.getContext('2d')
    let w = 0
    let h = 0
    const fit = () => {
      const r = window.devicePixelRatio || 1
      w = cv.clientWidth
      h = cv.clientHeight
      cv.width = w * r
      cv.height = h * r
      ctx.setTransform(r, 0, 0, r, 0, 0)
    }
    fit()
    window.addEventListener('resize', fit)
    const bits = []
    const burst = (x, dir, n) => {
      for (let i = 0; i < n; i += 1) {
        bits.push({ x, y: h * 0.9, vx: dir * (2 + Math.random() * 5), vy: -(9 + Math.random() * 8), r: Math.random() * Math.PI, vr: (Math.random() - 0.5) * 0.3,
          s: 5 + Math.random() * 6, c: COLORS[(Math.random() * COLORS.length) | 0], life: 0 })
      }
    }
    const rain = () => {
      bits.push({ x: Math.random() * w, y: -10, vx: (Math.random() - 0.5) * 1.2, vy: 1.5 + Math.random() * 2, r: Math.random() * Math.PI, vr: (Math.random() - 0.5) * 0.2,
        s: 4 + Math.random() * 6, c: COLORS[(Math.random() * COLORS.length) | 0], life: 0 })
    }
    burst(0, 1, 90)
    burst(w, -1, 90)
    const again = setInterval(() => { burst(0, 1, 40); burst(w, -1, 40) }, 2600)
    let raf = 0
    const tick = () => {
      if (bits.length < 260) for (let i = 0; i < 3; i += 1) rain()
      ctx.clearRect(0, 0, w, h)
      for (let i = bits.length - 1; i >= 0; i -= 1) {
        const b = bits[i]
        b.vy = Math.min(b.vy + 0.18, 3.2)
        b.vx *= 0.99
        b.x += b.vx + Math.sin((b.life += 1) / 12) * 0.6
        b.y += b.vy
        b.r += b.vr
        if (b.y > h + 20) { bits.splice(i, 1); continue }
        ctx.save()
        ctx.translate(b.x, b.y)
        ctx.rotate(b.r)
        ctx.scale(1, Math.cos(b.life / 6))
        ctx.fillStyle = b.c
        ctx.fillRect(-b.s / 2, -b.s / 4, b.s, b.s / 2)
        ctx.restore()
      }
      raf = requestAnimationFrame(tick)
    }
    raf = requestAnimationFrame(tick)
    return () => {
      cancelAnimationFrame(raf)
      clearInterval(again)
      window.removeEventListener('resize', fit)
    }
  }, [ref, on])
}

// Torcida: fileiras de cabeças com bandeiras e flashes de câmera.
function Crowd() {
  const heads = Array.from({ length: 34 }, (_, i) => i)
  return (
    <div className="ch-crowd" aria-hidden="true">
      {[0, 1].map((row) => (
        <div key={row} className={`ch-row r${row}`}>
          {heads.map((i) => <i key={i} style={{ animationDelay: `${((i * 37 + row * 13) % 10) / 10}s` }} />)}
        </div>
      ))}
      {Array.from({ length: 6 }, (_, i) => <b key={i} className="ch-flag" style={{ left: `${8 + i * 16}%`, animationDelay: `${i * 0.23}s` }} />)}
      {Array.from({ length: 14 }, (_, i) => <em key={i} className="ch-flash" style={{ left: `${(i * 53) % 100}%`, bottom: `${8 + ((i * 29) % 26)}%`, animationDelay: `${(i * 0.41) % 3}s` }} />)}
    </div>
  )
}

// Comemoração de título: aparece quando o técnico tem um comunicado de campeão (insígnia na premiação).
// notice: item da caixa de entrada; onClaim(): resgata (promessa); onClose(): fecha.
export default function ChampionCelebration({ notice, onClaim, onClose }) {
  const honor = honorOf(notice.reward)
  const cv = useRef(null)
  const [stage, setStage] = useState(0) // 0 entrada, 1 título, 2 prêmios
  const [claimed, setClaimed] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const { playSfx } = useAudio()
  useConfetti(cv, true)
  useEffect(() => {
    playSfx('whistle_end')
    const a = setTimeout(() => { setStage(1); playSfx('goal_for') }, 700)
    const b = setTimeout(() => { setStage(2); playSfx('levelup') }, 2300)
    return () => { clearTimeout(a); clearTimeout(b) }
  }, [playSfx])
  const r = notice.reward || {}
  const cash = /\$ ([\d.]+)/.exec(notice.body || '')?.[1]
  const items = [
    cash && { k: 'cash', icon: <span className="ch-cash">$</span>, v: `$ ${cash}`, l: 'no caixa do clube' },
    r.diamonds && { k: 'diamonds', icon: <GameIcon name="diamond" size={30} />, v: fmt(r.diamonds), l: 'diamantes' },
    r.bonus_energy && { k: 'energy', icon: <GameIcon name="energy" size={30} />, v: fmt(r.bonus_energy), l: 'de energia' },
    r.xp && { k: 'xp', icon: <span className="ch-xp">XP</span>, v: fmt(r.xp), l: 'de experiência' },
    r.golden_whistle && { k: 'gw', icon: <GoldenWhistle size={34} />, v: fmt(r.golden_whistle), l: 'Apito de Ouro' },
  ].filter(Boolean)
  const claim = () => {
    setBusy(true)
    setError('')
    Promise.resolve(onClaim?.())
      .then(() => { setClaimed(true); playSfx('reward') })
      .catch((e) => setError(e.message))
      .finally(() => setBusy(false))
  }
  const comp = honor?.comp === 'L' ? 'Liga Online' : 'Copa Online'
  return (
    <div className={`ch-wrap s${stage} ${honor?.first ? 'is-first' : ''} ${honor?.comp === 'L' ? 'is-league' : 'is-cup'}`} role="dialog" aria-modal="true" aria-label={notice.title}>
      <div className="ch-sky" aria-hidden="true">
        <span className="ch-beam b1" /><span className="ch-beam b2" /><span className="ch-beam b3" /><span className="ch-beam b4" />
        {[0, 1, 2, 3, 4].map((i) => <span key={i} className="ch-firework" style={{ left: `${12 + i * 19}%`, top: `${10 + ((i * 17) % 22)}%`, animationDelay: `${0.8 + i * 0.55}s` }} />)}
      </div>
      <Crowd />
      <canvas ref={cv} className="ch-confetti" aria-hidden="true" />
      <div className="ch-stage">
        <div className="ch-trophy">
          <span className="ch-glow" aria-hidden="true" />
          <img src={HONOR_ART[honor?.id] || COMP_LOGO[honor?.comp || 'C']} alt={honor?.label || comp} />
        </div>
        <div className="ch-title">
          <small>{comp}{honor?.first ? ' · primeira edição' : ''}</small>
          <h2 aria-label="Campeão">{'CAMPEÃO!'.split('').map((c, i) => <span key={i} style={{ animationDelay: `${0.75 + i * 0.06}s` }}>{c}</span>)}</h2>
          <p>{notice.title}</p>
        </div>
        <div className="ch-prizes">
          {honor && (
            <div className="ch-prize is-honor" style={{ animationDelay: '0s' }}>
              <img src={HONOR_ART[honor.id]} alt="" />
              <span><b>Insígnia {honor.first ? 'rara' : ''}</b><small>{honor.label}</small></span>
            </div>
          )}
          {items.map((it, i) => (
            <div key={it.k} className="ch-prize" style={{ animationDelay: `${0.15 + i * 0.15}s` }}>
              <i>{it.icon}</i>
              <span><b>{it.v}</b><small>{it.l}</small></span>
            </div>
          ))}
        </div>
        {error && <p className="ch-error">{error}</p>}
        <div className="ch-actions">
          {!claimed ? (
            <>
              <button type="button" className="ch-claim" disabled={busy} onClick={claim}><Sparkles size={18} /> {busy ? 'Resgatando…' : 'Resgatar prêmios'}</button>
              <button type="button" className="ch-later" disabled={busy} onClick={onClose}>Depois (fica na caixa de entrada)</button>
            </>
          ) : (
            <>
              <p className="ch-done"><Check size={18} /> Prêmios recebidos! A insígnia já está no seu perfil.</p>
              <button type="button" className="ch-claim" onClick={onClose}>Continuar</button>
            </>
          )}
        </div>
      </div>
    </div>
  )
}
