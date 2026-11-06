import { useEffect, useMemo, useRef, useState } from 'react'
import ClubCrest from '../club/components/ClubCrest'
import { getClubById } from '../club/data/clubs'
import { GROUND, SCENE, SPRITES, colorDistance, imageUrl, loadKit, project, tintAtlas } from './kit'
import { DIRS, L, W, createDirector } from '../match2d/director'
import './match25d.css'

const REF_W = SCENE.reference_canvas[0]
const REF_H = SCENE.reference_canvas[1]
const PLAYER_PX = 40 // altura visível do atleta na cena de referência (o kit sugere 30; maior para ler os movimentos no celular)
const GOAL_W = 7.32
const GOAL_H = 2.44
const GOAL_D = 1.8

const PLAYER_ATLAS = SPRITES.atlases.player
const KEEPER_ATLAS = SPRITES.atlases.keeper
const SPRITE_SCALE = PLAYER_PX / PLAYER_ATLAS.visible_height

// Quadro do atleta: animação especial (mergulho, defesa, comemoração), corrida pela passada ou parado na direção do corpo.
function frameOf(p) {
  const atlas = p.gk ? KEEPER_ATLAS : PLAYER_ATLAS
  const f = atlas.frames
  const a = p.anim
  if (a) {
    const i = Math.min(7, Math.floor((a.t / a.dur) * 8))
    if (a.name === 'kick' && !p.gk) return f[`run_${DIRS[p.face]}_3`]
    if (a.name === 'stumble') return f[`run_${DIRS[p.face]}_${(Math.floor(a.t * 20) % 2) + 5}`]
    const name = `${a.name}_${a.name === 'celebrate' ? Math.floor(a.t * 7) % 8 : i}`
    if (f[name]) return f[name]
  }
  const sp = Math.hypot(p.vx, p.vy)
  if (sp > 0.7) return f[`run_${DIRS[p.face]}_${Math.floor(p.stride) % 8}`]
  return f[`idle_${p.face}`]
}

function drawMarkings(g) {
  g.save()
  g.strokeStyle = 'rgba(255,255,255,0.86)'
  g.lineWidth = 0.14
  g.strokeRect(0, 0, L, W)
  g.beginPath()
  g.moveTo(L / 2, 0)
  g.lineTo(L / 2, W)
  g.stroke()
  g.beginPath()
  g.arc(L / 2, W / 2, 9.15, 0, Math.PI * 2)
  g.stroke()
  for (const side of [0, 1]) {
    const x0 = side ? L : 0
    const s = side ? -1 : 1
    g.strokeRect(side ? L - 16.5 : 0, W / 2 - 20.16, 16.5, 40.32)
    g.strokeRect(side ? L - 5.5 : 0, W / 2 - 9.16, 5.5, 18.32)
    g.beginPath()
    g.arc(x0 + s * 11, W / 2, 0.22, 0, Math.PI * 2)
    g.fillStyle = 'rgba(255,255,255,0.9)'
    g.fill()
    g.beginPath()
    const a = Math.acos(5.5 / 9.15)
    if (side) g.arc(x0 - 11, W / 2, 9.15, Math.PI - a, Math.PI + a)
    else g.arc(x0 + 11, W / 2, 9.15, -a, a)
    g.stroke()
  }
  for (const [cx, cy, a0] of [[0, 0, 0], [L, 0, Math.PI / 2], [L, W, Math.PI], [0, W, -Math.PI / 2]]) {
    g.beginPath()
    g.arc(cx, cy, 1, a0, a0 + Math.PI / 2)
    g.stroke()
  }
  g.beginPath()
  g.arc(L / 2, W / 2, 0.22, 0, Math.PI * 2)
  g.fill()
  g.restore()
}

