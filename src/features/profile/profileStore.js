import { useCallback, useSyncExternalStore } from 'react'
import { DEFAULT_BANNER_ID } from './data/banners'

/**
 * Preferências visuais do perfil (banner, foto, vitrine pública).
 * Hoje ficam no navegador (localStorage, uma entrada por usuário).
 * Para sincronizar entre aparelhos depois, troque read/write por chamadas ao
 * Supabase — o resto do app não precisa mudar (veja o README).
 */
const KEY = 'fc:profile:'
const DEFAULTS = { bannerId: DEFAULT_BANNER_ID, avatarUrl: null, showcasePublic: true }

const cache = new Map()
const listeners = new Set()

function read(userId) {
  if (!cache.has(userId)) {
    let value = { ...DEFAULTS }
    try {
      const raw = localStorage.getItem(KEY + userId)
      if (raw) value = { ...DEFAULTS, ...JSON.parse(raw) }
    } catch {
      /* ignore */
    }
    cache.set(userId, value)
  }
  return cache.get(userId)
}

function write(userId, patch) {
  const next = { ...read(userId), ...patch }
  cache.set(userId, next)
  try {
    localStorage.setItem(KEY + userId, JSON.stringify(next))
  } catch {
    /* sem espaço: mantém só em memória */
  }
  listeners.forEach((l) => l())
}

function subscribe(listener) {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

// [prefs, update] — qualquer tela que usar isso atualiza junto (ex.: foto no topo da Home)
export function useProfilePrefs(userId) {
  const prefs = useSyncExternalStore(subscribe, () => read(userId))
  const update = useCallback((patch) => write(userId, patch), [userId])
  return [prefs, update]
}

// Recorta a imagem em quadrado 256x256 e devolve data URL leve (~20 KB)
export function fileToAvatar(file, size = 256) {
  return new Promise((resolve, reject) => {
    if (!file?.type?.startsWith('image/')) return reject(new Error('Escolha um arquivo de imagem.'))
    const url = URL.createObjectURL(file)
    const img = new Image()
    img.onload = () => {
      const side = Math.min(img.width, img.height)
      const canvas = document.createElement('canvas')
      canvas.width = size
      canvas.height = size
      canvas.getContext('2d').drawImage(img, (img.width - side) / 2, (img.height - side) / 2, side, side, 0, 0, size, size)
      URL.revokeObjectURL(url)
      resolve(canvas.toDataURL('image/jpeg', 0.85))
    }
    img.onerror = () => {
      URL.revokeObjectURL(url)
      reject(new Error('Não foi possível ler essa imagem.'))
    }
    img.src = url
  })
}
