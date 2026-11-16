// Atletas com esqueleto e animações capturadas (protótipo): boneco Mannequin e animações do KayKit (CC0, Kay Lousberg),
// em public/models/kaykit. O diretor continua decidindo onde cada um está e o que faz; aqui só muda o desenho:
// uniforme pintado no boneco, parado/andar/correr misturados pela velocidade e animações de chute, mergulho, arremesso,
// comemoração e queda tocadas a partir de p.anim (o mesmo campo que o boneco antigo usa).
import * as THREE from 'three'
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js'
import { clone as cloneSkinned } from 'three/examples/jsm/utils/SkeletonUtils.js'

const HEIGHT = 1.8 // altura do atleta no campo (m)
const HEAD_SCALE = 0.68
const LEG_SCALE = 1.3
const SKINS = ['#f1c9a5', '#d8a07a', '#a8714b', '#6e4428']
const HAIR = '#1f1712'
const BOOTS = '#15171c'

let assets = null
let tries = 0
// Carrega o boneco e as animações uma vez por sessão (tenta de novo uma vez se a rede falhar). Devolve null se não
// der: a transmissão segue com o boneco antigo.
export function loadPlayerAssets() {
  if (!assets) {
    tries += 1
    const base = `${import.meta.env.BASE_URL || '/'}models/kaykit/`
    const loader = new GLTFLoader()
    assets = Promise.all([loader.loadAsync(`${base}mannequin.glb`), loader.loadAsync(`${base}anims.glb`)])
      .then(([model, anims]) => {
        const scene = model.scene
        scene.updateMatrixWorld(true)
        const box = new THREE.Box3().setFromObject(scene)
        const clips = Object.fromEntries(anims.animations.map((c) => [c.name, c]))
        return { scene, clips, minY: box.min.y, height: box.max.y - box.min.y, kits: new Map() }
      })
      .catch((err) => {
        console.error('[atletas 3D]', err)
        assets = null
        return tries < 2 ? new Promise((r) => setTimeout(r, 1500)).then(loadPlayerAssets) : null
      })
  }
  return assets
}

// Pinta o uniforme por vértice, pela altura de cada ponto com o boneco em pé (pose de ligação):
// cabeça pele (topo cabelo) · tronco camisa · quadril e coxa calção · canela meião · pé chuteira; braços com manga.
function kitGeometry(a, mesh, kit, skin) {
  const g = mesh.geometry.clone()
  const pos = g.attributes.position
  const col = new Float32Array(pos.count * 3)
  const c = new THREE.Color()
  const tmp = new THREE.Vector3()
  const name = mesh.name.toLowerCase()
  const shirt = new THREE.Color(kit.shirt)
  const shorts = new THREE.Color(kit.shorts)
  const socks = new THREE.Color(kit.socks)
  const skinC = new THREE.Color(skin)
  // braços: extensão em x para separar a manga da mão/antebraço
  // e cabeça: altura própria (o cabelo é a parte de cima dela)
  let ax0 = Infinity
  let ax1 = -Infinity
  let hy0 = Infinity
  let hy1 = -Infinity
  for (let i = 0; i < pos.count; i += 1) {
    tmp.fromBufferAttribute(pos, i).applyMatrix4(mesh.matrixWorld)
    ax0 = Math.min(ax0, Math.abs(tmp.x))
    ax1 = Math.max(ax1, Math.abs(tmp.x))
    hy0 = Math.min(hy0, tmp.y)
    hy1 = Math.max(hy1, tmp.y)
  }
  for (let i = 0; i < pos.count; i += 1) {
    tmp.fromBufferAttribute(pos, i).applyMatrix4(mesh.matrixWorld)
    const h = (tmp.y - a.minY) / a.height
    if (name.includes('head')) c.copy((tmp.y - hy0) / Math.max(1e-6, hy1 - hy0) > 0.72 ? new THREE.Color(HAIR) : skinC)
    else if (name.includes('arm')) c.copy((Math.abs(tmp.x) - ax0) / Math.max(1e-6, ax1 - ax0) < 0.4 ? shirt : skinC)
    else if (name.includes('leg')) c.copy(h > 0.33 ? shorts : h > 0.07 ? socks : new THREE.Color(BOOTS))
    else c.copy(h > 0.47 ? shirt : shorts)
    col[i * 3] = c.r
    col[i * 3 + 1] = c.g
    col[i * 3 + 2] = c.b
  }
  g.setAttribute('color', new THREE.BufferAttribute(col, 3))
  return g
}

