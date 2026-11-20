// Cena 3D da transmissão (Three.js): estádio, gramado, gols, atletas articulados, bola e árbitro.
// Só APRESENTAÇÃO: as posições vêm do mesmo diretor do campo 2D (match2d/director.js).
// Mundo do diretor: x ∈ [0, 105] (comprimento), y ∈ [0, 68] (largura), z = altura da bola.
// Mundo 3D: X = x − 52,5 · Z = y − 34 · Y = altura. A câmera fica do lado y = 68 (Z positivo).
import * as THREE from 'three'
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js'
import { L, W } from '../match2d/director'
import { buildStadiumFromDef } from './stadiums'

const GOAL_W = 7.32
const GOAL_H = 2.44
const GOAL_D = 2
const PX_PER_M = 20
const RUN_X = 10 // gramado além das linhas de fundo
const RUN_Y = 8 // gramado além das laterais
const clamp = (v, a, b) => Math.max(a, Math.min(b, v))
const lerp = (a, b, k) => a + (b - a) * k
const smooth = (u) => u * u * (3 - 2 * u)

function hash(str) {
  let h = 2166136261
  for (const c of String(str)) h = Math.imul(h ^ c.charCodeAt(0), 16777619)
  return (h >>> 0) / 4294967295
}

function seeded(seed) {
  let s = seed >>> 0 || 1
  return () => {
    s = (Math.imul(s, 1664525) + 1013904223) >>> 0
    return s / 4294967296
  }
}

export function colorDist(a, b) {
  const ca = new THREE.Color(a)
  const cb = new THREE.Color(b)
  return Math.hypot(ca.r - cb.r, ca.g - cb.g, ca.b - cb.b) * 255
}

// ---------- gramado: listras de corte, ruído e linhas num único canvas ----------
function pitchTexture(renderer) {
  const tw = L + RUN_X * 2
  const th = W + RUN_Y * 2
  const cv = document.createElement('canvas')
  cv.width = Math.round(tw * PX_PER_M)
  cv.height = Math.round(th * PX_PER_M)
  const g = cv.getContext('2d')
  g.scale(PX_PER_M, PX_PER_M)
  g.translate(RUN_X, RUN_Y)
  g.fillStyle = '#3f8a2c'
  g.fillRect(-RUN_X, -RUN_Y, tw, th)
  // faixas de corte (verticais, como na TV) e um xadrez leve
  const n = 18
  for (let i = -2; i < n + 2; i += 1) {
    g.fillStyle = i % 2 ? 'rgba(255,255,255,0.055)' : 'rgba(0,0,0,0.05)'
    g.fillRect((L / n) * i, -RUN_Y, L / n, th)
  }
  for (let j = 0; j < 8; j += 1) {
    if (j % 2) continue
    g.fillStyle = 'rgba(255,255,255,0.025)'
    g.fillRect(-RUN_X, (W / 8) * j, tw, W / 8)
  }
  // granulado
  const rnd = seeded(7)
  for (let k = 0; k < 26000; k += 1) {
    const v = rnd()
    g.fillStyle = v > 0.5 ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.07)'
    g.fillRect(-RUN_X + rnd() * tw, -RUN_Y + rnd() * th, 0.12, 0.12)
  }
  // desgaste na pequena área e no meio
  for (const [cx, cy, r] of [[5, W / 2, 4], [L - 5, W / 2, 4], [L / 2, W / 2, 3]]) {
    const gr = g.createRadialGradient(cx, cy, 0, cx, cy, r)
    gr.addColorStop(0, 'rgba(120,110,60,0.18)')
    gr.addColorStop(1, 'rgba(120,110,60,0)')
    g.fillStyle = gr
    g.fillRect(cx - r, cy - r, r * 2, r * 2)
  }
  // linhas
  g.strokeStyle = 'rgba(255,255,255,0.92)'
  g.fillStyle = 'rgba(255,255,255,0.92)'
  g.lineWidth = 0.13
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
    g.arc(x0 + s * 11, W / 2, 0.2, 0, Math.PI * 2)
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
  g.arc(L / 2, W / 2, 0.2, 0, Math.PI * 2)
  g.fill()
  const tex = new THREE.CanvasTexture(cv)
  tex.colorSpace = THREE.SRGBColorSpace
  tex.anisotropy = renderer.capabilities.getMaxAnisotropy()
  return { tex, tw, th }
}

