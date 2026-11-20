// ARTE EM PIXEL dos atletas e do estádio (desenhada por código, sem arquivos; usada pelo modo pixel da transmissão 3D): atletas em camadas (pele, cabelo, camisa, calção,
// meião e chuteira) com as cores de cada time, gramado com listras, gols com rede, placas, arquibancada com torcida e
// bancos de reservas. Tudo sai em <canvas> pequenos; o Pixi amplia sem suavizar (pixel nítido).

// Projeção oblíqua: x em metros vira PX pixels, y vira PY (campo "deitado", como câmera alta inclinada) e a altura
// (z) sobe PZ pixels por metro.
export const PX = 8
export const PY = 6
export const PZ = 8
export const FW = 16 // quadro do atleta
export const FH = 24
export const FOOT = 22 // linha dos pés dentro do quadro
// margens em volta do gramado (pixels): arquibancada em cima, banco embaixo
export const M = { left: 96, right: 96, top: 132, bottom: 84 }

const L = 105
const W = 68

// ─── cores ───────────────────────────────────────────────────────────────────
function hexRgb(hex) {
  let h = String(hex || '#888888').replace('#', '')
  if (h.length === 3) h = h.split('').map((c) => c + c).join('')
  const n = parseInt(h.slice(0, 6), 16) || 0
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255]
}
const rgbHex = ([r, g, b]) => `#${[r, g, b].map((v) => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0')).join('')}`
export const shade = (hex, k) => rgbHex(hexRgb(hex).map((v) => (k < 0 ? v * (1 + k) : v + (255 - v) * k)))
export function colorDist(a, b) {
  const [r1, g1, b1] = hexRgb(a)
  const [r2, g2, b2] = hexRgb(b)
  const r = (r1 + r2) / 2
  return Math.sqrt((2 + r / 256) * (r1 - r2) ** 2 + 4 * (g1 - g2) ** 2 + (2 + (255 - r) / 256) * (b1 - b2) ** 2)
}

// Uniformes que se distinguem (mesma regra da transmissão 3D, sem depender do three.js).
const KEEPER_COLORS = ['#22c55e', '#f472b6', '#f97316', '#eab308', '#a855f7', '#06b6d4']
const REF_COLORS = ['#111827', '#facc15', '#ec4899', '#14b8a6']
const farthest = (list, avoid) => [...list].sort((a, b) => Math.min(...avoid.map((c) => colorDist(b, c))) - Math.min(...avoid.map((c) => colorDist(a, c))))[0]
export function kitsFor(hc = [], ac = []) {
  const h0 = hc[0] || '#c8102e'
  const h1 = hc[1] || '#ffffff'
  const score = ([s0, s1]) => Math.min(colorDist(s0, h0), Math.max(colorDist(s0, h1), colorDist(s1, h0)) * 2)
  const own = [ac[0] || '#1d4ed8', ac[1] || '#ffffff']
  const options = [own, [own[1], own[0]], ['#f4f4f4', '#f4f4f4'], ['#f4f4f4', '#111827'], ['#1e3a8a', '#ffffff'], ['#111827', '#111827'], ['#facc15', '#111827'], ['#0ea5e9', '#ffffff']]
  const pick = options.find((o) => score(o) >= 200) || [...options].sort((x, y) => score(y) - score(x))[0]
  const [a0, a1] = pick
  const gkH = farthest(KEEPER_COLORS, [h0, a0, h1, a1])
  const gkA = farthest(KEEPER_COLORS.filter((c) => c !== gkH), [h0, a0, h1, a1, gkH])
  const ref = farthest(REF_COLORS, [h0, a0, gkH, gkA])
  return {
    h: { shirt: h0, shorts: h1, socks: h0 },
    a: { shirt: a0, shorts: a1, socks: a0 },
    gk_h: { shirt: gkH, shorts: '#1f2937', socks: gkH, gloves: true },
    gk_a: { shirt: gkA, shorts: '#1f2937', socks: gkA, gloves: true },
    ref: { shirt: ref, shorts: '#111827', socks: '#111827' },
  }
}

