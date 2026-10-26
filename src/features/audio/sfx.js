// ─────────────────────────────────────────────────────────────────────────────
// EFEITOS SONOROS E AMBIENTAÇÃO DE PARTIDA (Web Audio API)
//
// Todos os sons são SINTETIZADOS aqui (osciladores e ruído filtrado): são criação original do jogo, sem
// gravação de terceiros — não há questão de licença. Quando houver gravações licenciadas, basta colocar o arquivo
// em public/audio/sfx/ e apontar em SFX_FILES (sfxConfig.js): o arquivo passa a ser usado no lugar do som sintetizado.
//
// Navegadores bloqueiam áudio antes de um gesto do usuário: o contexto só é criado/retomado em `unlock()`,
// chamado no primeiro toque/tecla. Antes disso, play() simplesmente não toca (nunca dá erro).
// ─────────────────────────────────────────────────────────────────────────────
import { SFX_FILES } from './sfxConfig'

const BASE = import.meta.env?.BASE_URL ?? '/'
let ctx = null
let sfxBus = null
let ambBus = null
let noiseBuf = null
let amb = null // { nodes, level }
const fileCache = new Map()
const state = { sfxVolume: 0.6, muted: false }

function ensure() {
  if (ctx) return ctx
  const AC = typeof window !== 'undefined' && (window.AudioContext || window.webkitAudioContext)
  if (!AC) return null
  ctx = new AC()
  sfxBus = ctx.createGain()
  ambBus = ctx.createGain()
  sfxBus.connect(ctx.destination)
  ambBus.connect(ctx.destination)
  noiseBuf = ctx.createBuffer(1, ctx.sampleRate * 2, ctx.sampleRate)
  const d = noiseBuf.getChannelData(0)
  for (let i = 0; i < d.length; i += 1) d[i] = Math.random() * 2 - 1
  applyVolume()
  return ctx
}

function applyVolume() {
  if (!ctx) return
  const v = state.muted ? 0 : state.sfxVolume
  sfxBus.gain.setTargetAtTime(v, ctx.currentTime, 0.02)
  ambBus.gain.setTargetAtTime(v, ctx.currentTime, 0.2)
}

export function setSfxVolume(v01) {
  state.sfxVolume = Math.max(0, Math.min(1, v01))
  applyVolume()
}
export function setSfxMuted(m) {
  state.muted = !!m
  applyVolume()
}

// Chamado a partir de um gesto do usuário (toque/tecla). Seguro chamar várias vezes.
export function unlock() {
  const c = ensure()
  if (c && c.state === 'suspended') c.resume().catch(() => {})
  return !!c
}
const ready = () => ctx && ctx.state === 'running'

// ---------- blocos de síntese ----------
function tone({ f, f2, dur = 0.15, type = 'sine', gain = 0.3, at = 0, attack = 0.005, out = sfxBus }) {
  const t = ctx.currentTime + at
  const o = ctx.createOscillator()
  const g = ctx.createGain()
  o.type = type
  o.frequency.setValueAtTime(f, t)
  if (f2) o.frequency.exponentialRampToValueAtTime(f2, t + dur)
  g.gain.setValueAtTime(0.0001, t)
  g.gain.exponentialRampToValueAtTime(gain, t + attack)
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur)
  o.connect(g).connect(out)
  o.start(t)
  o.stop(t + dur + 0.05)
}

function noise({ dur = 0.5, gain = 0.3, at = 0, type = 'bandpass', f = 1000, f2, q = 1, attack = 0.05, release, out = sfxBus }) {
  const t = ctx.currentTime + at
  const src = ctx.createBufferSource()
  src.buffer = noiseBuf
  src.loop = true
  const flt = ctx.createBiquadFilter()
  flt.type = type
  flt.frequency.setValueAtTime(f, t)
  if (f2) flt.frequency.exponentialRampToValueAtTime(f2, t + dur)
  flt.Q.value = q
  const g = ctx.createGain()
  g.gain.setValueAtTime(0.0001, t)
  g.gain.exponentialRampToValueAtTime(gain, t + attack)
  g.gain.setValueAtTime(gain, t + Math.max(attack, dur - (release ?? dur * 0.6)))
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur)
  src.connect(flt).connect(g).connect(out)
  src.start(t, Math.random())
  src.stop(t + dur + 0.05)
}