function adTexture(lines) {
  const cv = document.createElement('canvas')
  cv.width = 1024
  cv.height = 64
  const g = cv.getContext('2d')
  const blocks = 4
  for (let i = 0; i < blocks; i += 1) {
    const dark = i % 2 === 0
    g.fillStyle = dark ? '#0f1b33' : '#e8eef8'
    g.fillRect((1024 / blocks) * i, 0, 1024 / blocks, 64)
    g.fillStyle = dark ? '#ffffff' : '#0f1b33'
    g.font = '800 34px Inter, system-ui, sans-serif'
    g.textAlign = 'center'
    g.textBaseline = 'middle'
    g.fillText(lines[i % lines.length], (1024 / blocks) * (i + 0.5), 34)
  }
  const tex = new THREE.CanvasTexture(cv)
  tex.colorSpace = THREE.SRGBColorSpace
  tex.wrapS = THREE.RepeatWrapping
  return tex
}

function netTexture() {
  const cv = document.createElement('canvas')
  cv.width = 128
  cv.height = 128
  const g = cv.getContext('2d')
  g.strokeStyle = 'rgba(255,255,255,0.85)'
  g.lineWidth = 3
  for (let i = 0; i <= 128; i += 16) {
    g.beginPath()
    g.moveTo(i, 0)
    g.lineTo(i, 128)
    g.moveTo(0, i)
    g.lineTo(128, i)
    g.stroke()
  }
  const tex = new THREE.CanvasTexture(cv)
  tex.wrapS = THREE.RepeatWrapping
  tex.wrapT = THREE.RepeatWrapping
  tex.repeat.set(10, 4)
  return tex
}

function ballTexture() {
  const cv = document.createElement('canvas')
  cv.width = 256
  cv.height = 128
  const g = cv.getContext('2d')
  g.fillStyle = '#f7f7f2'
  g.fillRect(0, 0, 256, 128)
  g.fillStyle = '#1b1f2a'
  const spots = [[32, 30], [96, 64], [160, 30], [224, 64], [32, 100], [160, 100], [96, 10], [224, 118]]
  for (const [x, y] of spots) {
    g.beginPath()
    for (let k = 0; k < 5; k += 1) {
      const a = (k / 5) * Math.PI * 2 - Math.PI / 2
      g.lineTo(x + Math.cos(a) * 14, y + Math.sin(a) * 12)
    }
    g.fill()
  }
  const tex = new THREE.CanvasTexture(cv)
  tex.colorSpace = THREE.SRGBColorSpace
  return tex
}

function numberTexture(num, fg) {
  const cv = document.createElement('canvas')
  cv.width = 64
  cv.height = 64
  const g = cv.getContext('2d')
  g.font = '900 44px Inter, system-ui, sans-serif'
  g.textAlign = 'center'
  g.textBaseline = 'middle'
  g.lineWidth = 4
  g.strokeStyle = 'rgba(0,0,0,0.25)'
  g.strokeText(String(num ?? ''), 32, 35)
  g.fillStyle = fg
  g.fillText(String(num ?? ''), 32, 35)
  const tex = new THREE.CanvasTexture(cv)
  tex.colorSpace = THREE.SRGBColorSpace
  return tex
}

// texto legível sobre a cor da camisa
function inkFor(hex) {
  const c = new THREE.Color(hex)
  return c.r * 0.299 + c.g * 0.587 + c.b * 0.114 > 0.6 ? '#101828' : '#ffffff'
}

