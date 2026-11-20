import { useEffect, useMemo, useRef, useState } from 'react'
import ClubCrest from '../club/components/ClubCrest'
import { getClubById } from '../club/data/clubs'
import { createDirector, L, W } from '../match2d/director'
import { createFieldAudio, dangerOf } from '../audio/fieldSounds'
import { eventText } from '../seasons/utils/managerUtils'
import { THREE, colorDist, createAthlete, createKitMaterials, createScene, poseAthlete, toWorld } from './scene3d'
import { createPlayerRig, loadPlayerAssets, poseKayPlayer } from './players3d'
import { createBallTrail, createKickRing, createSpriteFactory, pixelPitchTexture } from './pixel3d'
import { stadiumById, stadiumFor } from './stadiums'
import './match3d.css'

// Transmissão 3D (protótipo). Mesmas props do campo 2D (MatchTactical2D): o diretor é o mesmo,
// só muda o desenho — estádio, atletas articulados e uma câmera de TV que acompanha a jogada.
// onHold(minuto|null): o relógio da partida não passa do lance que ainda está em campo.
// onReveal(seqs): lances que o campo acabou de mostrar (o placar conta na hora).

const KEEPER_COLORS = ['#22c55e', '#f472b6', '#f97316', '#eab308', '#a855f7', '#06b6d4']
const REF_COLORS = ['#111827', '#facc15', '#ec4899', '#14b8a6']

const lerp = (a, b, k) => a + (b - a) * k

function farthest(list, avoid) {
  return [...list].sort((a, b) => Math.min(...avoid.map((c) => colorDist(b, c))) - Math.min(...avoid.map((c) => colorDist(a, c))))[0]
}

// Distância de cor perceptual ("redmean"): 0 a ~765. Vermelho e vinho ficam perto; vermelho e preto, longe.
function kitDist(a, b) {
  const ca = new THREE.Color(a)
  const cb = new THREE.Color(b)
  const r = ((ca.r + cb.r) / 2) * 255
  const dr = (ca.r - cb.r) * 255
  const dg = (ca.g - cb.g) * 255
  const db = (ca.b - cb.b) * 255
  return Math.sqrt((2 + r / 256) * dr * dr + 4 * dg * dg + (2 + (255 - r) / 256) * db * db)
}
const KIT_OK = 200 // abaixo disso, na câmera aberta do celular, os dois times se confundem
// Uniformes que se distinguem na TV: compara camisa com camisa E camisa com calção do outro (vermelho/preto
// contra preto/vermelho também confunde). Se o visitante não se distinguir, usa o segundo uniforme ou um reserva.
function kitsFor(hc, ac) {
  const h0 = hc[0] || '#c8102e'
  const h1 = hc[1] || '#ffffff'
  // camisa contra camisa; e o uniforme invertido (camisa ≈ calção do outro E calção ≈ camisa do outro)
  const score = ([s0, s1]) => Math.min(kitDist(s0, h0), Math.max(kitDist(s0, h1), kitDist(s1, h0)) * 2)
  const own = [ac[0] || '#1d4ed8', ac[1] || '#ffffff']
  const options = [own, [own[1], own[0]], ['#f4f4f4', '#f4f4f4'], ['#f4f4f4', '#111827'], ['#1e3a8a', '#ffffff'], ['#111827', '#111827'], ['#facc15', '#111827'], ['#0ea5e9', '#ffffff']]
  const pick = options.find((o) => score(o) >= KIT_OK) || [...options].sort((x, y) => score(y) - score(x))[0]
  const [a0, a1] = pick
  const gkH = farthest(KEEPER_COLORS, [h0, a0, h1, a1])
  const gkA = farthest(KEEPER_COLORS.filter((c) => c !== gkH), [h0, a0, h1, a1, gkH])
  const ref = farthest(REF_COLORS, [h0, a0, gkH, gkA])
  return { h: [h0, h1, h0], a: [a0, a1, a0], gkH, gkA, ref }
}