// apito de árbitro: ~2,9 kHz com trinado rápido (a "ervilha" do apito)
function whistle(at = 0, dur = 0.45, gain = 0.22) {
  const t = ctx.currentTime + at
  const o = ctx.createOscillator()
  const lfo = ctx.createOscillator()
  const lfoGain = ctx.createGain()
  const g = ctx.createGain()
  o.type = 'sine'
  o.frequency.value = 2900
  lfo.frequency.value = 32
  lfoGain.gain.value = 140
  lfo.connect(lfoGain).connect(o.frequency)
  g.gain.setValueAtTime(0.0001, t)
  g.gain.exponentialRampToValueAtTime(gain, t + 0.02)
  g.gain.setValueAtTime(gain, t + dur - 0.05)
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur)
  o.connect(g).connect(sfxBus)
  o.start(t)
  lfo.start(t)
  o.stop(t + dur + 0.05)
  lfo.stop(t + dur + 0.05)
  noise({ at, dur, gain: gain * 0.15, f: 3000, q: 4 })
}

// torcida: ruído em várias faixas (vozes), com envelope
function crowd({ at = 0, dur = 2.5, gain = 0.5, attack = 0.2, bright = 1 }) {
  noise({ at, dur, gain, f: 650 * bright, q: 0.6, attack, release: dur * 0.7 })
  noise({ at, dur, gain: gain * 0.6, f: 1400 * bright, q: 0.8, attack, release: dur * 0.6 })
  noise({ at, dur, gain: gain * 0.35, f: 2600 * bright, q: 1.2, attack: attack * 1.3, release: dur * 0.5 })
}

// ---------- catálogo de sons ----------
const SYNTH = {
  click: () => tone({ f: 1250, dur: 0.035, type: 'square', gain: 0.05 }),
  select: () => { tone({ f: 660, dur: 0.07, type: 'triangle', gain: 0.12 }); tone({ f: 990, dur: 0.09, type: 'triangle', gain: 0.1, at: 0.05 }) },
  open: () => noise({ dur: 0.22, gain: 0.08, f: 400, f2: 2200, q: 1.5, attack: 0.04 }),
  notify: () => { tone({ f: 880, dur: 0.18, gain: 0.16 }); tone({ f: 1320, dur: 0.3, gain: 0.14, at: 0.12 }) },
  purchase: () => [1318.5, 1760, 2093].forEach((f, i) => tone({ f, dur: 0.28, type: 'triangle', gain: 0.14, at: i * 0.06 })),
  reward: () => [523.25, 659.25, 783.99, 1046.5].forEach((f, i) => tone({ f, dur: i === 3 ? 0.6 : 0.2, type: 'triangle', gain: 0.16, at: i * 0.09 })),
  levelup: () => {
    ;[392, 523.25, 659.25, 783.99, 1046.5, 1318.5].forEach((f, i) => tone({ f, dur: i === 5 ? 0.8 : 0.18, type: 'square', gain: 0.07, at: i * 0.07 }))
    noise({ at: 0.35, dur: 0.8, gain: 0.05, type: 'highpass', f: 6000, attack: 0.1 })
  },
  // partida
  kickoff: () => whistle(0, 0.9),
  whistle_half: () => { whistle(0, 0.5); whistle(0.65, 0.8) },
  whistle_end: () => { whistle(0, 0.35); whistle(0.5, 0.35); whistle(1.0, 1.0) },
  foul: () => whistle(0, 0.28, 0.18),
  card_yellow: () => { whistle(0, 0.32, 0.2); crowd({ at: 0.3, dur: 1.2, gain: 0.18, attack: 0.3, bright: 0.7 }) },
  card_red: () => { whistle(0, 0.6, 0.22); noise({ at: 0.4, dur: 1.8, gain: 0.3, type: 'lowpass', f: 450, q: 0.7, attack: 0.3 }) },
  goal_for: () => { crowd({ dur: 3.4, gain: 0.75, attack: 0.12, bright: 1.15 }); tone({ f: 233, dur: 0.9, type: 'sawtooth', gain: 0.05, at: 0.3 }) },
  goal_against: () => { crowd({ dur: 2.2, gain: 0.35, attack: 0.2, bright: 0.9 }); noise({ at: 0.2, dur: 1.6, gain: 0.22, type: 'lowpass', f: 380, attack: 0.25 }) },
  chance: () => noise({ dur: 1.3, gain: 0.32, f: 500, f2: 1100, q: 0.9, attack: 0.25, release: 0.7 }),
}