// aparência de cada atleta (estável pelo id): pele, cabelo e corte
const SKINS = [['#f2c6a0', '#d9a37c'], ['#e0a878', '#c18456'], ['#b97a4f', '#9a5f39'], ['#8a5532', '#6c3f22'], ['#5e3a22', '#472a17']]
const HAIRS = ['#1b1209', '#2b1a0e', '#4a2c14', '#7a4a1e', '#c58b3a', '#e8c36a', '#8c8c8c', '#a23b1d']
const hash = (s) => {
  let h = 2166136261
  for (const c of String(s)) h = Math.imul(h ^ c.charCodeAt(0), 16777619)
  return (h >>> 0) / 4294967296
}
export function lookOf(id) {
  const a = hash(`${id}:skin`)
  const b = hash(`${id}:hair`)
  const c = hash(`${id}:style`)
  return { skin: Math.floor(a * SKINS.length), hair: Math.floor(b * HAIRS.length), style: Math.floor(c * 4) }
}

// ─── atleta ──────────────────────────────────────────────────────────────────
// Folha de quadros: linhas = vista (0 frente, 1 lado olhando para a direita, 2 costas); colunas = pose.
export const POSES = ['idle', 'run0', 'run1', 'run2', 'run3', 'kick0', 'kick1', 'celebrate', 'catch', 'dive', 'sit']
export const VIEWS = ['front', 'side', 'back']

function frameCanvas() {
  const c = document.createElement('canvas')
  c.width = FW
  c.height = FH
  return c
}

// contorno escuro de 1 pixel em volta da figura (o que dá a cara de pixel art)
function outline(g, w, h, color = [20, 16, 24, 235]) {
  const img = g.getImageData(0, 0, w, h)
  const d = img.data
  const out = new Uint8ClampedArray(d)
  const at = (x, y) => (x < 0 || y < 0 || x >= w || y >= h ? 0 : d[(y * w + x) * 4 + 3])
  for (let y = 0; y < h; y += 1) {
    for (let x = 0; x < w; x += 1) {
      if (at(x, y) > 0) continue
      if (at(x - 1, y) > 0 || at(x + 1, y) > 0 || at(x, y - 1) > 0 || at(x, y + 1) > 0) {
        const i = (y * w + x) * 4
        out[i] = color[0]
        out[i + 1] = color[1]
        out[i + 2] = color[2]
        out[i + 3] = color[3]
      }
    }
  }
  img.data.set(out)
  g.putImageData(img, 0, 0)
}