// ---------- estádio ----------
function buildStadium(scene, opts) {
  const { crowdColors, ads } = opts
  const group = new THREE.Group()
  scene.add(group)

  // anel de concreto e pista
  const apron = new THREE.Mesh(new THREE.PlaneGeometry(L + 60, W + 90), new THREE.MeshLambertMaterial({ color: '#2d5a22' }))
  apron.rotation.x = -Math.PI / 2
  apron.position.y = -0.02
  apron.receiveShadow = true
  group.add(apron)

  // arquibancadas: degraus mesclados num só mesh por lado + torcida em instâncias
  const ROWS = 16
  const STEP_D = 0.85
  const STEP_H = 0.48
  const standMat = new THREE.MeshLambertMaterial({ color: '#9aa3ad' })
  // sem arquibancada do lado da câmera (Z+): a câmera de TV fica sobre ela e ela tamparia o campo
  const sides = [
    { len: L + 18, at: (d) => [0, -(W / 2 + 7 + d)], rotY: Math.PI }, // lado oposto
    { len: W + 10, at: (d) => [L / 2 + 8 + d, 0], rotY: Math.PI / 2 },
    { len: W + 10, at: (d) => [-(L / 2 + 8 + d), 0], rotY: -Math.PI / 2 },
  ]
  const crowdSpots = []
  const rnd = seeded(42)
  for (const s of sides) {
    const geos = []
    for (let r = 0; r < ROWS; r += 1) {
      const h = 1.2 + r * STEP_H
      const box = new THREE.BoxGeometry(s.len, h, STEP_D)
      const [cx, cz] = s.at(r * STEP_D + STEP_D / 2)
      box.rotateY(s.rotY)
      box.translate(cx, h / 2, cz)
      geos.push(box)
      // torcida neste degrau
      const seats = Math.floor(s.len / 0.58)
      for (let k = 0; k < seats; k += 1) {
        if (rnd() < 0.1) continue
        const along = -s.len / 2 + (k + 0.5) * (s.len / seats) + (rnd() - 0.5) * 0.12
        const out = r * STEP_D + STEP_D * 0.55
        let x
        let z
        if (s.rotY === 0) [x, z] = [along, W / 2 + 7 + out]
        else if (s.rotY === Math.PI) [x, z] = [along, -(W / 2 + 7 + out)]
        else if (s.rotY > 0) [x, z] = [L / 2 + 8 + out, along]
        else [x, z] = [-(L / 2 + 8 + out), along]
        crowdSpots.push({ x, y: h, z, rot: s.rotY, ph: rnd() * Math.PI * 2, hgt: 0.62 + rnd() * 0.22 })
      }
    }
    const merged = mergeGeometries(geos)
    const mesh = new THREE.Mesh(merged, standMat)
    mesh.receiveShadow = true
    group.add(mesh)
    // parede do fundo
    const backD = ROWS * STEP_D + 0.5
    const [bx, bz] = s.at(backD)
    const wall = new THREE.Mesh(new THREE.BoxGeometry(s.len, 1.2 + ROWS * STEP_H + 6, 0.6), new THREE.MeshLambertMaterial({ color: '#56606c' }))
    wall.rotation.y = s.rotY
    wall.position.set(bx, (1.2 + ROWS * STEP_H + 6) / 2, bz)
    group.add(wall)
  }

  // cobertura sobre o lado oposto: projeta a sombra no fundo do gramado (como na TV)
  const roof = new THREE.Mesh(new THREE.BoxGeometry(L + 22, 0.4, 20), new THREE.MeshLambertMaterial({ color: '#3a4350' }))
  roof.position.set(0, 1.2 + ROWS * STEP_H + 6, -(W / 2 + 7 + ROWS * STEP_D - 4))
  roof.castShadow = true
  group.add(roof)

  // torcida
  const personGeo = new THREE.BoxGeometry(0.42, 1, 0.3)
  personGeo.translate(0, 0.5, 0)
  const personMat = new THREE.MeshLambertMaterial({ color: '#ffffff' })
  const crowd = new THREE.InstancedMesh(personGeo, personMat, crowdSpots.length)
  const m = new THREE.Matrix4()
  const q = new THREE.Quaternion()
  const sc = new THREE.Vector3()
  const pos = new THREE.Vector3()
  const col = new THREE.Color()
  crowdSpots.forEach((c, i) => {
    q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), c.rot)
    sc.set(1, c.hgt, 1)
    pos.set(c.x, c.y, c.z)
    m.compose(pos, q, sc)
    crowd.setMatrixAt(i, m)
    const v = rnd()
    col.set(v < 0.62 ? crowdColors[0] : v < 0.8 ? crowdColors[1] : v < 0.9 ? '#f1f1f1' : crowdColors[2])
    col.offsetHSL(0, 0, (rnd() - 0.5) * 0.12)
    crowd.setColorAt(i, col)
  })
  crowd.instanceMatrix.needsUpdate = true
  group.add(crowd)

  // placas de publicidade
  const adTex = adTexture(ads)
  const adMat = new THREE.MeshBasicMaterial({ map: adTex })
  const boardH = 0.9
  const boards = [
    { w: L + 8, x: 0, z: W / 2 + 4, ry: Math.PI },
    { w: L + 8, x: 0, z: -(W / 2 + 4), ry: 0 },
    { w: (W - GOAL_W - 10) / 2, x: L / 2 + 5, z: (W + GOAL_W + 10) / 4, ry: -Math.PI / 2 },
    { w: (W - GOAL_W - 10) / 2, x: L / 2 + 5, z: -(W + GOAL_W + 10) / 4, ry: -Math.PI / 2 },
    { w: (W - GOAL_W - 10) / 2, x: -(L / 2 + 5), z: (W + GOAL_W + 10) / 4, ry: Math.PI / 2 },
    { w: (W - GOAL_W - 10) / 2, x: -(L / 2 + 5), z: -(W + GOAL_W + 10) / 4, ry: Math.PI / 2 },
  ]
  for (const b of boards) {
    const t = adTex.clone()
    t.needsUpdate = true
    t.repeat.set(b.w / 14, 1)
    const mat = adMat.clone()
    mat.map = t
    const mesh = new THREE.Mesh(new THREE.BoxGeometry(b.w, boardH, 0.15), [null, null, null, null, mat, mat].map((x) => x || new THREE.MeshLambertMaterial({ color: '#0f1b33' })))
    mesh.position.set(b.x, boardH / 2, b.z)
    mesh.rotation.y = b.ry
    mesh.castShadow = true
    group.add(mesh)
  }

  // bandeirinhas de escanteio
  const poleMat = new THREE.MeshLambertMaterial({ color: '#f3f3f3' })
  const flagMat = new THREE.MeshLambertMaterial({ color: '#f6c445', side: THREE.DoubleSide })
  for (const [fx, fz] of [[-L / 2, -W / 2], [L / 2, -W / 2], [-L / 2, W / 2], [L / 2, W / 2]]) {
    const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.02, 0.02, 1.5, 6), poleMat)
    pole.position.set(fx, 0.75, fz)
    pole.castShadow = true
    const flag = new THREE.Mesh(new THREE.PlaneGeometry(0.4, 0.3), flagMat)
    flag.position.set(fx + 0.2, 1.35, fz)
    group.add(pole, flag)
  }

  return {
    crowd,
    crowdSpots,
    // torcida pula (gol): intensidade 0..1
    bounce(t, k) {
      if (k <= 0.001 && !crowd.userData.dirty) return
      crowd.userData.dirty = k > 0.001
      crowdSpots.forEach((c, i) => {
        q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), c.rot)
        sc.set(1, c.hgt, 1)
        pos.set(c.x, c.y + Math.max(0, Math.sin(t * 9 + c.ph)) * 0.35 * k, c.z)
        m.compose(pos, q, sc)
        crowd.setMatrixAt(i, m)
      })
      crowd.instanceMatrix.needsUpdate = true
    },
  }
}

