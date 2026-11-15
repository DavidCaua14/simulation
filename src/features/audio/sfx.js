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
let master = null
let meters = null
let crowdEng = null // torcida sintetizada (vozes, cantos, reações)
let ambWanted = 0 // nível do ambiente contínuo pedido pela partida (0 = só reações)
const fileCache = new Map()
const state = { sfxVolume: 0.6, muted: false }

function ensure() {
  if (ctx) return ctx
  const AC = typeof window !== 'undefined' && (window.AudioContext || window.webkitAudioContext)
  if (!AC) return null
  ctx = new AC()
  sfxBus = ctx.createGain()
  ambBus = ctx.createGain()
  // tudo passa por um compressor suave: lances fortes (gol) não estouram e o ambiente não some
  master = ctx.createDynamicsCompressor()
  master.threshold.value = -18
  master.knee.value = 12
  master.ratio.value = 4
  master.attack.value = 0.01
  master.release.value = 0.25
  sfxBus.connect(master)
  ambBus.connect(master)
  master.connect(ctx.destination)
  // medidores (conferência de equilíbrio de volume: torcida × efeitos)
  meters = { sfx: ctx.createAnalyser(), amb: ctx.createAnalyser() }
  meters.sfx.fftSize = 2048
  meters.amb.fftSize = 2048
  sfxBus.connect(meters.sfx)
  ambBus.connect(meters.amb)
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
  if (c && c.state === 'suspended')
    c.resume()
      .then(() => {
        // a partida abriu antes do primeiro toque: a ambientação pedida começa agora
        if (pendingAmb != null) ambienceStart(pendingAmb)
      })
      .catch(() => {})
  else if (c && pendingAmb != null) ambienceStart(pendingAmb)
  return !!c
}
let pendingAmb = null
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