function drawFigure(g, view, pose, pal) {
  const px = (x, y, c) => {
    g.fillStyle = c
    g.fillRect(x, y, 1, 1)
  }
  const rect = (x, y, w, h, c) => {
    g.fillStyle = c
    g.fillRect(x, y, w, h)
  }
  const { skin, skinD, hair, shirt, shirtD, shorts, socks, boot, glove } = pal
  const hand = glove || skin

  // deitado (mergulho do goleiro): corpo na horizontal, olhando para a direita
  if (pose === 'dive') {
    const y0 = 15
    rect(1, y0 + 1, 3, 3, socks)
    rect(0, y0 + 2, 1, 2, boot)
    rect(4, y0 + 1, 2, 3, shorts)
    rect(6, y0, 5, 4, shirt)
    rect(6, y0 + 3, 5, 1, shirtD)
    rect(11, y0, 4, 4, skin)
    rect(11, y0, 4, 1, hair)
    px(14, y0 + 2, '#20140c')
    rect(13, y0 - 2, 2, 2, hand) // braço esticado
    rect(12, y0 - 1, 1, 1, shirt)
    return
  }
  if (pose === 'sit') {
    // sentado (levantando do chão / banco)
    rect(5, 11, 6, 6, shirt)
    rect(5, 16, 6, 1, shirtD)
    rect(5, 4, 6, 7, skin)
    rect(5, 3, 6, 2, hair)
    rect(4, 17, 8, 2, shorts)
    rect(9, 19, 4, 2, socks)
    rect(12, 21, 2, 1, boot)
    rect(3, 19, 4, 2, socks)
    rect(2, 21, 2, 1, boot)
    return
  }

  const run = pose.startsWith('run') ? Number(pose[3]) : -1
  const bob = run === 1 || run === 3 ? -1 : 0 // corpo sobe na passada
  const armsUp = pose === 'celebrate' || pose === 'catch'

  if (view === 'side') {
    const o = bob
    // pernas: pés à frente/atrás conforme a passada (ou o chute)
    const feet = {
      idle: [[1, 0], [-1, 0]],
      run0: [[2, 0], [-2, -1]],
      run1: [[1, -2], [0, 0]],
      run2: [[-2, -1], [2, 0]],
      run3: [[0, 0], [1, -2]],
      kick0: [[-3, -2], [0, 0]],
      kick1: [[4, -3], [0, 0]],
      celebrate: [[1, 0], [-1, 0]],
      catch: [[1, 0], [-1, 0]],
    }[pose] || [[1, 0], [-1, 0]]
    const leg = ([fx, lift], back) => {
      const hipX = back ? 6 : 8
      const top = 18 + o
      const fy = FOOT + lift
      for (let y = top; y <= fy; y += 1) {
        const k = (y - top) / Math.max(1, fy - top)
        const x = Math.round(hipX + fx * k)
        const c = y >= fy - 2 ? socks : back ? skinD : skin
        rect(x, y, 2, 1, c)
      }
      rect(Math.round(hipX + fx) + (back ? 0 : 1), fy, 2, 1, boot)
    }
    leg(feet[1], true)
    // tronco
    rect(5, 16 + o, 6, 2, shorts)
    rect(5, 11 + o, 6, 5, shirt)
    rect(5, 11 + o, 1, 5, shirtD)
    // braço de trás
    const swing = run === 0 ? 2 : run === 2 ? -2 : 0
    if (!armsUp) {
      rect(6 - swing, 12 + o, 1, 3, shirtD)
      px(6 - swing, 15 + o, skinD)
    }
    leg(feet[0], false)
    // cabeça (olhando para a direita): cabelo na nuca e no topo
    rect(10 - 3, 10 + o, 2, 1, skin) // pescoço
    rect(5, 4 + o, 6, 6, skin)
    rect(5, 9 + o, 6, 1, skinD)
    rect(5, 3 + o, 6, 2, hair)
    rect(5, 5 + o, 2, pal.style === 1 ? 4 : 2, hair)
    if (pal.style === 2) rect(6, 2 + o, 4, 1, hair)
    if (pal.style === 3) rect(4, 4 + o, 1, 3, hair)
    px(9, 6 + o, '#20140c') // olho
    px(10, 8 + o, skinD)
    // braço da frente
    if (armsUp) {
      rect(8, 7 + o, 1, 4, shirt)
      rect(8, 5 + o, 1, 2, hand)
      rect(5, 7 + o, 1, 4, shirtD)
      rect(5, 5 + o, 1, 2, hand)
    } else {
      rect(8 + swing, 12 + o, 1, 2, shirt)
      rect(8 + swing, 14 + o, 1, 1, skin)
      px(8 + swing, 15 + o, hand)
    }
    return
  }

  // frente e costas
  const back = view === 'back'
  const o = bob
  const lift = { run0: [0, -2], run1: [0, 0], run2: [-2, 0], run3: [0, 0], kick0: [-2, 0], kick1: [-3, 0] }[pose] || [0, 0]
  const legs = (x, l, c) => {
    rect(x, 18 + o, 2, FOOT - 18 - o + l - 1, c)
    rect(x, FOOT + l - 2, 2, 2, socks)
    rect(x, FOOT + l, 2, 1, boot)
  }
  legs(5, lift[0], skin)
  legs(9, lift[1], skin)
  rect(5, 16 + o, 6, 2, shorts)
  px(7 + 0, 17 + o, shade(shorts, -0.25))
  rect(4, 11 + o, 8, 5, shirt)
  rect(4, 15 + o, 8, 1, shirtD)
  if (back) rect(6, 12 + o, 4, 3, shade(shirt, colorDist(shirt, '#ffffff') > 300 ? 0.55 : -0.45)) // número
  // braços
  if (armsUp) {
    rect(3, 7 + o, 1, 4, shirt)
    rect(12, 7 + o, 1, 4, shirt)
    rect(3, 5 + o, 1, 2, hand)
    rect(12, 5 + o, 1, 2, hand)
  } else {
    const sw = run === 0 ? 1 : run === 2 ? -1 : 0
    rect(3, 11 + o + sw, 1, 2, shirt)
    rect(12, 11 + o - sw, 1, 2, shirt)
    rect(3, 13 + o + sw, 1, 2, skin)
    rect(12, 13 + o - sw, 1, 2, skin)
    px(3, 15 + o + sw, hand)
    px(12, 15 + o - sw, hand)
  }
  // cabeça
  rect(7, 10 + o, 2, 1, skinD)
  rect(5, 4 + o, 6, 6, skin)
  rect(5, 3 + o, 6, 2, hair)
  if (back) rect(5, 4 + o, 6, pal.style === 1 ? 5 : 3, hair)
  else {
    rect(5, 5 + o, 1, pal.style === 1 ? 4 : 1, hair)
    rect(10, 5 + o, 1, pal.style === 1 ? 4 : 1, hair)
    px(6, 6 + o, '#20140c')
    px(9, 6 + o, '#20140c')
    px(7, 8 + o, skinD)
    px(8, 8 + o, skinD)
  }
  if (pal.style === 2) rect(6, 2 + o, 4, 1, hair)
  if (pal.style === 3) {
    px(4, 5 + o, hair)
    px(11, 5 + o, hair)
  }
}

