// ESTÁDIOS do modo pixel: cada estádio é uma ficha (dados) e o gerador monta o 3D a partir dela. A imagem em baixa
// resolução do modo pixel deixa tudo com cara de pixel art. Para criar um estádio novo basta uma ficha nova.
//
// Ficha:
//  name, capacity (texto), sky (cor do céu), apron (cor da pista/entorno do gramado)
//  grass: { pattern: 'stripes' | 'diagonal' | 'checker' | 'circles' | 'plain', colors: [clara, escura] }
//  tiers: anéis da arquibancada, de baixo para cima: [{ rows, seats: [cor, cor2?], stripe: 'rows' | 'blocks' | null }]
//  sides: lados com arquibancada ('back' = oposto à câmera, 'left', 'right')
//  roof: 'none' | 'back' | 'full' (cobertura) · roofColor
//  press: tribuna de imprensa no meio do lado de trás (true/false)
//  lights: torres de refletores nos cantos (true/false)
//  surround: 'city' | 'sea' | 'trees' | 'hills' | 'none' (o que aparece atrás do estádio)
//  crowd: ocupação da torcida (0 a 1)
import * as THREE from 'three'
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js'
import { L, W } from '../match2d/director'

export const STADIUMS = [
  {
    id: 'arena',
    name: 'Arena Central',
    capacity: '62 mil',
    sky: '#7fb7ea',
    apron: '#2b3445',
    grass: { pattern: 'stripes', colors: ['#3fbf6a', '#36a95c'] },
    tiers: [
      { rows: 12, seats: ['#c8202f', '#a31826'], stripe: 'rows' },
      { rows: 10, seats: ['#d63041', '#ffffff'], stripe: 'blocks' },
    ],
    sides: ['back', 'left', 'right'],
    roof: 'full',
    roofColor: '#e9edf3',
    press: true,
    lights: false,
    surround: 'city',
    crowd: 0.92,
  },
  {
    id: 'concreto',
    name: 'Estádio do Povo',
    capacity: '38 mil',
    sky: '#a9c7d8',
    apron: '#7a6a58',
    grass: { pattern: 'checker', colors: ['#46a85a', '#3d9650'] },
    tiers: [{ rows: 18, seats: ['#9aa1a8', '#8a9097'], stripe: 'rows' }],
    sides: ['back', 'left', 'right'],
    roof: 'back',
    roofColor: '#5b6470',
    press: true,
    lights: true,
    surround: 'city',
    crowd: 0.78,
  },
  {
    id: 'interior',
    name: 'Campo do Interior',
    capacity: '9 mil',
    sky: '#8fd0f2',
    apron: '#5f8f3c',
    grass: { pattern: 'plain', colors: ['#5cb83c', '#52a836'] },
    tiers: [{ rows: 7, seats: ['#1d5fb8', '#f2f2f2'], stripe: 'blocks' }],
    sides: ['back'],
    roof: 'none',
    roofColor: '#c9c9c9',
    press: false,
    lights: true,
    surround: 'trees',
    crowd: 0.55,
  },
  {
    id: 'praia',
    name: 'Estádio da Orla',
    capacity: '27 mil',
    sky: '#8ad3ff',
    apron: '#d9c48f',
    grass: { pattern: 'diagonal', colors: ['#38c79a', '#2fb08a'] },
    tiers: [{ rows: 11, seats: ['#f5a623', '#1b9ad6'], stripe: 'blocks' }],
    sides: ['back', 'left'],
    roof: 'none',
    roofColor: '#ffffff',
    press: false,
    lights: true,
    surround: 'sea',
    crowd: 0.7,
  },
  {
    id: 'neon',
    name: 'Arena Neon',
    capacity: '45 mil',
    sky: '#1a1035',
    apron: '#2a1748',
    grass: { pattern: 'diagonal', colors: ['#3ad6c4', '#2ab3b0'] },
    tiers: [
      { rows: 10, seats: ['#7c3aed', '#6d28d9'], stripe: 'rows' },
      { rows: 10, seats: ['#a855f7', '#e879f9'], stripe: 'blocks' },
    ],
    sides: ['back', 'left', 'right'],
    roof: 'full',
    roofColor: '#3b2a63',
    press: true,
    lights: false,
    surround: 'none',
    crowd: 0.95,
  },
  {
    id: 'circulos',
    name: 'Estádio Municipal',
    capacity: '21 mil',
    sky: '#9fd8ef',
    apron: '#a83a32',
    grass: { pattern: 'circles', colors: ['#3ea055', '#348c49'] },
    tiers: [{ rows: 13, seats: ['#e11d48', '#be123c'], stripe: 'rows' }],
    sides: ['back', 'left', 'right'],
    roof: 'back',
    roofColor: '#f1f5f9',
    press: true,
    lights: true,
    surround: 'hills',
    crowd: 0.66,
  },
]