// ---------- gols ----------
function buildGoal(scene, side) {
  const g = new THREE.Group()
  const x = side ? L / 2 : -L / 2
  const s = side ? 1 : -1
  const postMat = new THREE.MeshLambertMaterial({ color: '#ffffff' })
  const r = 0.06
  const postGeo = new THREE.CylinderGeometry(r, r, GOAL_H, 10)
  for (const z of [-GOAL_W / 2, GOAL_W / 2]) {
    const post = new THREE.Mesh(postGeo, postMat)
    post.position.set(x, GOAL_H / 2, z)
    post.castShadow = true
    g.add(post)
  }
  const bar = new THREE.Mesh(new THREE.CylinderGeometry(r, r, GOAL_W + r * 2, 10), postMat)
  bar.rotation.x = Math.PI / 2
  bar.position.set(x, GOAL_H, 0)
  bar.castShadow = true
  g.add(bar)

  // rede: fundo, teto e laterais num grupo que balança no gol
  const net = new THREE.Group()
  const netMat = new THREE.MeshBasicMaterial({ map: netTexture(), transparent: true, opacity: 0.55, side: THREE.DoubleSide, depthWrite: false })
  const back = new THREE.Mesh(new THREE.PlaneGeometry(GOAL_W, GOAL_H), netMat)
  back.position.set(s * GOAL_D, GOAL_H / 2, 0)
  back.rotation.y = Math.PI / 2
  const top = new THREE.Mesh(new THREE.PlaneGeometry(GOAL_D, GOAL_W), netMat)
  top.rotation.x = -Math.PI / 2
  top.position.set((s * GOAL_D) / 2, GOAL_H, 0)
  for (const z of [-GOAL_W / 2, GOAL_W / 2]) {
    const sideNet = new THREE.Mesh(new THREE.PlaneGeometry(GOAL_D, GOAL_H), netMat)
    sideNet.position.set((s * GOAL_D) / 2, GOAL_H / 2, z)
    net.add(sideNet)
  }
  net.add(back, top)
  net.position.x = x
  g.add(net)
  scene.add(g)
  return { group: g, net, side }
}