const material = new THREE.MeshLambertMaterial({ vertexColors: true })

// Locomoção: parado, andar, correr e disparar, cada um com a velocidade (m/s) em que a animação fica natural
const GAITS = [
  ['Idle_A', 0],
  ['Walking_A', 1.6],
  ['Running_A', 4.6],
  ['Running_B', 7],
]
// p.anim do diretor → animação do pacote
const ONE_SHOT = {
  kick: 'Melee_Unarmed_Attack_Kick',
  throw: 'Throw',
  stumble: 'Hit_A',
  celebrate: 'Cheering',
  dive_left: 'Dodge_Left',
  dive_right: 'Dodge_Right',
  catch: 'Crouching',
  catch_low: 'Crouching',
  catch_high: 'Jump_Full_Short',
  jump: 'Jump_Full_Short',
  getup: 'Lie_StandUp',
}

// kit: { shirt, shorts, socks }; seed: id do jogador (tom de pele)
export function createPlayerRig(a, kit, seed) {
  let h = 0
  for (const ch of String(seed)) h = (h * 31 + ch.charCodeAt(0)) >>> 0
  const skin = SKINS[h % SKINS.length]
  const key = `${kit.shirt}|${kit.shorts}|${kit.socks}|${skin}`
  if (!a.kits.has(key)) {
    const geos = new Map()
    a.scene.traverse((o) => {
      if (o.isSkinnedMesh) geos.set(o.name, kitGeometry(a, o, kit, skin))
    })
    a.kits.set(key, geos)
  }
  const geos = a.kits.get(key)
  const model = cloneSkinned(a.scene)
  model.traverse((o) => {
    if (o.isSkinnedMesh) {
      o.geometry = geos.get(o.name) || o.geometry
      o.material = material
      o.castShadow = true
      o.frustumCulled = false
    }
  })
  // pernas alongadas (LEG_SCALE): o boneco sobe o que as pernas cresceram e a escala refaz a altura de 1,80 m
  if (a.legLen == null) {
    const w = new THREE.Vector3()
    const y = (n) => {
      let b = null
      a.scene.traverse((o) => {
        if (o.isBone && o.name === n) b = o
      })
      return b ? b.getWorldPosition(w).y : null
    }
    const hip = y('upperleg.l')
    const foot = y('foot.l')
    a.legLen = hip != null && foot != null ? Math.max(0, hip - foot) : a.height * 0.4
  }
  const extra = a.legLen * (LEG_SCALE - 1)
  const k = HEIGHT / (a.height + extra)
  model.scale.setScalar(k)
  model.position.y = (-a.minY + extra) * k
  const root = new THREE.Group()
  root.add(model)
  const mixer = new THREE.AnimationMixer(model)
  const act = (name) => (a.clips[name] ? mixer.clipAction(a.clips[name]) : null)
  const gaits = GAITS.map(([name, v]) => ({ action: act(name), v })).filter((g) => g.action)
  for (const g of gaits) {
    g.action.play()
    g.action.setEffectiveWeight(0)
  }
  // proporção de atleta: o boneco do pacote é cabeçudo; a cabeça fica menor (o osso é escalado a cada quadro,
  // depois das animações)
  // pernas mais longas e tronco um pouco mais estreito (o osso cresce no próprio eixo, y)
  const bones = {}
  model.traverse((o) => {
    if (o.isBone) bones[o.name] = o
  })
  const legs = ['upperleg.l', 'upperleg.r', 'lowerleg.l', 'lowerleg.r'].map((n) => bones[n] || bones[n.replace('.', '')]).filter(Boolean)
  const chest = bones.chest || null
  return { root, mixer, act, gaits, head: bones.head || null, legs, chest, yaw: 0, oneShot: null, animRef: null, kay: true }
}