// reação da torcida (vozes sintetizadas — ver "torcida" abaixo). Liga o motor de vozes se preciso,
// mesmo com o ambiente contínuo desligado (aí só as reações soam).
function crowd(kind) {
  const c = crowdStartEngine()
  if (c) c.react(kind)
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
  card_yellow: () => { whistle(0, 0.32, 0.2); crowd('boo') },
  card_red: () => { whistle(0, 0.6, 0.22); crowd('boo_big') },
  goal_for: () => crowd('roar'),
  goal_against: () => crowd('groan'),
  chance: () => crowd('ooh'),
  // campo (instante visual): contato de bola, choques, apito curto, rede e reações da torcida
  touch: () => { tone({ f: 140, f2: 80, dur: 0.06, gain: 0.07 }); noise({ dur: 0.04, gain: 0.03, type: 'lowpass', f: 900, attack: 0.003 }) },
  kick: () => { tone({ f: 120, f2: 55, dur: 0.09, gain: 0.13 }); noise({ dur: 0.06, gain: 0.07, type: 'lowpass', f: 1200, attack: 0.002, release: 0.05 }) },
  shot: () => {
    tone({ f: 110, f2: 45, dur: 0.14, gain: 0.24 })
    noise({ dur: 0.08, gain: 0.14, type: 'lowpass', f: 1800, attack: 0.002, release: 0.07 })
    noise({ at: 0.02, dur: 0.35, gain: 0.05, f: 2400, f2: 900, q: 1.4, attack: 0.03 }) // assobio da bola no ar
  },
  tackle: () => {
    tone({ f: 90, f2: 50, dur: 0.12, gain: 0.12 })
    noise({ dur: 0.16, gain: 0.08, type: 'bandpass', f: 600, q: 0.8, attack: 0.004 }) // chuteiras e grama
    noise({ at: 0.03, dur: 0.18, gain: 0.04, type: 'highpass', f: 2500, attack: 0.01 })
  },
  whistle_short: () => whistle(0, 0.3, 0.2),
  net: () => noise({ dur: 0.5, gain: 0.12, type: 'highpass', f: 1600, f2: 4000, attack: 0.01, release: 0.4 }),
  save: () => {
    tone({ f: 180, f2: 90, dur: 0.07, gain: 0.12 })
    noise({ dur: 0.06, gain: 0.1, type: 'bandpass', f: 1500, q: 1, attack: 0.002 }) // luva
    crowd('ooh')
  },
  ooh: () => crowd('ooh'),
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

// ---------- torcida: vozes sintetizadas, cantos e reações ----------
// Nada de ruído filtrado (soava como chuva): cada "torcedor" é uma voz (onda dente-de-serra com vibrato) passando
// por filtros de formantes de vogal (a/ó/u/é), num estádio (reverberação). O burburinho são sílabas curtas e
// irregulares de cada voz; os CANTOS são as vozes juntas numa melodia, com bumbo e palmas no tempo; as REAÇÕES
// (gol, "uhh", lamento, vaia) mudam vogal, altura e volume de todas as vozes. Melodias criadas aqui (originais).
const VOWEL = { a: [730, 1090], o: [470, 840], u: [330, 760], e: [530, 1650] }
// cantos: graus em semitons a partir da tônica (~Sol2) e duração em colcheias; null = pausa
const CHANTS = [
  { notes: [[0, 2], [0, 1], [2, 1], [4, 2], [2, 2], [0, 2], [null, 2], [7, 2], [5, 1], [4, 1], [2, 2], [0, 4]], vowel: ['o', 'a'] },
  { notes: [[4, 1], [4, 1], [4, 2], [2, 1], [4, 1], [7, 2], [null, 2], [5, 1], [5, 1], [4, 2], [2, 2], [0, 4]], vowel: ['e', 'o'] },
  { notes: [[0, 3], [0, 1], [0, 2], [3, 2], [5, 3], [3, 1], [0, 4], [null, 2], [0, 2], [-2, 2], [0, 4]], vowel: ['o', 'u'] },
  { notes: [[7, 2], [7, 2], [9, 1], [7, 1], [5, 2], [4, 2], [null, 1], [4, 1], [5, 2], [4, 2], [2, 2], [0, 4]], vowel: ['a', 'o'] },
  // "ô-ô-ô" curto de incentivo (repetido duas vezes)
  { notes: [[0, 2], [4, 2], [7, 4], [null, 2], [0, 2], [4, 2], [7, 4], [null, 2]], vowel: ['o', 'o'] },
]
const TEMPO = 118 // batidas por minuto (colcheia = meia batida)

function impulse(sec = 2.2, decay = 3.2) {
  const len = Math.floor(ctx.sampleRate * sec)
  const buf = ctx.createBuffer(2, len, ctx.sampleRate)
  for (let ch = 0; ch < 2; ch += 1) {
    const d = buf.getChannelData(ch)
    for (let i = 0; i < len; i += 1) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, decay)
  }
  return buf
}