// ---------- atleta articulado ----------
const SKINS = ['#f1c7a5', '#e0ac85', '#c68863', '#a46a45', '#7b4b2e', '#5a3622']
const HAIRS = ['#1d140e', '#3b2618', '#6b4a2b', '#c49a55', '#111111']
const G = {}
function geos() {
  if (G.ready) return G
  G.torso = new THREE.CapsuleGeometry(0.16, 0.3, 4, 10)
  G.torso.scale(1.3, 1, 0.75)
  G.head = new THREE.SphereGeometry(0.115, 14, 12)
  G.hair = new THREE.SphereGeometry(0.122, 14, 8, 0, Math.PI * 2, 0, Math.PI * 0.5)
  G.neck = new THREE.CylinderGeometry(0.05, 0.055, 0.1, 8)
  G.upperArm = new THREE.CapsuleGeometry(0.052, 0.2, 3, 8)
  G.foreArm = new THREE.CapsuleGeometry(0.044, 0.2, 3, 8)
  G.shorts = new THREE.CylinderGeometry(0.1, 0.092, 0.22, 10)
  G.thigh = new THREE.CapsuleGeometry(0.072, 0.26, 3, 8)
  G.shin = new THREE.CapsuleGeometry(0.06, 0.3, 3, 8)
  G.boot = new THREE.BoxGeometry(0.1, 0.07, 0.24)
  G.number = new THREE.PlaneGeometry(0.26, 0.26)
  G.ready = true
  return G
}

function mesh(geo, mat, shadow = true) {
  const m = new THREE.Mesh(geo, mat)
  m.castShadow = shadow
  return m
}

export function createKitMaterials(shirt, shorts, socks) {
  return {
    shirt: new THREE.MeshLambertMaterial({ color: shirt }),
    shorts: new THREE.MeshLambertMaterial({ color: shorts }),
    socks: new THREE.MeshLambertMaterial({ color: socks }),
    ink: inkFor(shirt),
  }
}

const skinMats = new Map()
const hairMats = new Map()
const bootMat = new THREE.MeshLambertMaterial({ color: '#15171c' })
const matFor = (cache, c) => {
  if (!cache.has(c)) cache.set(c, new THREE.MeshLambertMaterial({ color: c }))
  return cache.get(c)
}