export const stadiumById = (id) => STADIUMS.find((s) => s.id === id) || STADIUMS[0]

// estádio fixo de cada clube (pelo nome/id): o mesmo clube sempre joga no mesmo estádio
export function stadiumFor(key) {
  let h = 0
  for (const c of String(key || '')) h = (h * 31 + c.charCodeAt(0)) >>> 0
  return STADIUMS[h % STADIUMS.length]
}

const lam = (color, extra = {}) => new THREE.MeshLambertMaterial({ color, ...extra })

function seeded(seed) {
  let s = seed >>> 0 || 1
  return () => ((s = (s * 16807) % 2147483647) / 2147483647)
}

// Monta o estádio da ficha. Devolve a mesma interface do estádio padrão: { crowd, bounce(t, k) }.
export function buildStadiumFromDef(scene, def, { crowdColors = [], ads = [] } = {}) {
  const group = new THREE.Group()
  scene.add(group)
  const rnd = seeded(def.id.length * 7919 + 13)
  scene.background = new THREE.Color(def.sky)
  scene.fog = new THREE.Fog(def.sky, 190, 380)

  // entorno do gramado (pista)
  const apron = new THREE.Mesh(new THREE.PlaneGeometry(L + 70, W + 100), lam(def.apron))
  apron.rotation.x = -Math.PI / 2
  apron.position.y = -0.03
  apron.receiveShadow = true
  group.add(apron)

  // lados: comprimento e posição de um degrau a uma distância d do campo
  const SIDES = {
    back: { len: L + 16, at: (d) => [0, -(W / 2 + 7 + d)], rotY: Math.PI },
    right: { len: W + 8, at: (d) => [L / 2 + 8 + d, 0], rotY: Math.PI / 2 },
    left: { len: W + 8, at: (d) => [-(L / 2 + 8 + d), 0], rotY: -Math.PI / 2 },
  }
  const STEP_D = 0.85
  const STEP_H = 0.5
  const crowdSpots = []
  const byColor = new Map() // cor → geometrias (um mesh por cor)
  const addGeo = (color, geo) => {
    if (!byColor.has(color)) byColor.set(color, [])
    byColor.get(color).push(geo)
  }
  let outer = 0 // profundidade total das arquibancadas
  let top = 0 // altura do último degrau
  for (const sideId of def.sides) {
    const s = SIDES[sideId]
    let d = 0
    let h0 = 1.2
    def.tiers.forEach((tier, ti) => {
      if (ti > 0) {
        // anel de cima: começa mais alto, com uma faixa de concreto entre os anéis
        d += 1.2
        h0 += 2.4
        const band = new THREE.BoxGeometry(s.len, 1.4, 1.2)
        const [bx, bz] = s.at(d - 0.6)
        band.rotateY(s.rotY)
        band.translate(bx, h0 - 0.7, bz)
        addGeo('#3b4250', band)
      }
      for (let r = 0; r < tier.rows; r += 1) {
        const h = h0 + r * STEP_H
        const [cx, cz] = s.at(d + STEP_D / 2)
        // degrau: listras por fileira ou blocos alternados ao longo do lado
        if (tier.stripe === 'blocks') {
          const blocks = Math.max(3, Math.round(s.len / 9))
          for (let k = 0; k < blocks; k += 1) {
            const bl = s.len / blocks
            const geo = new THREE.BoxGeometry(bl, h, STEP_D)
            const along = -s.len / 2 + bl * (k + 0.5)
            geo.translate(along, 0, 0)
            geo.rotateY(s.rotY)
            geo.translate(cx, h / 2, cz)
            addGeo(tier.seats[(k % 2) && tier.seats[1] ? 1 : 0], geo)
          }
        } else {
          const geo = new THREE.BoxGeometry(s.len, h, STEP_D)
          geo.rotateY(s.rotY)
          geo.translate(cx, h / 2, cz)
          addGeo(tier.seats[tier.stripe === 'rows' && r % 2 && tier.seats[1] ? 1 : 0], geo)
        }
        // torcida neste degrau
        const seats = Math.floor(s.len / 0.62)
        for (let k = 0; k < seats; k += 1) {
          if (rnd() > def.crowd) continue
          const along = -s.len / 2 + (k + 0.5) * (s.len / seats)
          const out = d + STEP_D * 0.55
          let x
          let z
          if (sideId === 'back') [x, z] = [along, -(W / 2 + 7 + out)]
          else if (sideId === 'right') [x, z] = [L / 2 + 8 + out, along]
          else [x, z] = [-(L / 2 + 8 + out), along]
          crowdSpots.push({ x, y: h, z, rot: s.rotY, ph: rnd() * Math.PI * 2, hgt: 0.62 + rnd() * 0.22 })
        }
        d += STEP_D
        top = Math.max(top, h)
      }
      h0 += tier.rows * STEP_H
    })
    outer = Math.max(outer, d)
    // parede do fundo
    const wallH = top + 2.5
    const [wx, wz] = s.at(d + 0.3)
    const wall = new THREE.BoxGeometry(s.len, wallH, 0.6)
    wall.rotateY(s.rotY)
    wall.translate(wx, wallH / 2, wz)
    addGeo('#4a5260', wall)
  }
  for (const [color, geos] of byColor) {
    const mesh = new THREE.Mesh(mergeGeometries(geos), lam(color))
    mesh.receiveShadow = true
    group.add(mesh)
  }

  // cobertura (sobre as arquibancadas): pilares no fundo e laje inclinada
  const roofY = top + 5
  const roofSides = def.roof === 'full' ? def.sides : def.roof === 'back' ? def.sides.filter((x) => x === 'back') : []
  for (const sideId of roofSides) {
    const s = SIDES[sideId]
    const depth = outer + 3
    const [rx, rz] = s.at(outer / 2 + 0.5)
    const slab = new THREE.Mesh(new THREE.BoxGeometry(s.len + 6, 0.6, depth), lam(def.roofColor))
    slab.rotation.y = s.rotY
    slab.position.set(rx, roofY, rz)
    slab.castShadow = true
    group.add(slab)
    // borda escura na frente da cobertura
    const [ex, ez] = s.at(-1)
    const edge = new THREE.Mesh(new THREE.BoxGeometry(s.len + 6, 0.9, 0.4), lam('#2b3140'))
    edge.rotation.y = s.rotY
    edge.position.set(ex, roofY - 0.1, ez)
    group.add(edge)
    const n = Math.max(3, Math.round(s.len / 18))
    for (let k = 0; k <= n; k += 1) {
      const along = -s.len / 2 + (s.len * k) / n
      const [px, pz] = s.at(outer + 0.5)
      const pillar = new THREE.Mesh(new THREE.BoxGeometry(0.7, roofY, 0.7), lam('#6b7380'))
      if (sideId === 'back') pillar.position.set(along, roofY / 2, pz)
      else pillar.position.set(px, roofY / 2, along)
      group.add(pillar)
    }
  }

  // tribuna de imprensa no meio do lado de trás (caixa com vidros)
  if (def.press && def.sides.includes('back')) {
    const [px, pz] = SIDES.back.at(outer * 0.55)
    const press = new THREE.Mesh(new THREE.BoxGeometry(22, 4, 4), lam('#c98a2b'))
    press.position.set(px, top * 0.7 + 3, pz)
    group.add(press)
    const glass = new THREE.Mesh(new THREE.BoxGeometry(20, 1.6, 0.2), new THREE.MeshBasicMaterial({ color: '#ffe08a' }))
    glass.position.set(px, top * 0.7 + 3.2, pz + 2.05)
    group.add(glass)
  }

  // refletores nos cantos
  if (def.lights) {
    for (const [lx, lz] of [[-L / 2 - 14, -W / 2 - 16], [L / 2 + 14, -W / 2 - 16], [-L / 2 - 14, W / 2 + 18], [L / 2 + 14, W / 2 + 18]]) {
      const hgt = top + 16
      const pole = new THREE.Mesh(new THREE.BoxGeometry(0.8, hgt, 0.8), lam('#6b7280'))
      pole.position.set(lx, hgt / 2, lz)
      const panel = new THREE.Mesh(new THREE.BoxGeometry(5, 3, 0.6), new THREE.MeshBasicMaterial({ color: '#fff7d1' }))
      panel.position.set(lx, hgt + 1, lz)
      panel.lookAt(0, 0, 0)
      group.add(pole, panel)
    }
  }

  // entorno: o que se vê atrás do estádio
  const far = W / 2 + 7 + outer + 14
  if (def.surround === 'city') {
    for (let k = 0; k < 46; k += 1) {
      const w = 8 + rnd() * 14
      const h = 10 + rnd() * 38
      const ang = -Math.PI + (k / 46) * Math.PI
      const r = 120 + rnd() * 40
      const b = new THREE.Mesh(new THREE.BoxGeometry(w, h, w), lam(['#8796a8', '#a9b4c2', '#6e7c8f', '#c4b9a8'][k % 4]))
      b.position.set(Math.cos(ang) * r, h / 2 - 1, Math.sin(ang) * r * 0.75 - 20)
      group.add(b)
    }
  } else if (def.surround === 'sea') {
    const sea = new THREE.Mesh(new THREE.PlaneGeometry(900, 260), lam('#2d8fd5'))
    sea.rotation.x = -Math.PI / 2
    sea.position.set(0, -0.2, -far - 130)
    group.add(sea)
    for (let k = 0; k < 5; k += 1) {
      const hill = new THREE.Mesh(new THREE.SphereGeometry(30 + rnd() * 25, 10, 6), lam(k % 2 ? '#3f8f3a' : '#4fa244'))
      hill.scale.y = 0.5
      hill.position.set(-200 + k * 100 + rnd() * 40, -4, -far - 230)
      group.add(hill)
    }
  } else if (def.surround === 'trees' || def.surround === 'hills') {
    if (def.surround === 'hills') {
      for (let k = 0; k < 6; k += 1) {
        const hill = new THREE.Mesh(new THREE.SphereGeometry(40 + rnd() * 30, 10, 6), lam(k % 2 ? '#5aa04a' : '#6cb356'))
        hill.scale.y = 0.45
        hill.position.set(-260 + k * 105, -6, -far - 120 - rnd() * 40)
        group.add(hill)
      }
    }
    const trunk = lam('#6b4423')
    const leaf = [lam('#2f7d32'), lam('#3d9a3f'), lam('#256b29')]
    for (let k = 0; k < 70; k += 1) {
      const ang = -Math.PI * 1.05 + (k / 70) * Math.PI * 1.1
      const r = 95 + rnd() * 45
      const x = Math.cos(ang) * r * 1.2
      const z = Math.sin(ang) * r * 0.7 - 15
      const t = new THREE.Mesh(new THREE.BoxGeometry(0.8, 4, 0.8), trunk)
      t.position.set(x, 2, z)
      const c = new THREE.Mesh(new THREE.ConeGeometry(3 + rnd() * 2, 8 + rnd() * 5, 6), leaf[k % 3])
      c.position.set(x, 8, z)
      group.add(t, c)
    }
  }

  // placas de publicidade (lado de trás e fundos)
  {
    const cv = document.createElement('canvas')
    cv.width = 512
    cv.height = 32
    const g = cv.getContext('2d')
    for (let i = 0; i < 4; i += 1) {
      const dark = i % 2 === 0
      g.fillStyle = dark ? '#0f1b33' : '#f1f5f9'
      g.fillRect(i * 128, 0, 128, 32)
      g.fillStyle = dark ? '#ffffff' : '#0f1b33'
      g.font = 'bold 16px monospace'
      g.textAlign = 'center'
      g.textBaseline = 'middle'
      g.fillText(ads[i % Math.max(1, ads.length)] || 'FUTEBOL', i * 128 + 64, 17)
    }
    const tex = new THREE.CanvasTexture(cv)
    tex.colorSpace = THREE.SRGBColorSpace
    tex.magFilter = THREE.NearestFilter
    tex.wrapS = THREE.RepeatWrapping
    const mk = (w, x, z, ry) => {
      const t = tex.clone()
      t.needsUpdate = true
      t.repeat.set(w / 20, 1)
      const m = new THREE.MeshBasicMaterial({ map: t })
      const board = new THREE.Mesh(new THREE.BoxGeometry(w, 0.9, 0.15), [lam('#0f1b33'), lam('#0f1b33'), lam('#0f1b33'), lam('#0f1b33'), m, m])
      board.position.set(x, 0.45, z)
      board.rotation.y = ry
      group.add(board)
    }
    mk(L + 8, 0, -(W / 2 + 4), 0)
    mk((W - 18) / 2, L / 2 + 5, (W + 18) / 4, -Math.PI / 2)
    mk((W - 18) / 2, L / 2 + 5, -(W + 18) / 4, -Math.PI / 2)
    mk((W - 18) / 2, -(L / 2 + 5), (W + 18) / 4, Math.PI / 2)
    mk((W - 18) / 2, -(L / 2 + 5), -(W + 18) / 4, Math.PI / 2)
  }

  // torcida (caixinhas coloridas que pulam no gol)
  const personGeo = new THREE.BoxGeometry(0.42, 1, 0.3)
  personGeo.translate(0, 0.5, 0)
  const crowd = new THREE.InstancedMesh(personGeo, lam('#ffffff'), Math.max(1, crowdSpots.length))
  const m = new THREE.Matrix4()
  const q = new THREE.Quaternion()
  const sc = new THREE.Vector3()
  const pos = new THREE.Vector3()
  const col = new THREE.Color()
  const up = new THREE.Vector3(0, 1, 0)
  const palette = [...crowdColors, ...crowdColors, '#f1f1f1', '#1f2937']
  crowdSpots.forEach((c, i) => {
    q.setFromAxisAngle(up, c.rot)
    sc.set(1, c.hgt, 1)
    pos.set(c.x, c.y, c.z)
    m.compose(pos, q, sc)
    crowd.setMatrixAt(i, m)
    col.set(palette[Math.floor(rnd() * palette.length)] || '#e5e7eb')
    crowd.setColorAt(i, col)
  })
  crowd.instanceMatrix.needsUpdate = true
  group.add(crowd)

  return {
    crowd,
    crowdSpots,
    group,
    bounce(t, k) {
      if (k <= 0.001 && !crowd.userData.dirty) return
      crowd.userData.dirty = k > 0.001
      crowdSpots.forEach((c, i) => {
        q.setFromAxisAngle(up, c.rot)
        sc.set(1, c.hgt, 1)
        pos.set(c.x, c.y + Math.max(0, Math.sin(t * 9 + c.ph)) * 0.35 * k, c.z)
        m.compose(pos, q, sc)
        crowd.setMatrixAt(i, m)
      })
      crowd.instanceMatrix.needsUpdate = true
    },
  }
}