// cantos da cabeça (6×7 px) arredondados: tira os 4 pixels das quinas
function roundHead(g, pose) {
  const o = pose === 'run1' || pose === 'run3' ? -1 : 0
  for (const [x, y] of [[5, 3], [10, 3], [5, 9], [10, 9]]) g.clearRect(x, y + o, 1, 1)
}

// Folha completa de um atleta: 3 vistas × 11 poses, com contorno.
export function playerSheet(kit, look) {
  const [skin, skinD] = SKINS[look.skin % SKINS.length]
  const pal = {
    skin,
    skinD,
    hair: HAIRS[look.hair % HAIRS.length],
    style: look.style,
    shirt: kit.shirt,
    shirtD: shade(kit.shirt, -0.28),
    shorts: kit.shorts,
    socks: kit.socks,
    boot: '#16161d',
    glove: kit.gloves ? '#f8fafc' : null,
  }
  const sheet = document.createElement('canvas')
  sheet.width = FW * POSES.length
  sheet.height = FH * VIEWS.length
  const sg = sheet.getContext('2d')
  VIEWS.forEach((view, r) => {
    POSES.forEach((pose, c) => {
      const f = frameCanvas()
      const g = f.getContext('2d')
      drawFigure(g, view, pose, pal)
      if (pose !== 'dive' && pose !== 'sit') roundHead(g, pose)
      outline(g, FW, FH)
      sg.drawImage(f, c * FW, r * FH)
    })
  })
  return sheet
}

// técnico na beira do campo (terno)
export function coachSheet(look) {
  return playerSheet({ shirt: '#2b2f3a', shorts: '#2b2f3a', socks: '#2b2f3a' }, look)
}

// ─── bola e sombras ──────────────────────────────────────────────────────────
export function ballCanvas() {
  const c = document.createElement('canvas')
  c.width = 5
  c.height = 5
  const g = c.getContext('2d')
  const rows = ['.www.', 'wwkww', 'wkwkw', 'wwwkw', '.www.']
  rows.forEach((row, y) =>
    row.split('').forEach((ch, x) => {
      if (ch === '.') return
      g.fillStyle = ch === 'w' ? '#ffffff' : '#2b2b2b'
      g.fillRect(x, y, 1, 1)
    }),
  )
  return c
}
export function shadowCanvas(w = 12, h = 4) {
  const c = document.createElement('canvas')
  c.width = w
  c.height = h
  const g = c.getContext('2d')
  g.fillStyle = 'rgba(0,0,0,0.32)'
  for (let y = 0; y < h; y += 1) {
    const k = 1 - Math.abs((y + 0.5) / h - 0.5) * 2
    const half = Math.round((w / 2) * Math.sqrt(Math.max(0.15, k)))
    g.fillRect(w / 2 - half, y, half * 2, 1)
  }
  return c
}
// marcador sobre o jogador (triângulo)
export function markerCanvas(color) {
  const c = document.createElement('canvas')
  c.width = 7
  c.height = 5
  const g = c.getContext('2d')
  const rows = ['ooooooo', 'occccco', '.occco.', '..oco..', '...o...']
  rows.forEach((row, y) =>
    row.split('').forEach((ch, x) => {
      if (ch === '.') return
      g.fillStyle = ch === 'o' ? '#0b1020' : color
      g.fillRect(x, y, 1, 1)
    }),
  )
  return c
}

