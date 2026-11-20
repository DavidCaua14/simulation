import { useEffect, useMemo, useRef, useState } from 'react'
import { Application, Container, Graphics, Rectangle, Sprite, Text, Texture } from 'pixi.js'
import ClubCrest from '../club/components/ClubCrest'
import { getClubById } from '../club/data/clubs'
import { createDirector, L, W } from '../match2d/director'
import { createFieldAudio, dangerOf } from '../audio/fieldSounds'
import { eventText } from '../seasons/utils/managerUtils'
import {
  FH, FOOT, FW, POSES, PX, PY, ballCanvas, coachSheet, crowdCanvases, fieldCanvas, goalCanvas, kitsFor, lookOf,
  markerCanvas, playerSheet, shadowCanvas, toScreen, worldSize,
} from './pixelArt'
import './matchPixel.css'

// CAMPO EM PIXEL ART (protótipo, PixiJS). Mesmas props da transmissão 3D: o diretor da partida é o mesmo; aqui o
// jogo é mostrado inteiro (sem cortes), com a câmera seguindo a bola, como num jogo de futebol 2D clássico.
// onHold(minuto|null): o relógio não passa do lance que ainda está em campo. onReveal(seqs): lances já mostrados.

const POSE = Object.fromEntries(POSES.map((p, i) => [p, i]))
// vista pelo rumo do diretor (S, SE, E, NE, N, NW, W, SW): 0 frente, 1 lado, 2 costas; espelha quando olha à esquerda
const VIEW_OF = [0, 1, 1, 1, 2, 1, 1, 1]
const FLIP_OF = [false, false, false, false, false, true, true, true]

function poseOf(p) {
  const a = p.anim
  if (a) {
    const k = a.dur ? a.t / a.dur : 0
    if (a.name === 'kick' || a.name === 'throw') return k < 0.45 ? 'kick0' : 'kick1'
    if (a.name === 'celebrate') return Math.floor(a.t * 6) % 2 ? 'celebrate' : 'idle'
    if (a.name.startsWith('catch') || a.name === 'jump') return 'catch'
    if (a.name.startsWith('dive')) return 'dive'
    if (a.name === 'getup') return k < 0.6 ? 'sit' : 'idle'
  }
  const sp = Math.hypot(p.vx || 0, p.vy || 0)
  if (sp > 0.5) return `run${Math.floor(((p.stride || 0) % 8) / 2)}`
  return 'idle'
}