export function createAthlete(kit, { id, number, seed }) {
  const g = geos()
  const h = hash(seed ?? id)
  const skin = matFor(skinMats, SKINS[Math.floor(h * SKINS.length) % SKINS.length])
  const hair = matFor(hairMats, HAIRS[Math.floor(hash(`${id}h`) * HAIRS.length) % HAIRS.length])
  const root = new THREE.Group()
  const body = new THREE.Group()
  root.add(body)
  const hips = new THREE.Group()
  hips.position.y = 0.97
  body.add(hips)

  const torso = mesh(g.torso, kit.shirt)
  torso.position.y = 0.3
  hips.add(torso)
  const shorts = mesh(g.shorts, kit.shorts)
  shorts.position.y = 0.0
  shorts.scale.set(1.9, 1, 1.25)
  hips.add(shorts)
  if (number != null) {
    const numMat = new THREE.MeshBasicMaterial({ map: numberTexture(number, kit.ink), transparent: true, depthWrite: false })
    const back = new THREE.Mesh(g.number, numMat)
    back.position.set(0, 0.34, -0.128)
    back.rotation.y = Math.PI
    hips.add(back)
  }
  const neck = mesh(g.neck, skin)
  neck.position.y = 0.6
  hips.add(neck)
  const head = mesh(g.head, skin)
  head.position.y = 0.72
  hips.add(head)
  const hairM = mesh(g.hair, hair, false)
  hairM.position.y = 0.735
  hairM.rotation.x = -0.25
  hips.add(hairM)

  const arm = (sx) => {
    const sh = new THREE.Group()
    sh.position.set(sx * 0.235, 0.5, 0)
    const up = mesh(g.upperArm, kit.shirt)
    up.position.y = -0.13
    sh.add(up)
    const elbow = new THREE.Group()
    elbow.position.y = -0.28
    const fo = mesh(g.foreArm, skin)
    fo.position.y = -0.13
    elbow.add(fo)
    sh.add(elbow)
    hips.add(sh)
    return { sh, elbow }
  }
  const leg = (sx) => {
    const hip = new THREE.Group()
    hip.position.set(sx * 0.1, -0.02, 0)
    const th = mesh(g.thigh, skin)
    th.position.y = -0.22
    hip.add(th)
    const knee = new THREE.Group()
    knee.position.y = -0.45
    const shin = mesh(g.shin, kit.socks)
    shin.position.y = -0.2
    knee.add(shin)
    const boot = mesh(g.boot, bootMat)
    boot.position.set(0, -0.47, 0.04)
    knee.add(boot)
    hip.add(knee)
    hips.add(hip)
    return { hip, knee }
  }
  const rig = { root, body, hips, armL: arm(1), armR: arm(-1), legL: leg(1), legR: leg(-1), yaw: 0 }
  return rig
}

// Sinal da rotação do corpo no mergulho. O eixo X local do boneco aponta, no mundo, para (cos yaw, −sin yaw)
// em (X, Z); rotation.z > 0 tomba o tronco para −X local. O mergulho vai para dy (eixo y do campo = Z).
function diveRollSign(a, yaw) {
  if (a.dy) {
    const s = -a.dy * Math.sin(yaw) // componente do mergulho no X local
    if (Math.abs(s) > 0.05) return s > 0 ? -1 : 1
  }
  return a.name === 'dive_left' ? 1 : -1
}

