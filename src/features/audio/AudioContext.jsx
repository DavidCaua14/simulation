import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react'
import { PLAYLIST, DEFAULT_VOLUME } from './playlist'

/**
 * Música de fundo com arquivos locais (<audio>).
 *
 * O <AudioProvider> fica NO TOPO do app (acima do Gate), então o player nunca é
 * desmontado: loading, login, troca de tela... a música segue tocando.
 * Quando uma faixa termina, vai para a próxima; depois da última, recomeça.
 *
 * Limitação dos navegadores: som só pode começar depois de um toque do usuário.
 * O provider tenta tocar ao abrir e, se for bloqueado, começa no primeiro toque.
 */

const STORAGE_KEY = 'fc:audio'
const BASE = import.meta.env?.BASE_URL ?? '/'

// 'audio/01.mp3' -> '/audio/01.mp3' (respeita o "base" do Vite). Links https:// ficam como estão.
const resolveSrc = (src) => (/^(https?:)?\/\//.test(src) ? src : BASE + String(src).replace(/^\//, ''))
const TRACKS = PLAYLIST.filter((t) => t.src).map((t) => ({ ...t, url: resolveSrc(t.src) }))

const AudioCtx = createContext(null)

function readSettings() {
  try {
    const raw = JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}')
    return {
      volume: Number.isFinite(raw.volume) ? Math.max(0, Math.min(100, raw.volume)) : DEFAULT_VOLUME,
      muted: !!raw.muted,
      enabled: raw.enabled !== false, // false = jogador pausou de propósito
    }
  } catch {
    return { volume: DEFAULT_VOLUME, muted: false, enabled: true }
  }
}

export function AudioProvider({ children }) {
  const audioRef = useRef(null)
  const errorsRef = useRef(0)

  const [initial] = useState(readSettings)
  const [volume, setVolumeState] = useState(initial.volume)
  const [muted, setMuted] = useState(initial.muted)
  const [enabled, setEnabled] = useState(initial.enabled)
  const [index, setIndex] = useState(0)
  const [playing, setPlaying] = useState(false)

  // Valores mais recentes para usar dentro dos eventos do <audio> (registrados uma vez só)
  const live = useRef({})
  live.current = { volume, muted, enabled, index }

  const tryPlay = useCallback(() => {
    // O navegador pode recusar antes do primeiro toque; o toque seguinte destrava (efeito abaixo).
    audioRef.current?.play()?.catch(() => {})
  }, [])

  const goTo = useCallback(
    (target, { play = true } = {}) => {
      const total = TRACKS.length
      const audio = audioRef.current
      if (!total || !audio) return
      const next = ((target % total) + total) % total
      setIndex(next)
      audio.src = TRACKS[next].url
      if (play) tryPlay()
    },
    [tryPlay],
  )

  // Cria o player uma única vez
  useEffect(() => {
    if (!TRACKS.length) {
      console.warn('[audio] Nenhuma faixa configurada. Edite src/features/audio/playlist.js')
      return undefined
    }
    const audio = new Audio()
    audio.preload = 'auto'
    audio.src = TRACKS[0].url
    audio.volume = live.current.volume / 100
    audio.muted = live.current.muted
    audioRef.current = audio

    const onPlaying = () => {
      errorsRef.current = 0
      setPlaying(true)
    }
    const onPause = () => setPlaying(false)
    const onEnded = () => goTo(live.current.index + 1) // próxima; depois da última volta à primeira
    const onError = () => {
      errorsRef.current += 1
      console.warn('[audio] não foi possível abrir:', TRACKS[live.current.index]?.url)
      if (errorsRef.current >= TRACKS.length) {
        setPlaying(false) // nenhuma faixa abre: para de tentar
        return
      }
      goTo(live.current.index + 1)
    }

    audio.addEventListener('playing', onPlaying)
    audio.addEventListener('pause', onPause)
    audio.addEventListener('ended', onEnded)
    audio.addEventListener('error', onError)

    if (live.current.enabled) tryPlay()

    return () => {
      audio.removeEventListener('playing', onPlaying)
      audio.removeEventListener('pause', onPause)
      audio.removeEventListener('ended', onEnded)
      audio.removeEventListener('error', onError)
      audio.pause()
      audio.removeAttribute('src')
      audio.load()
      audioRef.current = null
    }
  }, [goTo, tryPlay])

  // Aplica volume / mudo
  useEffect(() => {
    const audio = audioRef.current
    if (!audio) return
    audio.volume = volume / 100
    audio.muted = muted
  }, [volume, muted])

  // Guarda preferências
  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify({ volume, muted, enabled }))
    } catch {
      /* ignore */
    }
  }, [volume, muted, enabled])

  // Se o navegador bloqueou o início automático, o primeiro toque do usuário libera o som
  useEffect(() => {
    if (playing || !enabled || !TRACKS.length) return undefined
    const events = ['pointerdown', 'keydown', 'touchend']
    events.forEach((ev) => document.addEventListener(ev, tryPlay))
    return () => events.forEach((ev) => document.removeEventListener(ev, tryPlay))
  }, [playing, enabled, tryPlay])

  const togglePlay = useCallback(() => {
    const audio = audioRef.current
    if (!audio) return
    if (playing) {
      setEnabled(false)
      audio.pause()
    } else {
      setEnabled(true)
      tryPlay()
    }
  }, [playing, tryPlay])

  const next = useCallback(() => {
    setEnabled(true)
    goTo(live.current.index + 1)
  }, [goTo])

  const prev = useCallback(() => {
    setEnabled(true)
    goTo(live.current.index - 1)
  }, [goTo])

  const setVolume = useCallback((v) => {
    const clamped = Math.max(0, Math.min(100, Math.round(v)))
    setVolumeState(clamped)
    if (clamped > 0) setMuted(false)
  }, [])

  const toggleMute = useCallback(() => setMuted((m) => !m), [])

  const value = useMemo(
    () => ({
      tracks: TRACKS,
      track: TRACKS[index] ?? null,
      index,
      hasTracks: TRACKS.length > 0,
      playing,
      ready: true,
      volume,
      muted,
      setVolume,
      toggleMute,
      togglePlay,
      next,
      prev,
    }),
    [index, playing, volume, muted, setVolume, toggleMute, togglePlay, next, prev],
  )

  return <AudioCtx.Provider value={value}>{children}</AudioCtx.Provider>
}

export function useAudio() {
  const ctx = useContext(AudioCtx)
  if (!ctx) throw new Error('useAudio deve ser usado dentro de <AudioProvider>')
  return ctx
}
