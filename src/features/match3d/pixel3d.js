// MODO PIXEL da transmissão 3D (2.5D): o estádio continua em 3D, mas o gramado é uma textura em pixel art e os
// atletas são desenhos 2D (sprites) sempre de frente para a câmera. A imagem é renderizada em resolução baixa e
// ampliada sem suavizar (CSS image-rendering: pixelated), o que deixa tudo com cara de pixel art.
import * as THREE from 'three'
import { L, W } from '../match2d/director'
import { FH, FOOT, FW, POSES, coachSheet, lookOf, playerSheet } from '../matchPixel/pixelArt'

const RUN_X = 10
const RUN_Y = 8
const PPM = 4 // pixels por metro no gramado (pixel bem marcado)

// Gramado turquesa com listras diagonais e luz em degradê, linhas de 1 pixel.
export function pixelPitchTexture() {
  const tw = L + RUN_X * 2
  const th = W + RUN_Y * 2
  const cv = document.createElement('canvas')
  cv.width = Math.round(tw * PPM)
  cv.height = Math.round(th * PPM)
  const g = cv.getContext('2d')
  const w = cv.width
  const h = cv.height
  // degradê: mais claro perto da câmera (embaixo), mais escuro no fundo
  const grad = g.createLinearGradient(0, 0, 0, h)
  grad.addColorStop(0, '#2aa7b8')
  grad.addColorStop(1, '#3fd3b0')
  g.fillStyle = grad
  g.fillRect(0, 0, w, h)
  // listras diagonais (degraus de 1 pixel)
  const band = 26
  for (let y = 0; y < h; y += 1) {
    for (let k = -h; k < w + h; k += band * 2) {
      const x0 = k + y * 0.55
      g.fillStyle = 'rgba(0,40,70,0.10)'
      g.fillRect(Math.round(x0), y, band, 1)
    }
  }
  // granulado em pixels soltos
  let s = 7
  const rnd = () => ((s = (s * 16807) % 2147483647) / 2147483647)
  for (let i = 0; i < (w * h) / 40; i += 1) {
    g.fillStyle = rnd() > 0.5 ? 'rgba(255,255,255,0.07)' : 'rgba(0,30,50,0.08)'
    g.fillRect(Math.floor(rnd() * w), Math.floor(rnd() * h), 1, 1)
  }
  // linhas: 1 pixel, desenhadas pixel a pixel (sem suavização)
  const line = '#f4fbff'
  const P = (x, y) => [Math.round((x + RUN_X) * PPM), Math.round((y + RUN_Y) * PPM)]
  const dot = (x, y) => {
    g.fillStyle = line
    g.fillRect(x, y, 1, 1)
  }
  const seg = (x1, y1, x2, y2) => {
    const [a, b] = P(x1, y1)
    const [c, d] = P(x2, y2)
    const n = Math.max(Math.abs(c - a), Math.abs(d - b), 1)
    for (let k = 0; k <= n; k += 1) dot(Math.round(a + ((c - a) * k) / n), Math.round(b + ((d - b) * k) / n))
  }
  const box = (x1, y1, x2, y2) => {
    seg(x1, y1, x2, y1)
    seg(x2, y1, x2, y2)
    seg(x2, y2, x1, y2)
    seg(x1, y2, x1, y1)
  }
  const arc = (cx, cy, r, a0 = 0, a1 = Math.PI * 2) => {
    const n = Math.ceil(r * PPM * 8)
    for (let k = 0; k <= n; k += 1) {
      const a = a0 + ((a1 - a0) * k) / n
      const [x, y] = P(cx + Math.cos(a) * r, cy + Math.sin(a) * r)
      dot(x, y)
    }
  }
  box(0, 0, L, W)
  seg(L / 2, 0, L / 2, W)
  arc(L / 2, W / 2, 9.15)
  for (const side of [0, 1]) {
    const x0 = side ? L : 0
    const sg = side ? -1 : 1
    box(Math.min(x0, x0 + sg * 16.5), W / 2 - 20.16, Math.max(x0, x0 + sg * 16.5), W / 2 + 20.16)
    box(Math.min(x0, x0 + sg * 5.5), W / 2 - 9.16, Math.max(x0, x0 + sg * 5.5), W / 2 + 9.16)
    const [px, py] = P(x0 + sg * 11, W / 2)
    g.fillStyle = line
    g.fillRect(px - 1, py - 1, 2, 2)
    const a = Math.acos(5.5 / 9.15)
    arc(x0 + sg * 11, W / 2, 9.15, side ? Math.PI - a : -a, side ? Math.PI + a : a)
  }
  for (const [cx, cy, a0] of [[0, 0, 0], [L, 0, Math.PI / 2], [L, W, Math.PI], [0, W, -Math.PI / 2]]) arc(cx, cy, 1, a0, a0 + Math.PI / 2)
  const [cx, cy] = P(L / 2, W / 2)
  g.fillStyle = line
  g.fillRect(cx - 1, cy - 1, 2, 2)
  const tex = new THREE.CanvasTexture(cv)
  tex.colorSpace = THREE.SRGBColorSpace
  tex.magFilter = THREE.NearestFilter
  tex.minFilter = THREE.NearestFilter
  tex.generateMipmaps = false
  return { tex, tw, th }
}