// Pose do quadro: corrida pela passada do diretor (2,6 m por ciclo), ou a animação especial em curso.
export function poseAthlete(rig, p, ballPos, dt, time) {
  const sp = Math.hypot(p.vx || 0, p.vy || 0)
  const k = clamp(sp / 7.6, 0, 1)
  const moving = sp > 0.35
  const ph = (p.stride || 0) * (Math.PI / 4)
  const s = Math.sin(ph)
  // a passada ganha e perde força aos poucos (sem trocar de parado para correndo de um quadro para o outro)
  const ampWant = moving ? 0.25 + 0.75 * k : 0
  rig.amp = (rig.amp ?? 0) + (ampWant - (rig.amp ?? 0)) * Math.min(1, dt * 7)
  const amp = rig.amp
  const a = p.anim
  const { body, armL, armR, legL, legR } = rig

  // direção do corpo: para onde corre; parado, olha para a bola
  if (!(a && (a.name.startsWith('dive') || a.name === 'getup'))) {
    let want = rig.yaw
    if (moving) want = Math.atan2(p.vx, p.vy)
    else if (ballPos) want = Math.atan2(ballPos.x - p.x, ballPos.y - p.y)
    let d = want - rig.yaw
    d = Math.atan2(Math.sin(d), Math.cos(d))
    // giro do corpo suave (em velocidade, curva mais aberta); a inclinação lateral acompanha a curva
    const turn = d * Math.min(1, dt * (moving ? 5.5 - k * 1.5 : 3))
    rig.yaw += turn
    rig.bank = (rig.bank ?? 0) + (clamp((turn / Math.max(dt, 1e-3)) * k * -0.06, -0.22, 0.22) - (rig.bank ?? 0)) * Math.min(1, dt * 6)
  }
  rig.root.rotation.y = rig.yaw

  // base: corrida / parado
  let lean = moving ? 0.04 + k * 0.2 : 0.02
  let bob = moving ? Math.abs(Math.cos(ph)) * 0.06 * k : Math.sin(time * 2 + rig.yaw) * 0.006
  let roll = rig.bank || 0
  legL.hip.rotation.x = -s * amp * 0.85
  legR.hip.rotation.x = s * amp * 0.85
  // parado, joelhos levemente dobrados (postura de jogo); correndo, o joelho de trás dobra mais
  legL.knee.rotation.x = (moving ? 0.06 : 0.16) + Math.max(0, s) * amp * 1.35
  legR.knee.rotation.x = (moving ? 0.06 : 0.16) + Math.max(0, -s) * amp * 1.35
  armL.sh.rotation.set(s * amp * 0.75, 0, 0.1)
  armR.sh.rotation.set(-s * amp * 0.75, 0, -0.1)
  armL.elbow.rotation.x = -0.25 - amp * 0.9
  armR.elbow.rotation.x = -0.25 - amp * 0.9
  legL.hip.rotation.z = 0
  legR.hip.rotation.z = 0

  if (a) {
    const u = clamp(a.t / a.dur, 0, 1)
    switch (a.name) {
      case 'kick': {
        legR.hip.rotation.x = u < 0.35 ? lerp(0, 0.75, u / 0.35) : lerp(0.75, -1.15, smooth((u - 0.35) / 0.65))
        legR.knee.rotation.x = u < 0.35 ? lerp(0.1, 1.2, u / 0.35) : lerp(1.2, 0.05, (u - 0.35) / 0.65)
        legL.hip.rotation.x = -0.15
        legL.knee.rotation.x = 0.25
        armL.sh.rotation.set(-0.3, 0, 0.75)
        armR.sh.rotation.set(0.2, 0, -0.55)
        lean = 0.12
        break
      }
      case 'celebrate': {
        const j = Math.abs(Math.sin(a.t * 7))
        armL.sh.rotation.set(-2.7 + j * 0.3, 0, 0.35)
        armR.sh.rotation.set(-2.7 + j * 0.3, 0, -0.35)
        armL.elbow.rotation.x = -0.2
        armR.elbow.rotation.x = -0.2
        if (!moving) bob = j * 0.28
        lean = -0.08
        break
      }
      case 'dive_left':
      case 'dive_right': {
        // o corpo tomba para o lado em que ele de fato se desloca (dy no campo), visto pela direção em que ele olha
        const dirS = diveRollSign(a, rig.yaw)
        const e = smooth(Math.min(1, u * 1.6))
        roll = dirS * e * 1.35
        // altura do salto conforme a bola: rasteira quase no chão, alta com impulso
        const h = a.h ?? 0.8
        bob = Math.sin(Math.min(1, u * 1.25) * Math.PI) * (0.12 + Math.min(1.9, h) * 0.3)
        armL.sh.rotation.set(-2.9, 0, 0.1)
        armR.sh.rotation.set(-2.9, 0, -0.1)
        armL.elbow.rotation.x = -0.1
        armR.elbow.rotation.x = -0.1
        legL.hip.rotation.x = -0.2
        legR.hip.rotation.x = 0.2
        legL.knee.rotation.x = 0.3
        legR.knee.rotation.x = 0.3
        lean = 0
        break
      }
      case 'catch_high': {
        armL.sh.rotation.set(-2.85, 0, 0.15)
        armR.sh.rotation.set(-2.85, 0, -0.15)
        armL.elbow.rotation.x = -0.3
        armR.elbow.rotation.x = -0.3
        // impulso proporcional à altura da bola (cruzamento alto: salto maior)
        bob = Math.sin(Math.min(1, u * 1.6) * Math.PI) * clamp(((a.h ?? 1.6) - 1.4) * 0.45, 0.12, 0.5)
        lean = -0.05
        break
      }
      case 'catch_low': {
        legL.hip.rotation.x = -0.9
        legR.hip.rotation.x = -0.9
        legL.knee.rotation.x = 1.5
        legR.knee.rotation.x = 1.5
        armL.sh.rotation.set(-1.2, 0, 0.1)
        armR.sh.rotation.set(-1.2, 0, -0.1)
        bob = -0.3
        lean = 0.45
        break
      }
      case 'throw': {
        armR.sh.rotation.set(lerp(-3.0, -0.6, smooth(u)), 0, -0.1)
        armL.sh.rotation.set(-0.6, 0, 0.4)
        lean = lerp(-0.2, 0.25, u)
        break
      }
      case 'getup': {
        // do chão para de pé: desfaz o rolamento do mergulho
        const dirS = diveRollSign({ name: a.from, dy: a.dy }, rig.yaw)
        const e = 1 - smooth(u)
        roll = dirS * e * 1.35
        bob = e * 0.1
        armL.sh.rotation.set(-1.4 * e, 0, 0.3)
        armR.sh.rotation.set(-1.4 * e, 0, -0.3)
        legL.knee.rotation.x = 0.3 + 0.6 * Math.sin(u * Math.PI)
        legR.knee.rotation.x = 0.3 + 0.6 * Math.sin(u * Math.PI)
        lean = 0.25 * Math.sin(u * Math.PI)
        break
      }
      case 'stumble': {
        lean = 0.35 + Math.sin(u * Math.PI) * 0.35
        armL.sh.rotation.set(-1.0, 0, 0.9)
        armR.sh.rotation.set(-1.0, 0, -0.9)
        break
      }
      default:
        break
    }
  }
  // tronco gira contra as pernas na passada (como na corrida de verdade) e respira de leve parado
  const twist = a ? 0 : -s * amp * 0.16 + (moving ? 0 : Math.sin(time * 1.3 + rig.yaw * 3) * 0.04)
  body.rotation.set(lean, twist, roll)
  body.position.y = bob
}

