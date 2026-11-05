import kitData from './assets/kitData.json'
import sprites from './assets/sprites.json'

// Arte do kit 2.5D (WebP gerados por scripts/build-kit-assets.py a partir dos PNGs originais).
const urls = import.meta.glob('./assets/*.webp', { eager: true, query: '?url', import: 'default' })
const url = (file) => urls[`./assets/${file}`]

export const KIT = kitData
export const SCENE = kitData.scene
// Animações dos atletas (scripts/build-sprite-atlases.py): parado e corrida em 8 direções, comemoração, goleiro.
export const SPRITES = sprites

// Projeção do manifesto: mundo em metros (x 0–105 no comprimento, y 0–68 na largura, z altura) → cena 1672×941.
const P = SCENE.projection
export function project(x, y, z = 0) {
  return [P.origin_px[0] + P.x_vector_px_per_m[0] * x + P.y_vector_px_per_m[0] * y, P.origin_px[1] + P.y_vector_px_per_m[1] * y + P.z_vector_px_per_m[1] * z]
}
// Mesma projeção como matriz afim do canvas (para gramado e linhas).
export const GROUND = [P.x_vector_px_per_m[0], 0, P.y_vector_px_per_m[0], P.y_vector_px_per_m[1], P.origin_px[0], P.origin_px[1]]

function loadImage(src) {
  return new Promise((resolve, reject) => {
    const img = new Image()
    img.decoding = 'async'
    img.onload = () => resolve(img)
    img.onerror = reject
    img.src = src
  })
}

let cache = null
export function loadKit() {
  if (cache) return cache
  const names = Object.keys(kitData.images)
  const atlases = Object.keys(sprites.atlases)
  cache = Promise.all([
    ...names.map((n) => loadImage(url(kitData.images[n].file)).then((img) => [n, img])),
    ...atlases.map((n) => loadImage(url(sprites.atlases[n].file)).then((img) => [`sprite_${n}`, img])),
  ]).then((pairs) => Object.fromEntries(pairs))
  cache.catch(() => {
    cache = null
  })
  return cache
}
export const imageUrl = (name) => url(kitData.images[name]?.file)

const hex = (c) => {
  const m = /^#?([0-9a-f]{6})$/i.exec(c || '')
  if (!m) return null
  const n = parseInt(m[1], 16)
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255]
}
const lum = (rgb) => (0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]) / 255
export function colorDistance(a, b) {
  const x = hex(a)
  const y = hex(b)
  if (!x || !y) return 999
  return Math.hypot(x[0] - y[0], x[1] - y[1], x[2] - y[2])
}

// Recolore as camisas do atlas vermelho com a cor do clube (uma vez por partida, num canvas fora da tela).
// Só pixels nitidamente vermelhos mudam: pele, calção e chuteiras ficam como estão.
export function tintAtlas(img, color) {
  const rgb = hex(color)
  const c = document.createElement('canvas')
  c.width = img.width
  c.height = img.height
  const g = c.getContext('2d', { willReadFrequently: true })
  g.drawImage(img, 0, 0)
  if (!rgb) return c
  const data = g.getImageData(0, 0, c.width, c.height)
  const d = data.data
  const bright = lum(rgb) < 0.18 ? 1.6 : 1.15
  for (let i = 0; i < d.length; i += 4) {
    const r = d[i]
    const gg = d[i + 1]
    const b = d[i + 2]
    if (d[i + 3] < 20 || r < 55 || r < gg * 1.7 || r < b * 1.6) continue
    const shade = Math.min(1.35, (r / 190) * bright)
    d[i] = Math.min(255, rgb[0] * shade + 12)
    d[i + 1] = Math.min(255, rgb[1] * shade + 12)
    d[i + 2] = Math.min(255, rgb[2] * shade + 12)
  }
  g.putImageData(data, 0, 0)
  return c
}