// ─── estádio ─────────────────────────────────────────────────────────────────
export const worldSize = () => ({ w: M.left + L * PX + M.right, h: M.top + W * PY + M.bottom })
export const toScreen = (x, y, z = 0) => [M.left + x * PX, M.top + y * PY - z * PZ]

// Gramado, linhas, placas, arquibancada vazia (a torcida é outra camada) e bancos.
export function fieldCanvas({ ads = [], adColors = [] } = {}) {
  const { w, h } = worldSize()
  const c = document.createElement('canvas')
  c.width = w
  c.height = h
  const g = c.getContext('2d')
  const rect = (x, y, ww, hh, col) => {
    g.fillStyle = col
    g.fillRect(Math.round(x), Math.round(y), Math.round(ww), Math.round(hh))
  }
  const fx = M.left
  const fy = M.top
  const fw = L * PX
  const fh = W * PY

  // gramado inteiro (inclui a área fora das linhas) com listras largas
  const grassA = '#43b065'
  const grassB = '#3a9d59'
  const top = M.top - 34
  rect(0, top, w, h - top, grassA)
  const band = (L * PX) / 14
  for (let i = -6; i < 20; i += 1) if (i % 2) rect(fx + i * band, top, band, h - top, grassB)
  // textura leve: pixels soltos mais claros/escuros
  for (let i = 0; i < (w * h) / 55; i += 1) {
    const x = Math.floor(hash(`gx${i}`) * w)
    const y = top + Math.floor(hash(`gy${i}`) * (h - top))
    rect(x, y, 1, 1, hash(`gc${i}`) > 0.5 ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.06)')
  }

  // linhas
  const line = 'rgba(240,250,240,0.92)'
  const hl = (x1, x2, y) => rect(Math.min(x1, x2), y, Math.abs(x2 - x1) + 1, 1, line)
  const vl = (x, y1, y2) => rect(x, Math.min(y1, y2), 1, Math.abs(y2 - y1) + 1, line)
  const P = (x, y) => [Math.round(fx + x * PX), Math.round(fy + y * PY)]
  const box = (x1, y1, x2, y2) => {
    const [a, b] = P(x1, y1)
    const [cc, d] = P(x2, y2)
    hl(a, cc, b)
    hl(a, cc, d)
    vl(a, b, d)
    vl(cc, b, d)
  }
  box(0, 0, L, W)
  vl(P(L / 2, 0)[0], P(0, 0)[1], P(0, W)[1])
  const ellipse = (cx, cy, r, from = 0, to = Math.PI * 2) => {
    for (let k = 0; k < 720; k += 1) {
      const a = from + ((to - from) * k) / 720
      const [x, y] = P(cx + Math.cos(a) * r, cy + Math.sin(a) * r)
      rect(x, y, 1, 1, line)
    }
  }
  ellipse(L / 2, W / 2, 9.15)
  rect(...P(L / 2, W / 2).map((v) => v - 1), 3, 2, line)
  for (const side of [0, 1]) {
    const x0 = side ? L : 0
    const dir = side ? -1 : 1
    box(Math.min(x0, x0 + dir * 16.5), W / 2 - 20.16, Math.max(x0, x0 + dir * 16.5), W / 2 + 20.16)
    box(Math.min(x0, x0 + dir * 5.5), W / 2 - 9.16, Math.max(x0, x0 + dir * 5.5), W / 2 + 9.16)
    const [sx, sy] = P(x0 + dir * 11, W / 2)
    rect(sx - 1, sy, 2, 1, line)
    // meia-lua: só a parte de fora da grande área
    const a = Math.acos(5.5 / 9.15)
    ellipse(x0 + dir * 11, W / 2, 9.15, side ? Math.PI - a : -a, side ? Math.PI + a : a)
    for (const cy of [0, W]) ellipse(x0, cy, 1, 0, Math.PI * 2)
  }

  // placas de publicidade em cima (atrás da linha lateral) e nas laterais do gol
  const adY = fy - 30
  const adH = 12
  const panels = Math.ceil(w / 120)
  for (let i = 0; i < panels; i += 1) {
    const x = i * 120
    const col = adColors[i % Math.max(1, adColors.length)] || ['#0f172a', '#1d4ed8', '#be123c', '#047857'][i % 4]
    rect(x, adY, 120, adH, col)
    rect(x, adY, 120, 1, shade(col, 0.35))
    rect(x, adY + adH - 1, 120, 1, shade(col, -0.4))
    rect(x + 119, adY, 1, adH, '#0b1020')
    const text = ads[i % Math.max(1, ads.length)] || 'FUTEBOL'
    g.font = 'bold 8px monospace'
    g.textAlign = 'center'
    g.textBaseline = 'middle'
    g.fillStyle = colorDist(col, '#ffffff') > 250 ? '#ffffff' : '#0b1020'
    g.fillText(text, x + 60, adY + adH / 2 + 1)
  }
  rect(0, adY + adH, w, 2, 'rgba(0,0,0,0.25)')

  // arquibancada: degraus (a torcida é desenhada por cima, em outra camada)
  const standTop = 0
  const standBot = adY - 2
  rect(0, standTop, w, standBot - standTop, '#232a45')
  for (let y = standTop + 4; y < standBot; y += 8) {
    rect(0, y, w, 1, '#2f3860')
    rect(0, y + 6, w, 1, '#171c30')
  }
  // escadas da arquibancada
  for (let x = 60; x < w; x += 170) rect(x, standTop, 8, standBot - standTop, '#3a4470')

  // bancos de reservas (cobertura de acrílico) embaixo, dos dois lados do meio-campo
  const benchY = fy + fh + 26
  for (const bx of [fx + fw / 2 - 150, fx + fw / 2 + 60]) {
    rect(bx, benchY, 90, 22, 'rgba(15,23,42,0.55)')
    rect(bx, benchY, 90, 3, '#cbd5e1')
    for (let i = 0; i < 6; i += 1) {
      const sx = bx + 4 + i * 14
      rect(sx, benchY + 6, 10, 12, '#1e3a8a')
      rect(sx + 1, benchY + 7, 8, 5, '#2563eb')
    }
    rect(bx, benchY + 3, 90, 2, 'rgba(255,255,255,0.35)')
    rect(bx, benchY + 20, 90, 2, '#475569')
  }
  // área técnica (linha tracejada)
  for (let x = fx + fw / 2 - 160; x < fx + fw / 2 + 160; x += 6) rect(x, benchY - 6, 3, 1, 'rgba(240,250,240,0.6)')
  return c
}