function createCrowd() {
  const now = ctx.currentTime
  const out = ctx.createGain()
  // ganho medido na prévia (window.__sfxLevels): burburinho ~-36 dBFS, canto ~-30, grito de gol ~-20,
  // contra chutes/apitos em ~-22 — a torcida fica presente sem cobrir os sons do campo
  out.gain.value = 4
  out.connect(ambBus)
  // estádio: som direto + reverberação longa (cobertura e arquibancadas)
  const tone = ctx.createBiquadFilter()
  tone.type = 'lowpass'
  tone.frequency.value = 2800
  const dry = ctx.createGain()
  dry.gain.value = 0.75
  const verb = ctx.createConvolver()
  verb.buffer = impulse()
  const wet = ctx.createGain()
  wet.gain.value = 0.5
  tone.connect(dry).connect(out)
  tone.connect(verb).connect(wet).connect(out)

  // três grupos de vozes, cada um com seus formantes (vogal)
  const groups = []
  for (let i = 0; i < 3; i += 1) {
    const inG = ctx.createGain()
    const f1 = ctx.createBiquadFilter()
    f1.type = 'bandpass'
    f1.Q.value = 4.5
    f1.frequency.value = VOWEL.o[0]
    const f2 = ctx.createBiquadFilter()
    f2.type = 'bandpass'
    f2.Q.value = 6
    f2.frequency.value = VOWEL.o[1]
    const g2 = ctx.createGain()
    g2.gain.value = 0.55
    inG.connect(f1).connect(tone)
    inG.connect(f2).connect(g2).connect(tone)
    groups.push({ inG, f1, f2 })
  }
  const voices = []
  for (let i = 0; i < 30; i += 1) {
    const o = ctx.createOscillator()
    o.type = 'sawtooth'
    const high = i % 5 === 0 // algumas vozes mais agudas
    const base = high ? 200 + Math.random() * 80 : 98 + Math.random() * 60
    o.frequency.value = base
    o.detune.value = (Math.random() - 0.5) * 40
    const vib = ctx.createOscillator()
    vib.frequency.value = 4.2 + Math.random() * 2.2
    const vg = ctx.createGain()
    vg.gain.value = base * 0.014
    vib.connect(vg).connect(o.frequency)
    const g = ctx.createGain()
    g.gain.value = 0
    o.connect(g).connect(groups[i % 3].inG)
    o.start(now + Math.random() * 0.05)
    vib.start(now)
    voices.push({ o, vib, g, base, high, free: 0 })
  }
  // grave do estádio (multidão distante + vento), bem baixo: dá corpo sem chiado
  const rum = ctx.createBufferSource()
  rum.buffer = noiseBuf
  rum.loop = true
  const rumF = ctx.createBiquadFilter()
  rumF.type = 'lowpass'
  rumF.frequency.value = 180
  const rumG = ctx.createGain()
  rumG.gain.value = 0
  rum.connect(rumF).connect(rumG).connect(out)
  rum.start(now)

  const eng = {
    level: 0, // ambiente contínuo (0..1)
    swell: 0, // expectativa (ataque perto do gol)
    reactUntil: 0, // reação em curso: o burburinho e o canto esperam
    chant: null, // { at, notes, i, vowel, root }
    nextChantAt: now + 6 + Math.random() * 8,
    beat: 0,
    nextBeat: now + 0.3,
    timer: null,
  }

  const setVowel = (v, at, tc = 0.08) => {
    const [a, b] = VOWEL[v] || VOWEL.o
    for (const g of groups) {
      g.f1.frequency.setTargetAtTime(a * (0.95 + Math.random() * 0.1), at, tc)
      g.f2.frequency.setTargetAtTime(b * (0.95 + Math.random() * 0.1), at, tc)
    }
  }

  // burburinho: sílabas curtas, alturas e intervalos irregulares, mais vozes com o jogo quente
  const murmur = (t) => {
    const lv = Math.min(1, eng.level + eng.swell * 0.6)
    if (lv <= 0.01) return
    for (const v of voices) {
      if (t < v.free) continue
      if (Math.random() > 0.25 + lv * 0.5) {
        v.free = t + 0.1 + Math.random() * 0.25
        continue
      }
      const dur = 0.12 + Math.random() * 0.35
      const amp = (0.024 + Math.random() * 0.03) * lv * (1 + eng.swell * 0.8)
      const pitch = v.base * (0.9 + Math.random() * 0.25) * (1 + eng.swell * 0.12)
      v.o.frequency.setTargetAtTime(pitch, t, 0.04)
      v.g.gain.setTargetAtTime(amp, t, 0.03)
      v.g.gain.setTargetAtTime(0, t + dur, 0.06)
      v.free = t + dur + 0.05 + Math.random() * 0.4
    }
    if (Math.random() < 0.08) setVowel(['a', 'o', 'e', 'u'][Math.floor(Math.random() * 4)], t, 0.3)
  }

  // canto: as vozes em uníssono (graves) e oitava (agudas), com leve desafinação de multidão
  const singNote = (t, semi, dur, vowel) => {
    const root = 98 * Math.pow(2, eng.chant.root / 12)
    const amp = (0.022 + eng.level * 0.03) * (1 + eng.swell * 0.4)
    setVowel(vowel, t, 0.05)
    for (const v of voices) {
      if (semi == null) {
        v.g.gain.setTargetAtTime(0.002, t, 0.05)
        continue
      }
      const f = root * Math.pow(2, semi / 12) * (v.high ? 2 : 1) * (1 + (Math.random() - 0.5) * 0.025)
      v.o.frequency.setTargetAtTime(f, t, 0.035)
      v.g.gain.setTargetAtTime(amp * (0.7 + Math.random() * 0.6), t + Math.random() * 0.04, 0.03)
      v.g.gain.setTargetAtTime(amp * 0.4, t + dur * 0.8, 0.05)
    }
  }

  const clap = (t, g) => {
    for (let k = 0; k < 3; k += 1) noise({ at: Math.max(0, t - ctx.currentTime) + k * 0.008, dur: 0.05, gain: g, type: 'bandpass', f: 1400 + k * 500, q: 1.2, attack: 0.002, release: 0.04, out })
  }
  const drum = (t, g) => tone({ f: 72, f2: 44, dur: 0.24, gain: g, at: Math.max(0, t - ctx.currentTime), out })

  const loop = () => {
    const t = ctx.currentTime
    const ahead = t + 0.3
    const hot = Math.min(1, eng.level + eng.swell * 0.5)
    rumG.gain.setTargetAtTime(0.025 + hot * 0.05, t, 0.8)
    if (t >= eng.reactUntil) {
      // começa um canto de tempos em tempos (mais frequente com o jogo quente)
      if (!eng.chant && eng.level > 0.05 && t > eng.nextChantAt) {
        const c = CHANTS[Math.floor(Math.random() * CHANTS.length)]
        eng.chant = { notes: c.notes, vowel: c.vowel, i: 0, at: t + 0.2, root: Math.floor(Math.random() * 4) - 1, reps: 1 + Math.floor(Math.random() * 2) }
      }
      if (eng.chant) {
        const ch = eng.chant
        while (ch.at < ahead) {
          if (ch.i >= ch.notes.length) {
            ch.reps -= 1
            ch.i = 0
            if (ch.reps <= 0) {
              eng.chant = null
              eng.nextChantAt = t + 14 + Math.random() * 22 - hot * 8
              for (const v of voices) v.g.gain.setTargetAtTime(0, ch.at, 0.15)
              break
            }
          }
          const [semi, len] = ch.notes[ch.i]
          const dur = (len * 60) / TEMPO / 2
          singNote(ch.at, semi, dur, ch.vowel[ch.i % 2])
          ch.at += dur
          ch.i += 1
        }
      } else murmur(t)
    }
    // bumbo e palmas no tempo (organizadas); palmas só cantando ou com o jogo quente
    while (eng.nextBeat < ahead) {
      const step = eng.beat % 8
      const lv = eng.level
      if (lv > 0.05) {
        if (step === 0 || step === 3 || step === 4 || (hot > 0.6 && step === 6)) drum(eng.nextBeat, 0.035 + lv * 0.09)
        if ((eng.chant || hot > 0.55) && (step === 2 || step === 6)) clap(eng.nextBeat, 0.012 + lv * 0.03)
      }
      eng.beat += 1
      eng.nextBeat += 60 / TEMPO / 2
    }
  }
  eng.timer = setInterval(() => {
    try {
      loop()
    } catch {
      /* som é enfeite */
    }
  }, 90)

  // reações (instante do lance): todas as vozes juntas
  eng.react = (kind) => {
    const t = ctx.currentTime
    const shape = {
      roar: { vowel: 'a', amp: 0.075, up: 1.4, dur: 3.6, attack: 0.08 },
      groan: { vowel: 'o', amp: 0.03, up: 0.82, dur: 1.6, attack: 0.15 },
      ooh: { vowel: 'u', amp: 0.04, up: 1.28, dur: 1.4, attack: 0.12, fall: true },
      boo: { vowel: 'u', amp: 0.022, up: 0.78, dur: 1.3, attack: 0.15 },
      boo_big: { vowel: 'u', amp: 0.035, up: 0.75, dur: 2.0, attack: 0.15 },
    }[kind]
    if (!shape) return
    eng.chant = null
    eng.reactUntil = t + shape.dur + 0.3
    setVowel(shape.vowel, t, 0.06)
    if (kind === 'roar') setTimeout(() => setVowel('o', ctx.currentTime, 0.4), 1600)
    for (const v of voices) {
      const f0 = v.base * (0.95 + Math.random() * 0.1)
      v.o.frequency.cancelScheduledValues(t)
      v.o.frequency.setTargetAtTime(f0 * shape.up, t + Math.random() * 0.08, shape.attack * 2)
      if (shape.fall) v.o.frequency.setTargetAtTime(f0 * 0.92, t + shape.dur * 0.5, 0.25)
      v.g.gain.cancelScheduledValues(t)
      v.g.gain.setTargetAtTime(shape.amp * (0.6 + Math.random() * 0.7), t + Math.random() * 0.06, shape.attack)
      v.g.gain.setTargetAtTime(0, t + shape.dur * (0.75 + Math.random() * 0.3), 0.35)
      v.free = t + shape.dur
    }
    if (kind === 'roar') {
      // festa: bumbo dobrado por alguns segundos
      for (let k = 0; k < 12; k += 1) drum(t + 0.4 + k * 0.25, 0.12)
      eng.nextChantAt = t + shape.dur + 0.5 // depois do grito, o canto da festa
    }
  }
  eng.stop = () => {
    clearInterval(eng.timer)
    const t = ctx.currentTime
    out.gain.setTargetAtTime(0, t, 0.4)
    setTimeout(() => {
      for (const v of voices) {
        try {
          v.o.stop()
          v.vib.stop()
        } catch {
          /* já parado */
        }
      }
      try {
        rum.stop()
      } catch {
        /* já parado */
      }
      out.disconnect()
    }, 1800)
  }
  return eng
}