const clamp = (v, a, b) => Math.max(a, Math.min(b, v))

// Atualiza o atleta: direção do corpo, mistura da locomoção pela velocidade e a animação do lance (p.anim).
export function poseKayPlayer(rig, p, ballPos, dt) {
  const sp = Math.hypot(p.vx || 0, p.vy || 0)
  // direção: para onde corre; parado, olha para a bola (giro suave, curva mais aberta em velocidade)
  let want = rig.yaw
  if (sp > 0.35) want = Math.atan2(p.vx, p.vy)
  else if (ballPos) want = Math.atan2(ballPos.x - p.x, ballPos.y - p.y)
  const busy = p.anim && (p.anim.name.startsWith('dive') || p.anim.name === 'getup')
  if (!busy) {
    let d = want - rig.yaw
    d = Math.atan2(Math.sin(d), Math.cos(d))
    rig.yaw += d * Math.min(1, dt * (sp > 0.35 ? 6 - clamp(sp / 7.6, 0, 1) * 2 : 3))
  }
  rig.root.rotation.y = rig.yaw

  // lance do momento (chute, mergulho, comemoração...): toca uma vez por cima da locomoção
  if (p.anim && p.anim !== rig.animRef) {
    rig.animRef = p.anim
    const name = ONE_SHOT[p.anim.name]
    const action = name ? rig.act(name) : null
    if (rig.oneShot && rig.oneShot !== action) rig.oneShot.fadeOut(0.12)
    if (action) {
      const loop = p.anim.name === 'celebrate'
      action.reset()
      action.setLoop(loop ? THREE.LoopRepeat : THREE.LoopOnce, loop ? Infinity : 1)
      action.clampWhenFinished = !loop
      // o tempo da animação acompanha o do diretor (o chute encosta na bola quando a bola sai)
      if (!loop && p.anim.dur) action.timeScale = clamp(action.getClip().duration / Math.max(0.2, p.anim.dur), 0.6, 3)
      else action.timeScale = 1
      action.fadeIn(0.1).play()
      rig.oneShot = action
    } else rig.oneShot = null
  }
  if (!p.anim && rig.animRef) {
    rig.animRef = null
    if (rig.oneShot) rig.oneShot.fadeOut(0.18)
    rig.oneShot = null
  }

  // locomoção: mistura as duas marchas vizinhas pela velocidade e acerta o passo (timeScale)
  const g = rig.gaits
  const shot = rig.oneShot ? rig.oneShot.getEffectiveWeight() : 0
  let i = 0
  while (i < g.length - 2 && sp > g[i + 1].v) i += 1
  const lo = g[i]
  const hi = g[i + 1] || g[i]
  const k = hi === lo ? 0 : clamp((sp - lo.v) / Math.max(0.01, hi.v - lo.v), 0, 1)
  for (const gg of g) {
    const w = gg === lo ? 1 - k : gg === hi ? k : 0
    const cur = gg.action.getEffectiveWeight()
    const target = w * (1 - shot)
    gg.action.setEffectiveWeight(cur + (target - cur) * Math.min(1, dt * 10))
    if (gg.v > 0) gg.action.timeScale = clamp(sp / gg.v, 0.6, 1.5)
  }
  rig.mixer.update(dt)
  if (rig.head) rig.head.scale.setScalar(HEAD_SCALE)
  for (const b of rig.legs) b.scale.set(1, LEG_SCALE, 1)
  if (rig.chest) rig.chest.scale.set(0.9, 1, 0.9)
}