// ---------- montagem ----------
export function createScene(canvas, opts) {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: !opts.pixel, powerPreference: 'high-performance' })
  renderer.shadowMap.enabled = true
  renderer.shadowMap.type = THREE.PCFSoftShadowMap
  renderer.toneMapping = THREE.ACESFilmicToneMapping
  renderer.toneMappingExposure = 1.05

  const scene = new THREE.Scene()
  const sky = new THREE.Color('#9fc6e8')
  scene.background = sky
  scene.fog = new THREE.Fog(sky, 170, 340)

  const hemi = new THREE.HemisphereLight('#dff0ff', '#3c5a2a', 1.25)
  scene.add(hemi)
  const sun = new THREE.DirectionalLight('#fff6e6', 2.3)
  sun.position.set(-25, 70, -55)
  sun.castShadow = true
  sun.shadow.mapSize.set(2048, 2048)
  const sc = sun.shadow.camera
  sc.left = -75
  sc.right = 75
  sc.top = 60
  sc.bottom = -60
  sc.near = 10
  sc.far = 200
  sun.shadow.bias = -0.0004
  sun.shadow.normalBias = 0.02
  scene.add(sun)

  // gramado
  // modo pixel: o gramado vem pronto (pixel3d.js), com textura sem suavização
  const { tex, tw, th } = opts.pitch || pitchTexture(renderer)
  const pitch = new THREE.Mesh(new THREE.PlaneGeometry(tw, th), new THREE.MeshLambertMaterial({ map: tex }))
  pitch.rotation.x = -Math.PI / 2
  pitch.receiveShadow = true
  scene.add(pitch)

  // modo pixel: estádio montado a partir da ficha (stadiums.js)
  const stadium = opts.stadiumDef ? buildStadiumFromDef(scene, opts.stadiumDef, opts) : buildStadium(scene, opts)
  const goals = [buildGoal(scene, 0), buildGoal(scene, 1)]

  // bola
  const ball = new THREE.Mesh(new THREE.SphereGeometry(0.16, 20, 14), new THREE.MeshLambertMaterial({ map: ballTexture() }))
  ball.castShadow = true
  scene.add(ball)

  const camera = new THREE.PerspectiveCamera(30, 16 / 9, 0.5, 600)
  camera.position.set(0, 26, W / 2 + 42)
  camera.lookAt(0, 0, 0)

  return { renderer, scene, camera, stadium, goals, ball, sun }
}

export const toWorld = (x, y, z = 0) => new THREE.Vector3(x - L / 2, z, y - W / 2)
export { THREE }