function crowdStartEngine() {
  if (!ready()) return null
  if (!crowdEng) crowdEng = createCrowd()
  return crowdEng
}

// ---------- ambientação contínua de estádio (API usada pelo AudioContext/partida) ----------
export function ambienceStart(level = 0.35) {
  ambWanted = level
  if (!ready()) {
    pendingAmb = level // começa no primeiro toque (o navegador bloqueia som antes)
    return
  }
  pendingAmb = null
  const c = crowdStartEngine()
  if (c) c.level = level
}

export function ambienceLevel(level) {
  if (pendingAmb != null) pendingAmb = level
  if (!ambWanted && !pendingAmb) return
  ambWanted = level
  if (crowdEng) crowdEng.level = level
}

// expectativa da torcida (0..1): sobe quando o ataque chega perto do gol e cai devagar
export function ambienceSwell(v) {
  if (crowdEng) crowdEng.swell = Math.max(0, Math.min(1, v))
}

export function ambienceStop() {
  pendingAmb = null
  ambWanted = 0
  if (!crowdEng) return
  crowdEng.stop()
  crowdEng = null
}

// equilíbrio de volume (conferência): RMS em dBFS da torcida e dos efeitos neste instante
export function busLevels() {
  if (!meters) return null
  const rms = (an) => {
    const buf = new Float32Array(an.fftSize)
    an.getFloatTimeDomainData(buf)
    let s = 0
    for (const x of buf) s += x * x
    const r = Math.sqrt(s / buf.length)
    return r > 0 ? 20 * Math.log10(r) : -120
  }
  return { crowd: rms(meters.amb), sfx: rms(meters.sfx), running: Boolean(crowdEng), level: crowdEng?.level ?? 0, state: ctx?.state }
}

export const SFX_IDS = Object.keys(SYNTH)

// conferência na prévia local: nível da torcida × efeitos (npm run dev)
if (import.meta.env?.DEV && typeof window !== 'undefined') Object.assign(window, { __sfxLevels: busLevels, __sfxPlay: play })