// Gol desenhado na mesma projeção (traves, travessão e rede), em duas partes para a sobreposição correta.
function goalLines(side) {
  const x = side ? L : 0
  const back = side ? L + GOAL_D : -GOAL_D
  const y0 = W / 2 - GOAL_W / 2
  const y1 = W / 2 + GOAL_W / 2
  return { x, back, y0, y1 }
}
function drawGoalBack(g, side, shake = 0) {
  const { x, y0, y1 } = goalLines(side)
  const back = goalLines(side).back + (side ? shake : -shake)
  const p = (a, b, c) => project(a, b, c)
  g.save()
  g.strokeStyle = 'rgba(235,240,255,0.42)'
  g.lineWidth = 0.9
  const n = 9
  for (let i = 0; i <= n; i += 1) {
    const yy = y0 + ((y1 - y0) * i) / n
    g.beginPath()
    g.moveTo(...p(back, yy, 0))
    g.lineTo(...p(back, yy, GOAL_H * 0.85))
    g.lineTo(...p(x, yy, GOAL_H))
    g.stroke()
  }
  for (let j = 0; j <= 5; j += 1) {
    const zz = (GOAL_H * 0.85 * j) / 5
    g.beginPath()
    g.moveTo(...p(back, y0, zz))
    g.lineTo(...p(back, y1, zz))
    g.stroke()
  }
  g.strokeStyle = '#f4f6fb'
  g.lineWidth = 3
  g.beginPath()
  g.moveTo(...p(x, y0, 0))
  g.lineTo(...p(x, y0, GOAL_H))
  g.lineTo(...p(x, y1, GOAL_H))
  g.stroke()
  g.restore()
}
function drawGoalFront(g, side) {
  const { x, y1 } = goalLines(side)
  g.save()
  g.strokeStyle = '#f4f6fb'
  g.lineWidth = 3
  g.beginPath()
  g.moveTo(...project(x, y1, 0))
  g.lineTo(...project(x, y1, GOAL_H))
  g.stroke()
  g.restore()
}