// ─── atletas em sprite ───────────────────────────────────────────────────────
const POSE = Object.fromEntries(POSES.map((p, i) => [p, i]))
const VIEW_OF = [0, 1, 1, 1, 2, 1, 1, 1] // rumo do diretor (S, SE, E, NE, N, NW, W, SW) → frente, lado, costas
const FLIP_OF = [false, false, false, false, false, true, true, true]
const SPRITE_H = 2.35 // metros (cabeção estilizado: lê bem na câmera de TV)
const SPRITE_W = (SPRITE_H * FW) / FH

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

// Uma folha de quadros por aparência (cores do time + pele + cabelo), compartilhada entre os sprites.
export function createSpriteFactory() {
  const sheets = new Map()
  const sheetOf = (kitKey, kit, id, coach) => {
    const look = lookOf(id)
    const key = `${kitKey}:${look.skin}:${look.hair}:${look.style}`
    if (!sheets.has(key)) {
      const cv = coach ? coachSheet(look) : playerSheet(kit, look)
      const tex = new THREE.CanvasTexture(cv)
      tex.colorSpace = THREE.SRGBColorSpace
      tex.magFilter = THREE.NearestFilter
      tex.minFilter = THREE.NearestFilter
      tex.generateMipmaps = false
      sheets.set(key, tex)
    }
    return sheets.get(key)
  }
  const cols = POSES.length
  return {
    // rig com a mesma interface usada pela transmissão: root (Object3D) e pose(p)
    create(kitKey, kit, id, { coach = false } = {}) {
      const base = sheetOf(kitKey, kit, id, coach)
      const tex = base.clone() // mesma imagem, recorte próprio
      tex.repeat.set(1 / cols, 1 / 3)
      const mat = new THREE.SpriteMaterial({ map: tex, transparent: true, alphaTest: 0.5, depthWrite: true })
      const sp = new THREE.Sprite(mat)
      sp.scale.set(SPRITE_W, SPRITE_H, 1)
      sp.center.set(0.5, (FH - FOOT - 1) / FH) // pés no chão
      const root = new THREE.Group()
      root.add(sp)
      // sombra no chão
      const sh = new THREE.Mesh(new THREE.CircleGeometry(0.5, 12), new THREE.MeshBasicMaterial({ color: '#00243a', transparent: true, opacity: 0.35, depthWrite: false }))
      sh.rotation.x = -Math.PI / 2
      sh.scale.set(1.1, 0.55, 1)
      sh.position.y = 0.02
      root.add(sh)
      let cur = ''
      return {
        root,
        sprite: true,
        kitKey,
        pose(p) {
          const v = VIEW_OF[p.face ?? 0] ?? 0
          const pose = poseOf(p)
          const flip = pose === 'dive' ? p.anim?.name === 'dive_left' : FLIP_OF[p.face ?? 0]
          const key = `${v}:${pose}:${flip}`
          if (key === cur) return
          cur = key
          const row = v // 0 frente, 1 lado, 2 costas (linhas da folha)
          const col = POSE[pose] ?? 0
          // textura: v=0 é a base da imagem no three.js → linha de cima da folha = v mais alto
          tex.offset.set((flip ? col + 1 : col) / cols, (2 - row) / 3)
          tex.repeat.set((flip ? -1 : 1) / cols, 1 / 3)
          // deitado (mergulho): sprite mais baixo, para o corpo ficar no chão
          sp.scale.set(SPRITE_W, SPRITE_H, 1)
        },
      }
    },
    dispose() {
      for (const t of sheets.values()) t.dispose()
      sheets.clear()
    },
  }
}

// Rastro da bola nos chutes: cópias que somem (como as bolas fantasmas do lance rápido).
export function createBallTrail(scene, n = 9) {
  const mat = new THREE.SpriteMaterial({ color: '#fff4c2', transparent: true, opacity: 0.6, depthWrite: false })
  const dots = Array.from({ length: n }, () => {
    const s = new THREE.Sprite(mat.clone())
    s.scale.set(0.38, 0.38, 1)
    s.visible = false
    scene.add(s)
    return s
  })
  const hist = []
  let acc = 0
  return {
    update(pos, speed, dt) {
      acc += dt
      if (acc >= 0.035) {
        acc = 0
        hist.unshift({ x: pos.x, y: pos.y, z: pos.z, fast: speed > 14 })
        if (hist.length > n) hist.pop()
      }
      dots.forEach((d, i) => {
        const h = hist[i + 1]
        d.visible = Boolean(h && h.fast && hist[0]?.fast)
        if (!d.visible) return
        d.position.set(h.x, h.y, h.z)
        d.material.opacity = 0.55 * (1 - i / n)
        const k = 0.42 * (1 - i / (n * 1.4))
        d.scale.set(k, k, 1)
      })
    },
  }
}

// Anel branco no ponto do chute (some em ~0,3 s).
export function createKickRing(scene) {
  const geo = new THREE.RingGeometry(0.45, 0.62, 20)
  const mat = new THREE.MeshBasicMaterial({ color: '#ffffff', transparent: true, opacity: 0, depthWrite: false, side: THREE.DoubleSide })
  const ring = new THREE.Mesh(geo, mat)
  ring.rotation.x = -Math.PI / 2
  ring.position.y = 0.05
  scene.add(ring)
  let t = 1
  return {
    fire(x, z) {
      ring.position.x = x
      ring.position.z = z
      t = 0
    },
    update(dt) {
      t = Math.min(1, t + dt / 0.32)
      mat.opacity = t < 1 ? 0.9 * (1 - t) : 0
      const s = 0.8 + t * 1.6
      ring.scale.set(s, s, s)
    },
  }
}
