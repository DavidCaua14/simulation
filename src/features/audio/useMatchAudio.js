import { useEffect, useRef } from 'react'
import { useAudio } from './AudioContext'

// Som de cada lance REVELADO na tela (o mesmo momento em que o texto aparece). Só lances que o motor
// gerou de verdade: sem gol, sem comemoração; sem expulsão, sem som de expulsão.
export function soundFor(e, userSide) {
  switch (e.kind) {
    case 'kickoff': return 'kickoff'
    case 'ht': case 'et': return 'whistle_half'
    case 'ft': return 'whistle_end'
    case 'goal': case 'pen_goal': case 'so_goal': return e.side === userSide ? 'goal_for' : 'goal_against'
    case 'pen_miss': case 'so_miss': return 'chance'
    case 'save': case 'shot_off': return e.detail === 'grande chance' ? 'chance' : null
    case 'yellow': return 'card_yellow'
    case 'second_yellow': case 'red': return 'card_red'
    case 'offside': case 'injury': return 'foul'
    default: return null
  }
}

// visible: lances já mostrados · userSide: 'h'|'a' · score: {h, a} · minute: relógio da tela · active: partida na tela
export default function useMatchAudio({ visible, userSide, score, minute, active = true }) {
  const { startMatch, stopMatch, playSfx, matchIntensity } = useAudio()
  const seen = useRef(null)
  const boostUntil = useRef(0)

  // entra/sai da ambientação junto com a tela da partida
  useEffect(() => {
    if (!active) return undefined
    startMatch()
    return () => stopMatch()
  }, [active, startMatch, stopMatch])

  useEffect(() => {
    if (!active) return
    if (!seen.current) {
      // partida retomada: lances antigos não tocam de novo (só uma partida nova toca o apito inicial)
      seen.current = new Set(minute > 1 ? visible.map((e) => e.seq) : [])
    }
    for (const e of visible) {
      if (seen.current.has(e.seq)) continue
      seen.current.add(e.seq)
      const id = soundFor(e, userSide)
      if (id) playSfx(id)
      if (id === 'goal_for' || id === 'goal_against' || id === 'chance') boostUntil.current = performance.now() + 4000
    }
  }, [visible, userSide, minute, active, playSfx])

  // intensidade da torcida: mais alta depois de lances fortes e nos minutos finais de jogo apertado
  useEffect(() => {
    if (!active) return
    const close = Math.abs((score?.h ?? 0) - (score?.a ?? 0)) <= 1
    const late = minute >= 80
    const hot = performance.now() < boostUntil.current
    matchIntensity(hot ? 0.75 : late && close ? 0.55 : 0.35)
  }, [minute, score?.h, score?.a, active, matchIntensity])
}
