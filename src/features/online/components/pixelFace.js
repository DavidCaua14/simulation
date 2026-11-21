// ROSTO EM PIXEL ART do atleta (44×36 px): pele, cabelo, corte e barba sempre iguais para o mesmo nome; a camisa sai
// na cor do clube. Gera uma imagem PNG (data URL) uma vez por combinação e reaproveita (listas grandes não pesam).
// A imagem é pequena e é ampliada sem suavizar (CSS image-rendering: pixelated).

const SKINS = [
  ['#f2c6a0', '#d9a37c', '#b8805a'],
  ['#e0a878', '#c18456', '#9b6440'],
  ['#b97a4f', '#9a5f39', '#7a4527'],
  ['#8a5532', '#6c3f22', '#502c16'],
  ['#5e3a22', '#472a17', '#33200f'],
]
const HAIRS = ['#16100b', '#2b1a0e', '#4a2c14', '#7a4a1e', '#c58b3a', '#e8c36a', '#a8a8a8']
export const FACE_W = 44
export const FACE_H = 36

const hash = (s) => {
  let h = 2166136261
  for (const c of String(s || '')) h = Math.imul(h ^ c.charCodeAt(0), 16777619)
  return h >>> 0
}
function shade(hex, k) {
  const n = parseInt(String(hex || '#888888').replace('#', '').slice(0, 6), 16) || 0
  const f = (v) => Math.max(0, Math.min(255, Math.round(k < 0 ? v * (1 + k) : v + (255 - v) * k)))
  return `rgb(${f(n >> 16)},${f((n >> 8) & 255)},${f(n & 255)})`
}
const isHex = (c) => /^#[0-9a-f]{6}$/i.test(String(c || ''))

function draw(seed, shirt, trim) {
  const c = document.createElement('canvas')
  c.width = FACE_W
  c.height = FACE_H
  const g = c.getContext('2d')
  const h = hash(seed)
  const [sk, skD, skDD] = SKINS[h % SKINS.length]
  const hair = HAIRS[(h >>> 4) % HAIRS.length]
  const cut = (h >>> 8) % 5
  const beard = (h >>> 12) % 3 === 0
  const brow = shade(hair, -0.2)
  const R = (x, y, w, hh, col) => {
    g.fillStyle = col
    g.fillRect(x, y, w, hh)
  }
  // ombros e camisa, gola
  for (let y = 27; y < FACE_H; y += 1) {
    const half = Math.min(21, 11 + (y - 27) * 2)
    R(22 - half, y, half * 2, 1, shirt)
  }
  R(3, 33, 38, 3, shade(shirt, -0.22))
  R(15, 27, 14, 2, trim)
  R(17, 29, 10, 1, trim)
  // pescoço
  R(18, 25, 8, 4, skD)
  R(19, 29, 6, 1, skDD)
  // cabeça (oval) com sombra lateral e orelhas
  const rows = [[16, 12], [15, 14], [14, 16], [14, 16], [13, 18], [13, 18], [13, 18], [13, 18], [13, 18], [13, 18], [14, 16], [14, 16], [15, 14], [16, 12], [17, 10], [18, 8]]
  rows.forEach(([x, w], i) => R(x, 8 + i, w, 1, sk))
  rows.forEach(([x, w], i) => {
    if (i > 3) R(x + w - 3, 8 + i, 3, 1, skD)
  })
  R(12, 14, 2, 4, skD)
  R(30, 14, 2, 4, skD)
  // cabelo
  const top = [[16, 12], [14, 16], [13, 18], [13, 18]]
  if (cut === 0) top.forEach(([x, w], i) => R(x, 5 + i, w, 1, hair))
  if (cut === 1) {
    top.forEach(([x, w], i) => R(x, 4 + i, w, 1, hair))
    R(13, 8, 2, 6, hair)
    R(29, 8, 2, 6, hair)
  }
  if (cut === 2) {
    R(15, 6, 14, 2, shade(sk, -0.12))
    R(16, 7, 12, 1, hair)
  }
  if (cut === 3) {
    ;[[15, 14], [13, 18], [12, 20], [12, 20], [12, 20]].forEach(([x, w], i) => R(x, 3 + i, w, 1, hair))
    R(12, 8, 3, 7, hair)
    R(29, 8, 3, 7, hair)
  }
  if (cut === 4) {
    top.forEach(([x, w], i) => R(x, 5 + i, w, 1, hair))
    R(18, 3, 8, 2, hair)
    R(20, 2, 4, 1, hair)
  }
  // rosto
  R(16, 13, 4, 1, brow)
  R(24, 13, 4, 1, brow)
  R(17, 15, 2, 2, '#161014')
  R(25, 15, 2, 2, '#161014')
  R(17, 15, 1, 1, '#ffffff')
  R(25, 15, 1, 1, '#ffffff')
  R(21, 16, 2, 3, skD)
  R(21, 19, 2, 1, skDD)
  R(19, 21, 6, 1, skDD)
  R(20, 22, 4, 1, shade(sk, -0.05))
  if (beard) {
    R(15, 19, 2, 4, hair)
    R(27, 19, 2, 4, hair)
    R(16, 22, 12, 2, hair)
    R(18, 24, 8, 1, hair)
    R(19, 21, 6, 1, shade(sk, -0.25))
  }
  // contorno de 1 pixel
  const img = g.getImageData(0, 0, FACE_W, FACE_H)
  const d = img.data
  const out = new Uint8ClampedArray(d)
  const A = (x, y) => (x < 0 || y < 0 || x >= FACE_W || y >= FACE_H ? 0 : d[(y * FACE_W + x) * 4 + 3])
  for (let y = 0; y < FACE_H; y += 1) {
    for (let x = 0; x < FACE_W; x += 1) {
      if (A(x, y)) continue
      if (A(x - 1, y) || A(x + 1, y) || A(x, y - 1) || A(x, y + 1)) {
        const i = (y * FACE_W + x) * 4
        out[i] = 8
        out[i + 1] = 10
        out[i + 2] = 18
        out[i + 3] = 255
      }
    }
  }
  img.data.set(out)
  g.putImageData(img, 0, 0)
  return c.toDataURL('image/png')
}

const cache = new Map()
// shirt/trim: cores da camisa e da gola (as do clube). Sem cores, azul e branco.
export function pixelFaceUrl(seed, shirt, trim) {
  const a = isHex(shirt) ? shirt : '#1d4ed8'
  const b = isHex(trim) ? trim : '#ffffff'
  const key = `${seed}|${a}|${b}`
  let url = cache.get(key)
  if (!url) {
    if (typeof document === 'undefined') return ''
    try {
      url = draw(seed, a, b)
    } catch {
      url = ''
    }
    if (cache.size > 600) cache.clear()
    cache.set(key, url)
  }
  return url
}

// Nome curto para as miniaturas: o sobrenome (sem "de", "da", "Jr."), ou o primeiro nome se o sobrenome for longo.
export function shortName(n = '') {
  const w = String(n).split(' ').filter((x) => x && !/^(de|da|do|dos|das|jr\.?|júnior|g\.)$/i.test(x))
  if (w.length === 0) return n
  if (w.length === 1) return w[0]
  const last = w[w.length - 1]
  return last.length > 10 ? w[0] : last
}