// onHold(minuto|null): o relógio da partida não passa do minuto de um lance que a transmissão ainda está mostrando.
export default function MatchBroadcast({ data, catalog, clock, events, paused, speed = 1, minute, score, finished, clockLabel, userSide, compact = false, onHold }) {
  const wrap = useRef(null)
  const canvas = useRef(null)
  const imgs = useRef(null)
  const seen = useRef(new Set())
  const [ready, setReady] = useState(false)
  const [failed, setFailed] = useState(false)
  const [banner, setBanner] = useState(null)
  const live = useRef({ paused, speed })
  useEffect(() => {
    live.current = { paused, speed }
  }, [paused, speed])

  const home = getClubById(data.home)
  const away = getClubById(data.away)
  const colors = useMemo(() => {
    const h = home?.colors?.[0] || '#c8102e'
    let a = away?.colors?.[0] || '#1d4ed8'
    if (colorDistance(h, a) < 120) a = away?.colors?.[1] && colorDistance(h, away.colors[1]) > 120 ? away.colors[1] : '#1d4ed8'
    return { h, a }
  }, [home, away])

  // carrega a arte uma vez e recolore as camisas
  useEffect(() => {
    let alive = true
    loadKit()
      .then((k) => {
        if (!alive) return
        imgs.current = { ...k, atlas_h: tintAtlas(k.sprite_player, colors.h), atlas_a: tintAtlas(k.sprite_player, colors.a) }
        setReady(true)
      })
      .catch(() => alive && setFailed(true))
    return () => {
      alive = false
    }
  }, [colors])

  // diretor visual (criado uma vez por partida)
  const [dir] = useState(() => {
    const d = createDirector({ formations: catalog?.byId, homeId: data.home, awayId: data.away })
    d.sync(data.players || [], data.formation)
    d.kickoff('h')
    return d
  })
  const director = useRef(dir)
  useEffect(() => {
    director.current?.sync(data.players || [], data.formation)
  }, [data.players, data.formation])
  useEffect(() => {
    const poss = data.stats?.poss?.[0]
    director.current?.setPossession(poss ? poss / 100 : 0.5)
  }, [data.stats])
  useEffect(() => {
    const m = minute ?? 0
    const half = m < 45 ? 1 : m < 90 ? 2 : m < 105 ? 1 : 2
    director.current?.setHalf(half)
  }, [minute])

  // eventos reais → jogadas roteirizadas. Lances anteriores à abertura da transmissão (partida retomada) não são reencenados.
  const startClock = useRef(clock)
  useEffect(() => {
    const d = director.current
    if (!d) return
    for (const e of events) {
      if (seen.current.has(e.seq)) continue
      seen.current.add(e.seq)
      if (e.minute < startClock.current - 0.5) continue
      d.enqueue(e)
    }
  }, [events])
  // sem transmissão pronta (arte falhou) ou desmontada: o relógio não fica preso
  const holdRef = useRef(onHold)
  useEffect(() => {
    holdRef.current = onHold
  }, [onHold])
  useEffect(() => {
    if (failed) {
      director.current?.releaseAll()
      holdRef.current?.(null)
    }
    return () => holdRef.current?.(null)
  }, [failed])

  // laço de desenho
  useEffect(() => {
    if (!ready) return undefined
    const cv = canvas.current
    const g = cv.getContext('2d')
    let raf = 0
    let last = performance.now()
    let cam = { x: REF_W / 2 }
    let lastBanner = null
    let lastHold
    let zoomBoost = 1

    const resize = () => {
      const r = wrap.current.getBoundingClientRect()
      const dpr = Math.min(2, window.devicePixelRatio || 1)
      cv.width = Math.round(r.width * dpr)
      cv.height = Math.round(r.height * dpr)
    }
    resize()
    const ro = new ResizeObserver(resize)
    ro.observe(wrap.current)

    const frame = (now) => {
      raf = requestAnimationFrame(frame)
      const dtReal = Math.min(0.05, (now - last) / 1000)
      last = now
      const d = director.current
      const I = imgs.current
      if (!d || !I) return
      const { paused: isPaused, speed: sp } = live.current
      if (!isPaused) d.update(dtReal * Math.min(2.2, 0.85 + 0.35 * sp))
      const st = d.state

      // câmera: escala uniforme; em telas estreitas aproxima e acompanha a bola
      const cw = cv.width
      const ch = cv.height
      const fit = Math.max(cw / REF_W, ch / REF_H)
      const attack = st.script && ['attack', 'penalty'].includes(st.script.kind) && ['build', 'aim', 'flight', 'runup', 'celebrate'].includes(st.script.phase)
      zoomBoost += ((attack ? 1.12 : 1) - zoomBoost) * Math.min(1, dtReal * 1.5)
      const zoom = (cw / ch < 1.5 ? 1.55 : 1.22) * zoomBoost
      const s = fit * zoom
      const [bx] = project(st.ball.x, st.ball.y, 0)
      const halfView = cw / s / 2
      const target = Math.max(halfView, Math.min(REF_W - halfView, bx))
      cam.x += (target - cam.x) * Math.min(1, dtReal * 2.5)
      const [, by] = project(st.ball.x, st.ball.y, 0)
      const halfViewY = ch / s / 2
      const camY = Math.max(halfViewY, Math.min(REF_H - halfViewY, zoom > 1.3 ? by : REF_H / 2 + 20))
      g.setTransform(1, 0, 0, 1, 0, 0)
      g.fillStyle = '#0a1426'
      g.fillRect(0, 0, cw, ch)
      g.setTransform(s, 0, 0, s, cw / 2 - cam.x * s, ch / 2 - camY * s)
      const base = g.getTransform()

      // gramado e linhas no plano do campo
      const gr = SCENE.grass_destination_world_rect_xywh
      g.save()
      g.transform(...GROUND)
      g.drawImage(I.grass, gr[0], gr[1], gr[2], gr[3])
      g.restore()
      g.setTransform(base)
      g.save()
      g.transform(...GROUND)
      // listras de corte do gramado
      for (let i = 0; i < 14; i += 1) {
        if (i % 2) continue
        g.fillStyle = 'rgba(255,255,255,0.035)'
        g.fillRect((L / 14) * i, 0, L / 14, W)
      }
      g.restore()
      g.setTransform(base)
      g.save()
      g.transform(...GROUND)
      drawMarkings(g)
      g.restore()
      g.setTransform(base)
      g.drawImage(I.stadium, 0, 0, REF_W, REF_H)

      // bandeirinhas de escanteio
      for (const [fx, fy] of [[0, 0], [L, 0], [0, W], [L, W]]) {
        const [px, py] = project(fx, fy, 0)
        g.drawImage(I.flag, px - 3, py - 15, 8, 16)
      }

      const shake = st.netShake ? Math.sin(st.netShake.t * 28) * Math.max(0, 1 - st.netShake.t) * 0.6 : 0
      drawGoalBack(g, 0, st.netShake?.side === 0 ? shake : 0)
      drawGoalBack(g, 1, st.netShake?.side === 1 ? shake : 0)

      // atletas ordenados pela posição dos pés (fundo → frente)
      const list = [...st.players].sort((a, b) => a.y - b.y)
      const owner = st.ball.owner
      const items = list.map((p) => ({ kind: 'p', y: p.y, p }))
      items.push({ kind: 'ball', y: st.ball.y })
      items.push({ kind: 'post', y: W / 2 + GOAL_W / 2 + 0.01, side: 0 }, { kind: 'post', y: W / 2 + GOAL_W / 2 + 0.01, side: 1 })
      items.sort((a, b) => a.y - b.y)

      // sombras no chão
      for (const p of list) {
        const [x, y] = project(p.x, p.y, 0)
        g.globalAlpha = 0.55
        g.drawImage(I.shadow, x - 9, y - 3.5, 18, 7)
        g.globalAlpha = 1
        if (p.id === owner) g.drawImage(I.ring, x - 11, y - 4.5, 22, 9)
      }
      {
        const [x, y] = project(st.ball.x, st.ball.y, 0)
        g.fillStyle = 'rgba(0,0,0,0.35)'
        g.beginPath()
        g.ellipse(x, y, 2.6, 1.2, 0, 0, Math.PI * 2)
        g.fill()
      }

      for (const it of items) {
        if (it.kind === 'post') {
          drawGoalFront(g, it.side)
          continue
        }
        if (it.kind === 'ball') {
          if (st.ball.hidden) continue
          const [x, y] = project(st.ball.x, st.ball.y, st.ball.z)
          g.drawImage(I.ball, x - 4.5, y - 8.5, 9, 9)
          continue
        }
        const p = it.p
        const sheet = p.gk ? I.sprite_keeper : p.side === 'h' ? I.atlas_h : I.atlas_a
        const fr = frameOf(p)
        if (!fr) continue
        const k = SPRITE_SCALE
        const [x, y] = project(p.x, p.y, 0)
        g.drawImage(sheet, fr[0], fr[1], fr[2], fr[3], x - fr[4] * k, y - fr[5] * k, fr[2] * k, fr[3] * k)
        if (p.id === owner) {
          g.font = '600 7px Inter, sans-serif'
          g.textAlign = 'center'
          const label = `${p.number ?? ''} ${p.name || ''}`.trim()
          const w = g.measureText(label).width + 6
          g.fillStyle = p.side === userSide ? 'rgba(14,116,144,0.92)' : 'rgba(10,18,36,0.88)'
          g.fillRect(x - w / 2, y - PLAYER_PX - 13, w, 9)
          g.fillStyle = '#fff'
          g.fillText(label, x, y - PLAYER_PX - 6.2)
        }
      }

      // o relógio da partida espera o lance em andamento (gol só aparece no placar quando a bola entra)
      const hold = d.holdMinute()
      if (hold !== lastHold) {
        lastHold = hold
        holdRef.current?.(hold)
      }
      // banner atual (fila no diretor)
      const top = st.banners[0] || null
      const key = top ? top.id : null
      if (key !== lastBanner) {
        lastBanner = key
        setBanner(top ? { ...top } : null)
      }
    }
    raf = requestAnimationFrame(frame)
    return () => {
      cancelAnimationFrame(raf)
      ro.disconnect()
    }
  }, [ready, userSide])

  const bannerText = (b) => {
    const e = b.ev
    if (!e) return b.text || ''
    if (b.kind === 'goal') return `${e.player_name || ''} ${e.minute}'`
    if (b.kind === 'sub') return `Entra ${e.player_name || ''}${e.player2_name ? ` · sai ${e.player2_name}` : ''}`
    if (b.kind === 'foul') return b.text || 'Falta'
    return `${e.player_name || ''}`
  }

  return (
    <div className={`bc ${compact ? 'is-compact' : ''}`} ref={wrap}>
      <canvas ref={canvas} className="bc-canvas" aria-label="Transmissão da partida" role="img" />
      {!ready && !failed && <div className="bc-loading">Preparando a transmissão…</div>}
      {failed && <div className="bc-loading">Não foi possível carregar a transmissão. Os lances seguem no relato.</div>}
      <div className="bc-score" style={{ backgroundImage: `url(${imageUrl('scoreboard')})` }}>
        <span className="bc-team h">
          <ClubCrest clubId={data.home} size={18} />
          <b>{home?.short || home?.name}</b>
        </span>
        <b className="bc-goals h">{score.h}</b>
        <b className="bc-goals a">{score.a}</b>
        <span className="bc-team a">
          <b>{away?.short || away?.name}</b>
          <ClubCrest clubId={data.away} size={18} />
        </span>
        <span className={`bc-clock ${finished ? 'is-done' : ''}`}>{clockLabel}</span>
      </div>
      {banner && (
        <div key={banner.id} className={`bc-banner k-${banner.kind} ${banner.ev?.side && banner.ev.side === userSide ? 'is-mine' : ''}`}>
          {banner.img && <img src={imageUrl(banner.img)} alt="" />}
          {banner.kind === 'text' ? <strong>{banner.text}</strong> : <span>{bannerText(banner)}</span>}
        </div>
      )}
    </div>
  )
}