// Gol (trave, travessão e rede) em leve perspectiva: as traves inclinam para fora do campo e a rede desce até o
// fundo. side 0 = esquerda, 1 = direita. Fica na camada dos atletas, ordenado pela linha de fundo do gol.
export function goalCanvas(side) {
  const depth = Math.round(2.4 * PX)
  const half = Math.round(3.66 * PY)
  const hgt = Math.round(2.9 * PZ) // um pouco mais alto que o real: lê melhor na câmera de cima
  const lean = 5 // inclinação das traves (pixels)
  const pad = 3
  const c = document.createElement('canvas')
  c.width = depth + lean + pad * 2 + 2
  c.height = half * 2 + hgt + pad * 2 + 2
  const g = c.getContext('2d')
  const dir = side ? 1 : -1 // para onde a rede vai (para fora do campo)
  const ox = side ? pad : c.width - pad - 1 // linha do gol dentro do canvas
  const y0 = pad + hgt // base da trave de cima
  const y1 = y0 + half * 2 // base da trave de baixo
  const dot = (x, y, col) => {
    g.fillStyle = col
    g.fillRect(Math.round(x), Math.round(y), 1, 1)
  }
  const line = (x0, ya, x1, yb, col, w = 1) => {
    const n = Math.max(Math.abs(x1 - x0), Math.abs(yb - ya), 1)
    for (let k = 0; k <= n; k += 1) {
      const x = x0 + ((x1 - x0) * k) / n
      const y = ya + ((yb - ya) * k) / n
      g.fillStyle = col
      g.fillRect(Math.round(x), Math.round(y), w, 1)
    }
  }
  const tx = ox + dir * lean // topo das traves
  const bx = ox + dir * depth // fundo da rede no chão
  const btx = ox + dir * (depth - 2) // fundo da rede no alto (mais baixo que o travessão)
  const bty = 0.55
  const net = 'rgba(236,242,248,0.6)'
  const netD = 'rgba(200,210,222,0.45)'
  // teto da rede (do travessão até o fundo) e fundo (do alto até o chão): malha de 3 px
  for (let k = 0; k <= half * 2; k += 3) {
    line(tx, y0 - hgt + k, btx, y0 - hgt * bty + k, net)
    line(btx, y0 - hgt * bty + k, bx, y0 + k, netD)
  }
  for (let t = 0; t <= 1.001; t += 0.2) {
    line(tx + (btx - tx) * t, y0 - hgt + (hgt - hgt * bty) * t, tx + (btx - tx) * t, y1 - hgt + (hgt - hgt * bty) * t, net)
  }
  for (let t = 0; t <= 1.001; t += 0.34) line(btx + (bx - btx) * t, y0 - hgt * bty + hgt * bty * t, btx + (bx - btx) * t, y1 - hgt * bty + hgt * bty * t, netD)
  // laterais da rede (lado de cima e de baixo)
  for (const yb of [y0, y1]) {
    line(tx, yb - hgt, btx, yb - hgt * bty, net)
    line(btx, yb - hgt * bty, bx, yb, net)
    line(ox, yb, bx, yb, netD)
  }
  // traves e travessão (branco com sombra)
  const post = '#ffffff'
  const postD = '#9aa8bb'
  for (const yb of [y0, y1]) {
    line(ox + dir, yb + 1, tx + dir, yb - hgt + 1, postD)
    line(ox, yb, tx, yb - hgt, post, 2)
  }
  line(tx + dir, y0 - hgt + 1, tx + dir, y1 - hgt + 1, postD)
  line(tx, y0 - hgt, tx, y1 - hgt, post, 2)
  dot(ox, y0, post)
  dot(ox, y1, post)
  // (ox, y0) no canvas = ponto (linha do gol, W/2 - 3,66) no chão
  return { canvas: c, ox, y0 }
}