async function playFile(id) {
  const path = SFX_FILES[id]
  if (!path) return false
  try {
    let buf = fileCache.get(id)
    if (!buf) {
      const res = await fetch(BASE + path.replace(/^\//, ''))
      if (!res.ok) throw new Error(String(res.status))
      buf = await ctx.decodeAudioData(await res.arrayBuffer())
      fileCache.set(id, buf)
    }
    const src = ctx.createBufferSource()
    src.buffer = buf
    src.connect(sfxBus)
    src.start()
    return true
  } catch {
    SFX_FILES[id] = null // arquivo ausente: usa o sintetizado daqui para frente
    return false
  }
}

const lastAt = new Map()
export function play(id) {
  if (!ready() || state.muted || state.sfxVolume <= 0) return
  const now = performance.now()
  if (now - (lastAt.get(id) || 0) < 60) return // evita empilhar o mesmo som em cliques repetidos
  lastAt.set(id, now)
  if (SFX_FILES[id]) {
    playFile(id).then((ok) => { if (!ok) SYNTH[id]?.() })
    return
  }
  try {
    SYNTH[id]?.()
  } catch {
    /* som é enfeite: nunca atrapalha o jogo */
  }
}

// ---------- ambientação contínua de estádio ----------
export function ambienceStart(level = 0.35) {
  if (!ready() || amb) return
  const nodes = []
  const mk = (f, q, g0) => {
    const src = ctx.createBufferSource()
    src.buffer = noiseBuf
    src.loop = true
    const flt = ctx.createBiquadFilter()
    flt.type = 'bandpass'
    flt.frequency.value = f
    flt.Q.value = q
    const g = ctx.createGain()
    g.gain.value = 0
    // ondulação lenta (a torcida "respira")
    const lfo = ctx.createOscillator()
    const lg = ctx.createGain()
    lfo.frequency.value = 0.07 + Math.random() * 0.08
    lg.gain.value = g0 * 0.35
    lfo.connect(lg).connect(g.gain)
    src.connect(flt).connect(g).connect(ambBus)
    src.start(0, Math.random() * 1.5)
    lfo.start()
    nodes.push({ src, lfo, g, base: g0 })
  }
  mk(420, 0.5, 0.5)
  mk(900, 0.7, 0.32)
  mk(1800, 1.1, 0.14)
  amb = { nodes, level: 0 }
  ambienceLevel(level)
}

export function ambienceLevel(level) {
  if (!amb || !ctx) return
  amb.level = level
  amb.nodes.forEach((n) => n.g.gain.setTargetAtTime(n.base * level, ctx.currentTime, 0.8))
}

export function ambienceStop() {
  if (!amb || !ctx) return
  const nodes = amb.nodes
  amb = null
  nodes.forEach((n) => n.g.gain.setTargetAtTime(0, ctx.currentTime, 0.4))
  setTimeout(() => nodes.forEach((n) => { try { n.src.stop(); n.lfo.stop() } catch { /* já parado */ } }), 1800)
}

export const SFX_IDS = Object.keys(SYNTH)
