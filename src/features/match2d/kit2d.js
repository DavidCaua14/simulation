// Kit tático 2D (campo visto de cima, marcadores em círculo, bola independente).
// Geometria do manifesto do kit: mundo 105 × 68; os PNGs do campo têm moldura lógica [-6, -5, 117, 78].
import campoH from './assets/campo_horizontal.png'
import campoV from './assets/campo_vertical.png'
import azul from './assets/jogador_azul.png'
import branco from './assets/jogador_branco.png'
import vermelho from './assets/jogador_vermelho.png'
import amarelo from './assets/jogador_amarelo.png'
import gkVerde from './assets/goleiro_verde.png'
import gkLaranja from './assets/goleiro_laranja.png'
import bola from './assets/bola.png'
import sombra from './assets/sombra_bola.png'
import posse from './assets/posse_amarela.png'
import gol from './assets/gol.png'
import cartaoAmarelo from './assets/cartao_amarelo.png'
import cartaoVermelho from './assets/cartao_vermelho.png'
import substituicao from './assets/substituicao.png'

export const FIELD = {
  h: { src: campoH, view: [-6, -5, 117, 78] },
  v: { src: campoV, view: [-5, -6, 78, 117] },
}

// Cores de cada marcador (do SVG do kit) e cor do número escrito por cima.
export const MARKERS = [
  { id: 'azul', src: azul, color: '#3b79c9', text: '#ffffff' },
  { id: 'vermelho', src: vermelho, color: '#cc4b48', text: '#ffffff' },
  { id: 'branco', src: branco, color: '#f2f4ee', text: '#143146' },
  { id: 'amarelo', src: amarelo, color: '#e9cb4c', text: '#143146' },
]
export const KEEPERS = {
  h: { src: gkVerde, text: '#0f3d27' },
  a: { src: gkLaranja, text: '#5a2a07' },
}

export const BALL = { src: bola, shadow: sombra, possession: posse }

// Avisos com arte do kit; os demais são só texto.
export const BANNER_ART = {
  goal: gol,
  pen_goal: gol,
  yellow: cartaoAmarelo,
  red: cartaoVermelho,
  second_yellow: cartaoVermelho,
  sub: substituicao,
}
export const BANNER_TEXT = {
  offside: 'Impedimento',
  injury: 'Lesão',
}

// Diâmetros visuais do manifesto (metros do mundo).
export const PLAYER_D = 2.2
export const BALL_D = 0.85

function hexRgb(hex) {
  const h = String(hex || '').replace('#', '')
  const n = parseInt(h.length === 3 ? h.split('').map((c) => c + c).join('') : h.padEnd(6, '0').slice(0, 6), 16)
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255]
}
function distance(a, b) {
  const [r1, g1, b1] = hexRgb(a)
  const [r2, g2, b2] = hexRgb(b)
  return Math.hypot(r1 - r2, g1 - g2, b1 - b2)
}

// Marcador mais parecido com a cor do clube; o visitante nunca repete o do mandante.
export function pickMarkers(homeColors = [], awayColors = []) {
  const best = (colors, except) => {
    let pick = null
    let score = Infinity
    for (const m of MARKERS) {
      if (m.id === except) continue
      for (const c of colors.filter(Boolean).slice(0, 2)) {
        const d = distance(c, m.color)
        if (d < score) {
          score = d
          pick = m
        }
      }
    }
    return pick || MARKERS.find((m) => m.id !== except)
  }
  const h = best(homeColors.length ? homeColors : ['#c8102e'])
  const a = best(awayColors.length ? awayColors : ['#1d4ed8'], h.id)
  return { h, a }
}

const cache = new Map()
function loadImage(src) {
  if (!cache.has(src)) {
    cache.set(
      src,
      new Promise((resolve, reject) => {
        const img = new Image()
        img.decoding = 'async'
        img.onload = () => resolve(img)
        img.onerror = reject
        img.src = src
      }),
    )
  }
  return cache.get(src)
}

export async function loadKit2d() {
  const entries = [
    ['fieldH', FIELD.h.src],
    ['fieldV', FIELD.v.src],
    ...MARKERS.map((m) => [m.id, m.src]),
    ['gk_h', KEEPERS.h.src],
    ['gk_a', KEEPERS.a.src],
    ['ball', BALL.src],
    ['shadow', BALL.shadow],
    ['possession', BALL.possession],
  ]
  const imgs = await Promise.all(entries.map(([, src]) => loadImage(src)))
  return Object.fromEntries(entries.map(([k], i) => [k, imgs[i]]))
}