// Torcida: dois quadros (sentada/pulando) com as cores dos dois times e cores neutras.
export function crowdCanvases(colors = []) {
  const { w } = worldSize()
  const h = M.top - 34 - 4
  const palette = [...colors, ...colors, '#e2e8f0', '#64748b', '#f59e0b', '#0f172a']
  const frames = [0, 1].map(() => {
    const c = document.createElement('canvas')
    c.width = w
    c.height = h
    return c
  })
  const rows = Math.floor((h - 4) / 8)
  for (let r = 0; r < rows; r += 1) {
    for (let x = 2; x < w - 4; x += 5) {
      if ((x - 60) % 170 < 9 && x > 50) continue // escada
      const id = `${r}:${x}`
      if (hash(`empty${id}`) < 0.07) continue
      const shirt = palette[Math.floor(hash(`shirt${id}`) * palette.length)]
      const skin = SKINS[Math.floor(hash(`skin${id}`) * SKINS.length)][0]
      const hair = HAIRS[Math.floor(hash(`hair${id}`) * HAIRS.length)]
      const jumper = hash(`jump${id}`) < 0.6
      frames.forEach((c, f) => {
        const g = c.getContext('2d')
        const up = f === 1 && jumper ? 2 : 0
        const y = 3 + r * 8 - up
        g.fillStyle = shirt
        g.fillRect(x, y + 3, 4, 4)
        g.fillStyle = skin
        g.fillRect(x + 1, y, 2, 3)
        g.fillStyle = hair
        g.fillRect(x + 1, y, 2, 1)
        if (f === 1 && jumper) {
          g.fillStyle = skin
          g.fillRect(x, y - 1, 1, 2)
          g.fillRect(x + 3, y - 1, 1, 2)
        }
      })
    }
  }
  return frames
}