// onUnavailable(): o aparelho não abriu o WebGL — a tela segue só com o placar
// pixel: modo 2.5D (gramado e atletas em pixel art, imagem em baixa resolução ampliada sem suavizar)
export default function MatchBroadcast3D({ data, catalog, clock, events, paused, speed = 1, minute, score, finished, clockLabel, userSide, onHold, onReveal, onUnavailable, clubs, pixel = false, stadium = null }) {
  const wrap = useRef(null)
  const canvas = useRef(null)
  const labelRef = useRef(null)
  const clockRef = useRef(null)
  // MELHORES MOMENTOS: o campo só aparece nos lances (roteiro do diretor), em tempo real e com relógio em segundos;
  // entre um lance e outro uma tela cobre o campo e o jogo avança rápido por baixo
  const [cut, setCut] = useState(false)
  const [hlKey, setHlKey] = useState(0)
  const introUntil = useRef(Infinity) // definido no efeito do tempo (abaixo), ao montar
  const seen = useRef(new Set())
  const [ready, setReady] = useState(false)
  const [failed, setFailed] = useState(false)
  const [caption, setCaption] = useState(null)
  const [fly, setFly] = useState(Boolean(pixel))
  const live = useRef({ paused, speed, minute, clockLabel })
  useEffect(() => {
    live.current = { paused, speed, minute, clockLabel }
  }, [paused, speed, minute, clockLabel])

  const home = clubs?.home || getClubById(data.home)
  const away = clubs?.away || getClubById(data.away)
  const hc = (clubs?.home?.colors || getClubById(data.home)?.colors || []).join()
  const ac = (clubs?.away?.colors || getClubById(data.away)?.colors || []).join()
  const kits = useMemo(() => kitsFor(hc ? hc.split(',') : [], ac ? ac.split(',') : []), [hc, ac])
  const names = useMemo(() => ({ h: home?.short || home?.name || 'Casa', a: away?.short || away?.name || 'Visitante' }), [home?.short, home?.name, away?.short, away?.name])
  // estádio do modo pixel: o pedido (id) ou o do mandante (sempre o mesmo para o mesmo clube)
  const stadiumDef = useMemo(() => (stadium ? stadiumById(stadium) : stadiumFor(data.home)), [stadium, data.home])
  const view = useRef({ userSide })
  useEffect(() => {
    view.current = { userSide }
  }, [userSide])

  // diretor (só apresentação): criado uma vez por partida — o mesmo do campo 2D
  const [dir] = useState(() => {
    const d = createDirector({ formations: catalog?.byId, homeId: data.home, awayId: data.away, highlights: true })
    d.sync(data.players || [], data.formation)
    d.kickoff('h')
    return d
  })
  const director = useRef(dir)
  useEffect(() => {
    if (import.meta.env.DEV) window.__campo3d = dir
  }, [dir])
  useEffect(() => {
    director.current?.sync(data.players || [], data.formation)
  }, [data.players, data.formation])
  useEffect(() => {
    const poss = data.stats?.poss?.[0]
    director.current?.setPossession(poss ? poss / 100 : 0.5)
  }, [data.stats])
  const styleH = data.tactics?.h?.style
  const styleA = data.tactics?.a?.style
  useEffect(() => {
    director.current?.setStyle('h', styleH)
    director.current?.setStyle('a', styleA)
  }, [styleH, styleA])
  const halfNow = (minute ?? 0) < 45 ? 1 : (minute ?? 0) < 90 ? 2 : (minute ?? 0) < 105 ? 1 : 2
  useEffect(() => {
    director.current?.setHalf(halfNow)
    // saída de bola do tempo: mostra o campo por alguns segundos
    introUntil.current = performance.now() + 10000
  }, [halfNow])

  const holdRef = useRef(onHold)
  const revealRef = useRef(onReveal)
  const failRef = useRef(onUnavailable)
  useEffect(() => {
    holdRef.current = onHold
    revealRef.current = onReveal
    failRef.current = onUnavailable
  }, [onHold, onReveal, onUnavailable])

  const startClock = useRef(clock)
  useEffect(() => {
    const d = director.current
    if (!d) return
    const old = []
    for (const e of events) {
      if (seen.current.has(e.seq)) continue
      seen.current.add(e.seq)
      // lance anterior à abertura do campo (partida retomada / campo ligado no meio do jogo): não é reencenado,
      // e a tela é avisada para mostrá-lo no relato sem esperar a imagem
      if (e.minute < startClock.current - 0.5) {
        old.push(e.seq)
        continue
      }
      d.enqueue(e)
    }
    if (old.length) revealRef.current?.(old)
  }, [events])

  useEffect(() => {
    if (failed) {
      // nada fica preso: os lances pendentes entram no relato e a tela passa para "só placar"
      const d = director.current
      d?.releaseAll()
      const shown = d?.takeRevealed()
      if (shown) revealRef.current?.(shown)
      holdRef.current?.(null)
      failRef.current?.()
    }
    return () => holdRef.current?.(null)
  }, [failed])

  // cena 3D + laço. Criados uma vez por partida; o resto chega por refs.
  useEffect(() => {
    let ctx
    try {
      ctx = createScene(canvas.current, {
        crowdColors: [kits.h[0], kits.h[1], kits.a[0]],
        ads: [names.h.toUpperCase(), 'AO VIVO', names.a.toUpperCase(), 'FUTEBOL'],
        pixel,
        stadiumDef: pixel ? stadiumDef : null,
        pitch: pixel ? pixelPitchTexture(stadiumDef.grass) : null,
      })
    } catch (err) {
      console.error('[campo 3D]', err)
      // sem WebGL: avisa fora do efeito (o relógio é liberado pelo efeito de `failed`)
      Promise.resolve().then(() => setFailed(true))
      return undefined
    }
    const { renderer, scene, camera, stadium, goals, ball } = ctx
    // bola mais visível no celular (o tamanho físico do diretor não muda) e sombra no chão que mostra a altura
    ball.scale.setScalar(pixel ? 1.9 : 1.12)
    ball.material.emissive = new THREE.Color(pixel ? '#9a9a9a' : '#2a2a2a')
    const ballShadow = new THREE.Mesh(new THREE.CircleGeometry(0.34, 20), new THREE.MeshBasicMaterial({ color: '#000000', transparent: true, opacity: 0.45, depthWrite: false }))
    ballShadow.rotation.x = -Math.PI / 2
    scene.add(ballShadow)
    const kitMats = {
      h: createKitMaterials(kits.h[0], kits.h[1], kits.h[2]),
      a: createKitMaterials(kits.a[0], kits.a[1], kits.a[2]),
      gk_h: createKitMaterials(kits.gkH, '#1f2937', kits.gkH),
      gk_a: createKitMaterials(kits.gkA, '#1f2937', kits.gkA),
      ref: createKitMaterials(kits.ref, '#111827', '#111827'),
    }
    const rigs = new Map()
    const referee = { x: L / 2 - 6, y: W / 2 + 8, vx: 0, vy: 0, stride: 0, anim: null }
    const sprites = pixel ? createSpriteFactory() : null
    const trail = pixel ? createBallTrail(scene) : null
    const kickRing = pixel ? createKickRing(scene) : null
    let refRig = sprites ? sprites.create('ref', { shirt: kits.ref, shorts: '#111827', socks: '#111827' }, 'referee') : createAthlete(kitMats.ref, { id: 'referee', number: null })
    scene.add(refRig.root)
    // atletas novos (protótipo): quando o boneco e as animações chegam, todos são refeitos com eles
    let kay = null
    const kayKits = {
      h: { shirt: kits.h[0], shorts: kits.h[1], socks: kits.h[2] },
      a: { shirt: kits.a[0], shorts: kits.a[1], socks: kits.a[2] },
      gk_h: { shirt: kits.gkH, shorts: '#1f2937', socks: kits.gkH, gloves: true },
      gk_a: { shirt: kits.gkA, shorts: '#1f2937', socks: kits.gkA, gloves: true },
      ref: { shirt: kits.ref, shorts: '#111827', socks: '#111827' },
    }
    // atletas com animação capturada (KayKit) em todas as partidas; o boneco antigo só fica se os arquivos não carregarem
    if (!pixel) {
      loadPlayerAssets().then((a) => {
        if (!a || disposed) return
        kay = a
        for (const [, r] of rigs) scene.remove(r.root)
        rigs.clear()
        scene.remove(refRig.root)
        refRig = createPlayerRig(kay, kayKits.ref, 'referee')
        scene.add(refRig.root)
      })
    }
    let disposed = false

    let raf = 0
    let last = performance.now()
    let lastHold
    let reported = false
    let lastCaption = null
    let wasHl = true
    let snapCam = false
    let hlSec = 0
    let lastSec = 0
    let introSynced = false
    let lastSeq = null
    let postSince = null
    let tagHold = { id: null, at: 0 }
    let ownerSeen = { id: null, at: 0 }
    let cheer = 0
    const fieldAudio = createFieldAudio()
    const cam = { x: 0, z: 0, fov: 20, ox: 0 }
    // modo pixel: sobrevoo do estádio na abertura (o jogo espera)
    const flyMs = pixel ? 5200 : 0
    const flyStart = performance.now()
    let flying = flyMs > 0
    const ballPrev = new THREE.Vector3()
    const tmp = new THREE.Vector3()
    const axis = new THREE.Vector3()

    const resize = () => {
      const r = wrap.current.getBoundingClientRect()
      // modo pixel: ~300 linhas de imagem, ampliadas sem suavizar (o pixel aparece)
      const dpr = pixel ? Math.min(1, 300 / Math.max(1, r.height)) : Math.min(1.75, window.devicePixelRatio || 1)
      renderer.setPixelRatio(dpr)
      renderer.setSize(Math.max(1, r.width), Math.max(1, r.height), false)
      camera.aspect = Math.max(0.3, r.width / Math.max(1, r.height))
      camera.updateProjectionMatrix()
    }
    resize()
    const ro = new ResizeObserver(resize)
    ro.observe(wrap.current)

    const syncRigs = (players) => {
      const alive = new Set()
      for (const p of players) {
        alive.add(p.id)
        let r = rigs.get(p.id)
        const kitKey = p.gk ? `gk_${p.side}` : p.side
        if (r && r.kitKey !== kitKey) {
          scene.remove(r.root)
          r = null
        }
        if (!r) {
          r = sprites ? sprites.create(kitKey, kayKits[kitKey], p.id) : kay ? createPlayerRig(kay, kayKits[kitKey], p.id) : createAthlete(kitMats[kitKey], { id: p.id, number: p.number })
          r.kitKey = kitKey
          r.yaw = p.side === 'h' ? Math.PI / 2 : -Math.PI / 2
          scene.add(r.root)
          rigs.set(p.id, r)
        }
      }
      for (const [id, r] of rigs) {
        if (!alive.has(id)) {
          scene.remove(r.root)
          rigs.delete(id)
        }
      }
    }

    const draw = (now) => {
      const dtReal = Math.min(0.05, (now - last) / 1000)
      last = now
      const d = director.current
      if (!d) return
      const { paused: isPaused, speed: sp } = live.current
      // câmera lenta no chute: do toque até a bola chegar (gol, defesa ou fora), o lance passa a 45%
      const sc0 = d.state.script
      const slowMo = sc0 && ['attack', 'penalty'].includes(sc0.kind) && sc0.phase === 'flight'
      // melhor momento = lance em andamento (ou a saída de bola do tempo): tempo real. Fora dele, o jogo
      // avança rápido por baixo da tela de transição (no mínimo 6x, ou mais se a partida estiver atrasada)
      // depois do desfecho (tiro de meta, bola com o goleiro, volta ao meio-campo) o lance acabou: mais ~1,2 s
      // de imagem e a tela de transição entra (não mostra a bola parada nem os jogadores voltando)
      const post = sc0 && /goalkick|keeper|reset/.test(sc0.phase)
      if (post && postSince == null) postSince = now
      if (!post) postSince = null
      const hl = (Boolean(sc0) && (!post || now - postSince < 1200)) || now < introUntil.current
      // um ataque montado logo depois do outro (sem tela entre eles): varredura de luz e câmera na nova jogada
      const seqNow = sc0?.ev?.seq ?? null
      if (hl && wasHl && sc0?.staged && seqNow !== lastSeq) {
        snapCam = true
        hlSec = Math.max(lastSec, sc0.ev.minute * 60 - 14)
        setHlKey((k) => k + 1)
      }
      if (seqNow != null) lastSeq = seqNow
      if (hl !== wasHl) {
        wasHl = hl
        if (hl) {
          snapCam = true
          hlSec = sc0?.ev ? Math.max(lastSec, sc0.ev.minute * 60 - 14) : Math.max(lastSec, (live.current.minute ?? 0) * 60)
          setHlKey((k) => k + 1)
        }
        setCut(!hl)
      }
      // no lance: a velocidade escolhida (1x, 2x, 4x nas Temporadas; o online acelera quando atrasa)
      const mult = Math.max(1, Number(sp) || 1)
      if (flying && now - flyStart >= flyMs) {
        flying = false
        snapCam = true
        setFly(false)
      }
      const step = isPaused || flying ? 0 : hl ? dtReal * mult * (slowMo ? 0.45 : 1) : dtReal * Math.max(6, mult * 3)
      if (hl) hlSec += step
      // fora de lance roteirizado (saída de bola), o relógio parte do minuto atual da partida
      if (hl && !sc0 && !introSynced) {
        introSynced = true
        hlSec = Math.max(hlSec, (live.current.minute ?? 0) * 60)
      }
      if (!hl) introSynced = false
      if (step > 0) {
        let rest = step
        while (rest > 1e-4) {
          const s = Math.min(rest, 1 / 60)
          d.update(s)
          rest -= s
        }
      }
      const st = d.state
      const b = st.ball
      const t = now / 1000

      // atletas
      syncRigs(st.players)
      for (const p of st.players) {
        const r = rigs.get(p.id)
        r.root.position.set(p.x - L / 2, 0, p.y - W / 2)
        if (r.sprite) r.pose(p)
        else if (r.kay) poseKayPlayer(r, p, b, step)
        else poseAthlete(r, p, b, step || dtReal * 0.0001, t)
      }

      // árbitro: acompanha a jogada em diagonal, sem entrar na linha da bola
      {
        const tx = Math.max(4, Math.min(L - 4, b.x - 7))
        const ty = Math.max(3, Math.min(W - 3, b.y + (b.y < W / 2 ? 9 : -9)))
        const dx = tx - referee.x
        const dy = ty - referee.y
        const dd = Math.hypot(dx, dy)
        const want = dd > 2 ? Math.min(6.5, dd * 0.9) : 0
        const k = Math.min(1, step * 3)
        referee.vx += ((dd ? (dx / dd) * want : 0) - referee.vx) * k
        referee.vy += ((dd ? (dy / dd) * want : 0) - referee.vy) * k
        referee.x += referee.vx * step
        referee.y += referee.vy * step
        referee.stride = (referee.stride + (Math.hypot(referee.vx, referee.vy) * step * 8) / 2.6) % 8
        refRig.root.position.set(referee.x - L / 2, 0, referee.y - W / 2)
        if (refRig.sprite) {
          if (Math.hypot(referee.vx, referee.vy) > 0.6) referee.face = [2, 1, 0, 7, 6, 5, 4, 3][((Math.round(Math.atan2(referee.vy, referee.vx) / (Math.PI / 4)) % 8) + 8) % 8]
          refRig.pose(referee)
        } else if (refRig.kay) poseKayPlayer(refRig, referee, b, step)
        else poseAthlete(refRig, referee, b, step, t)
      }

      // bola: rola de acordo com a distância percorrida
      ball.visible = !b.hidden
      tmp.set(b.x - L / 2, (b.z || 0) + 0.16, b.y - W / 2)
      const mx = tmp.x - ballPrev.x
      const mz = tmp.z - ballPrev.z
      const md = Math.hypot(mx, mz)
      if (md > 1e-4 && md < 5) {
        axis.set(mz, 0, -mx).normalize()
        ball.rotateOnWorldAxis(axis, md / 0.16)
      }
      if (trail) trail.update(tmp, step > 0 ? md / step : 0, step)
      if (kickRing) kickRing.update(dtReal)
      ball.position.copy(tmp)
      ballPrev.copy(tmp)
      ballShadow.visible = !b.hidden
      ballShadow.position.set(tmp.x, 0.02, tmp.z)
      {
        const hgt = b.z || 0
        ballShadow.scale.setScalar(1 + hgt * 0.12)
        ballShadow.material.opacity = Math.max(0.12, 0.45 - hgt * 0.05)
      }

      // rede balança no gol
      for (const gl of goals) {
        const ns = st.netShake
        const k = ns && ns.side === gl.side ? Math.sin(ns.t * 28) * Math.max(0, 1 - ns.t) * 0.35 : 0
        gl.net.scale.set(1 + k, 1, 1 + k * 0.2)
      }

      // câmera de TV: segue a bola com atraso; no ataque fecha e gira para o gol; no gol, close no artilheiro
      const script = st.script
      const celebrating = script?.phase === 'celebrate' && script.shooter
      const attacking = script && ['attack', 'penalty'].includes(script.kind) && ['build', 'aim', 'flight', 'runup', 'carry', 'through'].includes(script.phase)
      // perto do gol, no ataque: o foco fica entre a bola e o gol (finalizador, goleiro e gol no quadro)
      const gxAtk = script?.side ? d.goalX(script.side) : null
      const nearGoal = attacking && gxAtk != null && Math.abs(gxAtk - b.x) < 34
      const focus = celebrating ? script.shooter : nearGoal ? { x: lerp(b.x, gxAtk, 0.42), y: lerp(b.y, W / 2, 0.35) } : b
      // câmera de TV: um pouco à frente da bola, no sentido de quem ataca, e com zona morta — a bola anda
      // dentro do quadro sem a câmera corrigir a cada passe; a câmera nunca corre mais que ~13 m/s
      const atkDir = (st.poss === 'h') === (st.half !== 2) ? 1 : -1
      const lead = celebrating || nearGoal ? 0 : atkDir * (attacking ? 7 : 5)
      const fx = focus.x - L / 2 + lead
      const fz = focus.y - W / 2
      const narrow = camera.aspect < 1.3
      // modo pixel: câmera mais fechada (atletas grandes, como nos jogos de futebol em pixel art)
      const wantFov = (celebrating ? 11 : nearGoal ? (slowMo ? 18 : 20) : slowMo ? 13 : attacking ? 16 : 19) * (narrow ? 1.5 : 1) * (pixel ? 0.72 : 1)
      const tx = Math.max(-L / 2 + 8, Math.min(L / 2 - 8, fx))
      const dead = celebrating || attacking ? 2 : 7
      const gapX = tx - cam.x
      const pushX = Math.abs(gapX) > dead ? gapX - Math.sign(gapX) * dead : 0
      const kc = Math.min(1, dtReal * (celebrating ? 1.4 : attacking ? 1.5 : 0.9))
      const maxV = (celebrating || attacking ? 20 : 13) * dtReal
      cam.x += Math.max(-maxV, Math.min(maxV, pushX * kc))
      cam.z += (fz - cam.z) * Math.min(1, dtReal * 0.9)
      // entrada de um lance: a câmera já começa na jogada (sem atravessar o campo)
      if (snapCam) {
        snapCam = false
        cam.x = tx
        cam.z = fz
      }
      cam.fov += (wantFov - cam.fov) * Math.min(1, dtReal * 1.2)
      // perto do gol a câmera fica mais para o meio: vê a área em diagonal, como na TV
      const wantOx = Math.abs(cam.x) > 28 ? -Math.sign(cam.x) * Math.min(9, (Math.abs(cam.x) - 28) * 0.6) : 0
      cam.ox += (wantOx - cam.ox) * Math.min(1, dtReal * 1.2)
      camera.fov = cam.fov
      camera.updateProjectionMatrix()
      camera.position.set(cam.x * 0.82 + cam.ox, celebrating ? 15 : 20, W / 2 + 30)
      camera.lookAt(cam.x, 0, cam.z * 0.7)
      if (flying) {
        // volta de câmera: começa alta, atrás do estádio, e desce até a posição da TV
        const u = Math.min(1, (now - flyStart) / flyMs)
        const e = u * u * (3 - 2 * u)
        const a = lerp(-2.5, 0, e)
        const R = lerp(150, W / 2 + 30, e)
        camera.position.set(Math.sin(a) * R, lerp(75, 20, e), Math.cos(a) * R)
        camera.fov = lerp(42, cam.fov, e)
        camera.updateProjectionMatrix()
        camera.lookAt(0, 0, 0)
      }

      // torcida pula no gol
      const goalNow = script?.phase === 'celebrate' && script.kind === 'attack'
      cheer += ((goalNow ? 1 : 0) - cheer) * Math.min(1, dtReal * (goalNow ? 3 : 1))
      stadium.bounce(t, cheer)

      renderer.render(scene, camera)

      // nome sobre quem tem a bola (ou o artilheiro comemorando)
      const owner = b.owner ? st.players.find((p) => p.id === b.owner) : null
      // o nome fica pelo menos 1,5 s em quem recebeu (não pisca a cada toque); sem dono, some depois de 1,5 s
      if (owner && owner.id !== ownerSeen.id) ownerSeen = { id: owner.id, at: now }
      const want = celebrating ? script.shooter : owner
      if (celebrating || (want && want.id !== tagHold.id && now - tagHold.at > 1500)) tagHold = { id: want.id, at: now }
      else if (want && want.id === tagHold.id) tagHold.last = now
      const held = tagHold.id ? st.players.find((p) => p.id === tagHold.id) : null
      const tag = held && (want || now - (tagHold.last || tagHold.at) < 1500) ? held : null
      const el = labelRef.current
      if (el) {
        if (tag) {
          tmp.copy(toWorld(tag.x, tag.y, 2.15)).project(camera)
          const r = wrap.current.getBoundingClientRect()
          // o rótulo nunca sai da tela (jogador na borda): a caixa fica inteira dentro do quadro
          const half = (el.offsetWidth || 90) / 2 + 4
          const px = Math.max(half, Math.min(r.width - half, ((tmp.x + 1) / 2) * r.width))
          el.style.transform = `translate(${px}px, ${((1 - tmp.y) / 2) * r.height}px) translate(-50%, -100%)`
          el.style.opacity = tmp.z < 1 ? '1' : '0'
          if (el.dataset.id !== String(tag.id)) {
            el.dataset.id = String(tag.id)
            el.textContent = tag.name || ''
            el.className = `m3d-tag ${tag.side === view.current.userSide ? 'is-mine' : ''}`
          }
        } else el.style.opacity = '0'
      }

      // relógio do lance em minutos e segundos (tempo real); fora do lance, o relógio da partida
      if (clockRef.current) {
        const txt = hl && !isPaused ? `${Math.floor(hlSec / 60)}:${String(Math.floor(hlSec % 60)).padStart(2, '0')}` : null
        if (txt) lastSec = hlSec
        const want = txt || live.current.clockLabel
        if (clockRef.current.textContent !== want) clockRef.current.textContent = want
      }
      // relógio espera o lance; placar conta quando a bola entra
      const hold = d.holdMinute()
      if (hold !== lastHold) {
        lastHold = hold
        holdRef.current?.(hold)
      }
      const shown = d.takeRevealed()
      if (shown) revealRef.current?.(shown)
      // sons de campo no mesmo quadro do desenho (chute, bote, defesa, rede, apito, expectativa da torcida)
      const fxs = d.takeFx()
      if (hl) fieldAudio.play(fxs, now)
      if (kickRing && fxs) for (const f of fxs) if (f.type === 'shot' || f.type === 'kick') kickRing.fire(f.x - L / 2, f.y - W / 2)
      fieldAudio.tick(dtReal, step > 0 && hl ? dangerOf(st, d.goalX) : 0)

      // faixa de narração: lance em destaque, senão quem conduz a bola
      const top = st.banners[0] || null
      let cap = null
      if (top) cap = { id: top.id, kind: top.kind, ev: top.ev, text: top.text }
      // "conduz a bola" só para quem fica com ela (1,2 s ou mais), não a cada passe
      else if (owner && now - ownerSeen.at > 1200) cap = { id: `own-${owner.id}`, kind: 'owner', name: owner.name, side: owner.side }
      const key = cap ? cap.id : null
      if (key !== lastCaption) {
        lastCaption = key
        setCaption(cap)
      }
    }

    let shownFirst = false
    const frame = (now) => {
      raf = requestAnimationFrame(frame)
      try {
        draw(now)
        if (!shownFirst) {
          shownFirst = true
          setReady(true)
        }
      } catch (err) {
        if (!reported) {
          reported = true
          console.error('[campo 3D]', err)
        }
      }
    }
    raf = requestAnimationFrame(frame)
    return () => {
      disposed = true
      cancelAnimationFrame(raf)
      ro.disconnect()
      fieldAudio.stop()
      scene.traverse((o) => {
        o.geometry?.dispose?.()
        const mats = Array.isArray(o.material) ? o.material : o.material ? [o.material] : []
        for (const m of mats) {
          m.map?.dispose?.()
          m.dispose?.()
        }
      })
      sprites?.dispose()
      renderer.dispose()
    }
    // a cena é montada uma vez por partida (cores e nomes não mudam no meio do jogo)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // Lance revelado: o MESMO texto do relato (eventText), do mesmo evento, no quadro em que o campo o mostra.
  // Faixas de transição (Falta, Pênalti!, Escanteio, Intervalo) usam o texto do diretor.
  const captionText = (c) => {
    if (c.kind === 'owner') return { who: c.name, rest: 'conduz a bola' }
    const e = c.ev
    if (!e || c.kind === 'foul' || c.kind === 'text') return { who: '', rest: c.text || '' }
    return { who: '', rest: eventText(e) }
  }
  const cap = caption && !finished ? captionText(caption) : null
  const capMine = caption && (caption.side || caption.ev?.side) === userSide

  // APITO FINAL: placar, resultado do meu time, gols com minuto e posse/finalizações
  const crestOf = (sd, size) => (clubs?.crest ? clubs.crest(sd, size) : <ClubCrest clubId={sd === 'h' ? data.home : data.away} size={size} />)
  const nameOf = (id) => (data.players || []).find((p) => p.id === id)?.name || ''
  const goals = finished ? (events || []).filter((e) => e.kind === 'goal' || e.kind === 'pen_goal').sort((x, y) => x.minute - y.minute) : []
  const result = !finished || !userSide ? null : score[userSide] > score[userSide === 'h' ? 'a' : 'h'] ? 'win' : score[userSide] < score[userSide === 'h' ? 'a' : 'h'] ? 'loss' : 'draw'
  const RESULT_TEXT = { win: 'Vitória', loss: 'Derrota', draw: 'Empate' }
  const ftStats = [
    ['Posse de bola', data.stats?.poss?.[0], data.stats?.poss?.[1], '%'],
    ['Finalizações', data.stats?.shots?.[0], data.stats?.shots?.[1], ''],
  ].filter(([, h, a]) => h != null && a != null)

  return (
    <div className="m3d">
      <div className="m3d-view" ref={wrap}>
        <canvas ref={canvas} className={`m3d-canvas ${pixel ? 'is-pixel' : ''}`} aria-label="Transmissão 3D da partida" role="img" />
        <div className="m3d-bug">
          <span ref={clockRef} className={`m3d-clock ${finished ? 'is-done' : ''}`}>{clockLabel}</span>
          <span className="m3d-team">
            {clubs?.crest ? clubs.crest('h') : <ClubCrest clubId={data.home} size={16} />}
            <b>{names.h}</b>
          </span>
          <span className="m3d-goals">
            <b>{score.h}</b>
            <b>{score.a}</b>
          </span>
          <span className="m3d-team">
            <b>{names.a}</b>
            {clubs?.crest ? clubs.crest('a') : <ClubCrest clubId={data.away} size={16} />}
          </span>
        </div>
        <div ref={labelRef} className="m3d-tag" style={{ opacity: 0 }} />
        {cap && (cap.who || cap.rest) && (
          <div key={caption.id} className={`m3d-caption k-${caption.kind} ${capMine ? 'is-mine' : ''}`}>
            {cap.who && <b>{cap.who}</b>} <span>{cap.rest}</span>
          </div>
        )}
        {pixel && fly && (
          <div className="m3d-stadium" aria-live="polite">
            <small>Estádio</small>
            <b>{stadiumDef.name}</b>
            <span>{stadiumDef.capacity} lugares</span>
          </div>
        )}
        {pixel && caption && (caption.kind === 'goal' || caption.kind === 'pen_goal') && <div key={`g-${caption.id}`} className="m3d-goalbig" aria-hidden="true">GOOOOOL!</div>}
        <div className={`m3d-cut ${cut && !finished ? 'is-on' : ''}`} aria-hidden={!cut}>
          <small>Melhores momentos</small>
          <b>{clockLabel}</b>
          <span>{paused ? 'Bola parada' : 'O jogo segue · próximo lance a qualquer momento'}</span>
        </div>
        {hlKey > 0 && <div key={hlKey} className="m3d-wipe" aria-hidden="true" />}
        {finished && (
          <div className={`m3d-ft ${result ? `is-${result}` : ''}`} role="status" aria-label={`Fim de jogo: ${names.h} ${score.h} × ${score.a} ${names.a}`}>
            <div className="m3d-ft-card">
              <small className="m3d-ft-kicker"><i className="m3d-ft-whistle" aria-hidden="true" /> Fim de jogo</small>
              <div className="m3d-ft-score">
                <span className="m3d-ft-team">{crestOf('h', 34)}<b>{names.h}</b></span>
                <strong>{score.h}<i>×</i>{score.a}</strong>
                <span className="m3d-ft-team">{crestOf('a', 34)}<b>{names.a}</b></span>
              </div>
              {result && <em className="m3d-ft-result">{RESULT_TEXT[result]}</em>}
              {goals.length > 0 && (
                <div className="m3d-ft-goals">
                  {['h', 'a'].map((sd) => (
                    <ul key={sd} className={sd === 'a' ? 'is-away' : ''}>
                      {/* um jogador por linha, com todos os minutos dos gols dele */}
                      {Object.values(goals.filter((g) => g.side === sd).reduce((acc, g) => {
                        const n = nameOf(g.player) || 'Gol'
                        acc[n] = acc[n] || { n, mins: [] }
                        acc[n].mins.push(`${g.minute}'${g.kind === 'pen_goal' ? ' (p)' : ''}`)
                        return acc
                      }, {})).map((x) => (
                        <li key={x.n}><span>{x.n}</span><b>{x.mins.join(' ')}</b></li>
                      ))}
                    </ul>
                  ))}
                </div>
              )}
              {ftStats.length > 0 && (
                <div className="m3d-ft-stats">
                  {ftStats.map(([label, h, a, unit]) => (
                    <div key={label}>
                      <b>{h}{unit}</b>
                      <span><small>{label}</small><i><em style={{ width: `${Number(h) + Number(a) ? (Number(h) / (Number(h) + Number(a))) * 100 : 50}%` }} /></i></span>
                      <b>{a}{unit}</b>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        )}
        {!ready && !failed && <div className="m3d-loading">Montando o estádio…</div>}
        {failed && <div className="m3d-loading">Este aparelho não conseguiu abrir o 3D. Os lances seguem no relato.</div>}
      </div>
    </div>
  )
}