export default function MatchPixel({ data, catalog, clock, events, paused, speed = 1, minute, score, finished, clockLabel, userSide, onHold, onReveal, onUnavailable, clubs }) {
  const wrap = useRef(null)
  const host = useRef(null)
  const [failed, setFailed] = useState(false)
  const [banner, setBanner] = useState(null)
  const live = useRef({ paused, speed })
  useEffect(() => {
    live.current = { paused, speed }
  }, [paused, speed])

  const home = clubs?.home || getClubById(data.home)
  const away = clubs?.away || getClubById(data.away)
  const hc = (clubs?.home?.colors || getClubById(data.home)?.colors || []).join()
  const ac = (clubs?.away?.colors || getClubById(data.away)?.colors || []).join()
  const kits = useMemo(() => kitsFor(hc ? hc.split(',') : [], ac ? ac.split(',') : []), [hc, ac])
  const names = useMemo(() => ({ h: home?.short || home?.name || 'CASA', a: away?.short || away?.name || 'FORA' }), [home?.short, home?.name, away?.short, away?.name])
  const view = useRef({ userSide })
  useEffect(() => {
    view.current = { userSide }
  }, [userSide])

  // diretor (só apresentação): criado uma vez por partida, jogo contínuo
  const [dir] = useState(() => {
    const d = createDirector({ formations: catalog?.byId, homeId: data.home, awayId: data.away })
    d.sync(data.players || [], data.formation)
    d.kickoff('h')
    return d
  })
  const director = useRef(dir)
  useEffect(() => {
    if (import.meta.env.DEV) window.__campoPixel = dir
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
  useEffect(() => {
    const m = minute ?? 0
    director.current?.setHalf(m < 45 ? 1 : m < 90 ? 2 : m < 105 ? 1 : 2)
  }, [minute])

  // eventos reais → jogadas. Lances anteriores à abertura (partida retomada) não são reencenados.
  const seen = useRef(new Set())
  const startClock = useRef(clock)
  const holdRef = useRef(onHold)
  const revealRef = useRef(onReveal)
  const failRef = useRef(onUnavailable)
  useEffect(() => {
    holdRef.current = onHold
    revealRef.current = onReveal
    failRef.current = onUnavailable
  }, [onHold, onReveal, onUnavailable])
  useEffect(() => {
    const d = director.current
    if (!d) return
    const old = []
    for (const e of events) {
      if (seen.current.has(e.seq)) continue
      seen.current.add(e.seq)
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
      const d = director.current
      d?.releaseAll()
      const shown = d?.takeRevealed()
      if (shown) revealRef.current?.(shown)
      holdRef.current?.(null)
      failRef.current?.()
    }
    return () => holdRef.current?.(null)
  }, [failed])

  // cena Pixi + laço. Criados uma vez por partida (as cores dos times entram na arte).
  useEffect(() => {
    let disposed = false
    let app = null
    let ro = null
    let fieldAudio = null
    const lastBanner = { key: null }
    const nearest = (c) => {
      const t = Texture.from(c)
      t.source.scaleMode = 'nearest'
      return t
    }

    const start = async () => {
      app = new Application()
      await app.init({
        background: '#0b1020',
        antialias: false,
        resolution: Math.min(2, window.devicePixelRatio || 1),
        autoDensity: true,
        roundPixels: true,
        resizeTo: wrap.current,
        preference: 'webgl',
      })
      if (disposed) {
        app.destroy(true)
        return
      }
      host.current.appendChild(app.canvas)

      const { w: worldW, h: worldH } = worldSize()
      const world = new Container()
      app.stage.addChild(world)
      const ui = new Container()
      app.stage.addChild(ui)

      // estádio
      world.addChild(new Sprite(nearest(fieldCanvas({ ads: [names.h.toUpperCase(), 'AO VIVO', names.a.toUpperCase(), 'FUTEBOL', 'LIGA'], adColors: [kits.h.shirt, '#0f172a', kits.a.shirt, '#047857', '#7c3aed'] }))))
      const crowdTex = crowdCanvases([kits.h.shirt, kits.h.shorts, kits.a.shirt, kits.a.shorts]).map(nearest)
      const crowd = new Sprite(crowdTex[0])
      world.addChild(crowd)
      const shadows = new Container()
      world.addChild(shadows)
      const actors = new Container()
      actors.sortableChildren = true
      world.addChild(actors)

      // gols
      for (const side of [0, 1]) {
        const gc = goalCanvas(side)
        const s = new Sprite(nearest(gc.canvas))
        const [sx, sy] = toScreen(side ? L : 0, W / 2 - 3.66)
        s.position.set(sx - gc.ox, sy - gc.y0)
        s.zIndex = toScreen(0, W / 2 + 3.66)[1] + 0.5
        actors.addChild(s)
      }

      // atletas: uma folha por aparência (cor do time + pele + cabelo), recortada em quadros
      const sheets = new Map()
      const framesOf = (kitKey, kit, id, coach = false) => {
        const look = lookOf(id)
        const key = `${kitKey}:${look.skin}:${look.hair}:${look.style}`
        if (!sheets.has(key)) {
          const tex = nearest(coach ? coachSheet(look) : playerSheet(kit, look))
          const fr = [0, 1, 2].map((r) => POSES.map((_, c) => new Texture({ source: tex.source, frame: new Rectangle(c * FW, r * FH, FW, FH) })))
          sheets.set(key, fr)
        }
        return sheets.get(key)
      }
      const shadowTex = nearest(shadowCanvas(12, 4))
      const makeActor = (frames) => {
        const sp = new Sprite(frames[0][0])
        sp.anchor.set(0.5, (FOOT + 1) / FH)
        const sh = new Sprite(shadowTex)
        sh.anchor.set(0.5, 0.5)
        actors.addChild(sp)
        shadows.addChild(sh)
        return { sp, sh, frames, cur: null }
      }
      const poseActor = (a, p, x, y) => {
        const v = VIEW_OF[p.face ?? 0] ?? 0
        const pose = poseOf(p)
        const key = `${v}:${pose}`
        if (key !== a.cur) {
          a.cur = key
          a.sp.texture = a.frames[v === 0 || v === 2 ? v : 1][POSE[pose]]
        }
        a.sp.scale.x = (pose === 'dive' ? p.anim?.name === 'dive_left' : FLIP_OF[p.face ?? 0]) ? -1 : 1
        a.sp.position.set(Math.round(x), Math.round(y))
        a.sp.zIndex = y
        a.sh.position.set(Math.round(x), Math.round(y))
      }
      const rigs = new Map()
      const syncActors = (players) => {
        const alive = new Set()
        for (const p of players) {
          alive.add(p.id)
          const kitKey = p.gk ? `gk_${p.side}` : p.side
          let a = rigs.get(p.id)
          if (a && a.kitKey !== kitKey) {
            a.sp.destroy()
            a.sh.destroy()
            a = null
          }
          if (!a) {
            a = makeActor(framesOf(kitKey, kits[kitKey], p.id))
            a.kitKey = kitKey
            rigs.set(p.id, a)
          }
        }
        for (const [id, a] of rigs) {
          if (alive.has(id)) continue
          a.sp.destroy()
          a.sh.destroy()
          rigs.delete(id)
        }
      }
      // árbitro e técnicos
      const referee = { x: L / 2 - 6, y: W / 2 + 8, vx: 0, vy: 0, stride: 0, face: 0, anim: null }
      const refActor = makeActor(framesOf('ref', kits.ref, 'referee'))
      const coaches = [
        { x: L / 2 - 6, y: W + 5.2, face: 4, anim: null, vx: 0, vy: 0, actor: makeActor(framesOf('coach', null, `coach:${names.h}`, true)) },
        { x: L / 2 + 20, y: W + 5.2, face: 4, anim: null, vx: 0, vy: 0, actor: makeActor(framesOf('coach', null, `coach:${names.a}`, true)) },
      ]

      // bola
      const ball = new Sprite(nearest(ballCanvas()))
      ball.anchor.set(0.5, 1)
      actors.addChild(ball)
      const ballShadow = new Sprite(nearest(shadowCanvas(6, 2)))
      ballShadow.anchor.set(0.5, 0.5)
      shadows.addChild(ballShadow)

      // marcador e nome de quem está com a bola (tela, fora da escala do mundo)
      const markerMine = nearest(markerCanvas('#22d3ee'))
      const markerOther = nearest(markerCanvas('#ef4444'))
      const marker = new Sprite(markerMine)
      marker.anchor.set(0.5, 1)
      const label = new Text({ text: '', style: { fontFamily: 'ui-monospace, Menlo, Consolas, monospace', fontWeight: '800', fontSize: 12, fill: '#ffffff', stroke: { color: '#0b1020', width: 3 }, letterSpacing: 0.5 } })
      label.anchor.set(0.5, 1)
      ui.addChild(marker, label)
      // minimapa
      const mini = new Graphics()
      ui.addChild(mini)

      fieldAudio = createFieldAudio()
      const cam = { x: L / 2, y: W / 2, zoom: 1 }
      let last = performance.now()
      let lastHold
      let reported = false
      let crowdT = 0
      let crowdF = 0
      let labelFor = null

      const tick = () => {
        const now = performance.now()
        const dt = Math.min(0.05, (now - last) / 1000)
        last = now
        try {
          frame(now, dt)
        } catch (err) {
          if (!reported) {
            reported = true
            console.error('[campo pixel]', err)
          }
        }
      }

      const frame = (now, dt) => {
        const d = director.current
        if (!d) return
        const { paused: isPaused, speed: sp } = live.current
        const step = isPaused ? 0 : dt * Math.max(1, Number(sp) || 1)
        let rest = step
        while (rest > 1e-4) {
          const s = Math.min(rest, 1 / 60)
          d.update(s)
          rest -= s
        }
        const st = d.state
        const b = st.ball

        syncActors(st.players)
        for (const p of st.players) {
          const [x, y] = toScreen(p.x, p.y)
          poseActor(rigs.get(p.id), p, x, y)
        }
        // árbitro: acompanha a jogada em diagonal
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
          referee.stride = (referee.stride + Math.hypot(referee.vx, referee.vy) * step * 3) % 8
          if (Math.hypot(referee.vx, referee.vy) > 0.6) {
            const ang = Math.atan2(referee.vy, referee.vx)
            referee.face = [2, 1, 0, 7, 6, 5, 4, 3][((Math.round(ang / (Math.PI / 4)) % 8) + 8) % 8]
          }
          const [x, y] = toScreen(referee.x, referee.y)
          poseActor(refActor, referee, x, y)
        }
        for (const c of coaches) {
          // técnico olha para onde está a bola
          c.face = b.x < c.x - 6 ? 6 : b.x > c.x + 6 ? 2 : 4
          const [x, y] = toScreen(c.x, c.y)
          poseActor(c.actor, c, x, y)
        }

        // bola: sobe na tela com a altura; a sombra fica no chão
        ball.visible = !b.hidden
        ballShadow.visible = !b.hidden
        {
          const [x, y] = toScreen(b.x, b.y, b.z || 0)
          const [sx, sy] = toScreen(b.x, b.y)
          ball.position.set(Math.round(x), Math.round(y + 1))
          ball.zIndex = sy + 0.2
          ball.scale.set(1 + Math.min(0.6, (b.z || 0) * 0.08))
          ballShadow.position.set(Math.round(sx), Math.round(sy))
          ballShadow.alpha = Math.max(0.3, 1 - (b.z || 0) * 0.12)
        }

        // torcida: balança devagar; no gol pula junto
        const celebrating = st.script?.phase === 'celebrate'
        crowdT += dt
        if (crowdT > (celebrating ? 0.16 : 0.7)) {
          crowdT = 0
          crowdF = celebrating ? 1 - crowdF : Math.random() < 0.25 ? 1 - crowdF : 0
          crowd.texture = crowdTex[crowdF]
        }

        // câmera: segue a bola com zona morta, um pouco à frente de quem ataca; no gol, fecha no artilheiro
        const screenW = app.screen.width
        const screenH = app.screen.height
        const script = st.script
        const shooter = celebrating ? script.shooter : null
        const focus = shooter || b
        const atkDir = (st.poss === 'h') === (st.half !== 2) ? 1 : -1
        const lead = shooter ? 0 : atkDir * 4
        const tx = focus.x + lead
        const ty = focus.y
        const dead = shooter ? 0.5 : 4
        const gx = tx - cam.x
        if (Math.abs(gx) > dead) cam.x += (gx - Math.sign(gx) * dead) * Math.min(1, dt * 2.2)
        const gy = ty - cam.y
        if (Math.abs(gy) > dead * 0.6) cam.y += (gy - Math.sign(gy) * dead * 0.6) * Math.min(1, dt * 2)
        const portrait = screenH > screenW
        // enquadramento: ~38 m de altura de campo no paisagem (atleta com ~1/10 da tela), ~30 m de largura no retrato
        const close = shooter ? 0.75 : 1
        const wantZoom = Math.max(portrait ? screenW / (30 * close * PX) : screenH / (38 * close * PY), screenH / (worldH * 0.95), screenW / worldW)
        cam.zoom += (wantZoom - cam.zoom) * Math.min(1, dt * 2)
        const z = cam.zoom
        world.scale.set(z)
        const [cx, cy] = toScreen(cam.x, cam.y)
        const wx = Math.min(0, Math.max(screenW - worldW * z, screenW / 2 - cx * z))
        const wy = Math.min(0, Math.max(screenH - worldH * z, screenH / 2 - cy * z))
        world.position.set(Math.round(wx), Math.round(wy))

        // marcador e nome: quem tem a bola (ou o artilheiro comemorando)
        const owner = shooter || (b.owner ? st.players.find((p) => p.id === b.owner) : null)
        marker.visible = Boolean(owner)
        label.visible = Boolean(owner?.name)
        if (owner) {
          const [ox, oy] = toScreen(owner.x, owner.y)
          const px = wx + ox * z
          const py = wy + (oy - FOOT - 2) * z
          marker.texture = owner.side === view.current.userSide ? markerMine : markerOther
          marker.scale.set(Math.max(2, Math.round(z * 0.75)))
          marker.position.set(Math.round(px), Math.round(py))
          if (labelFor !== owner.id) {
            labelFor = owner.id
            label.text = String(owner.name || '').toUpperCase()
          }
          label.position.set(Math.round(px), Math.round(py - 6 * marker.scale.y - 2))
        }

        // minimapa (canto inferior direito)
        {
          const mw = Math.min(120, screenW * 0.22)
          const mh = (mw * W) / L
          const mx = screenW - mw - 10
          const my = screenH - mh - 10
          mini.clear()
          mini.rect(mx - 2, my - 2, mw + 4, mh + 4).fill({ color: 0x0b1020, alpha: 0.55 })
          mini.rect(mx, my, mw, mh).stroke({ color: 0xffffff, alpha: 0.5, width: 1 })
          mini.moveTo(mx + mw / 2, my).lineTo(mx + mw / 2, my + mh).stroke({ color: 0xffffff, alpha: 0.35, width: 1 })
          for (const p of st.players) {
            const col = p.side === 'h' ? kits.h.shirt : kits.a.shirt
            mini.circle(mx + (p.x / L) * mw, my + (p.y / W) * mh, 2).fill(col)
          }
          if (!b.hidden) mini.circle(mx + (b.x / L) * mw, my + (b.y / W) * mh, 2).fill(0xffffff)
        }

        // som do campo
        const fxs = d.takeFx()
        fieldAudio.play(fxs, now)
        fieldAudio.tick(dt, step > 0 ? dangerOf(st, d.goalX) : 0)

        // relógio espera o lance; placar conta quando a bola entra
        const hold = d.holdMinute()
        if (hold !== lastHold) {
          lastHold = hold
          holdRef.current?.(hold)
        }
        const shown = d.takeRevealed()
        if (shown) revealRef.current?.(shown)
        const top = st.banners[0] || null
        const key = top ? top.id : null
        if (key !== lastBanner.key) {
          lastBanner.key = key
          setBanner(top ? { ...top } : null)
        }
      }
      app.ticker.add(tick)
      ro = new ResizeObserver(() => app.resize())
      ro.observe(wrap.current)
    }

    start().catch((err) => {
      console.error('[campo pixel]', err)
      if (!disposed) setFailed(true)
    })
    return () => {
      disposed = true
      ro?.disconnect()
      fieldAudio?.stop()
      if (app?.renderer) app.destroy(true, { children: true, texture: true })
    }
    // a arte depende das cores dos times; o resto chega por refs
  }, [kits, names.h, names.a])

  const crestOf = (sd) => (clubs?.crest ? clubs.crest(sd, 18) : <ClubCrest clubId={sd === 'h' ? data.home : data.away} size={18} />)
  const bannerText = (bn) => {
    const e = bn.ev
    if (!e) return bn.text || ''
    if (bn.kind === 'goal' || bn.kind === 'pen_goal') return `GOL! ${e.player_name || ''} ${e.minute}'`
    if (bn.kind === 'sub') return `Entra ${e.player_name || ''}${e.player2_name ? ` · sai ${e.player2_name}` : ''}`
    return eventText(e, e.player_name || '') || bn.text || ''
  }
  const mine = banner?.ev?.side && banner.ev.side === userSide

  return (
    <div className="mpx" ref={wrap}>
      <div className="mpx-canvas" ref={host} />
      <div className="mpx-board" aria-live="polite">
        <span className="mpx-team">{crestOf('h')} {names.h}</span>
        <b className="mpx-score">{score?.h ?? 0}-{score?.a ?? 0}</b>
        <span className="mpx-team">{names.a} {crestOf('a')}</span>
        <span className={`mpx-clock ${finished ? 'is-done' : ''}`}>{clockLabel}</span>
      </div>
      {banner && <div className={`mpx-banner k-${banner.kind} ${mine ? 'is-mine' : ''}`} key={banner.id}>{bannerText(banner)}</div>}
      {failed && <div className="mpx-fail">Campo indisponível neste aparelho</div>}
    </div>
  )
}
