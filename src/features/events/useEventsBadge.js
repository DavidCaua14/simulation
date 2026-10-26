import { useEffect, useState } from 'react'
import { fetchEvents } from './eventsApi'

// Indicador discreto da Home: recompensas de evento prontas + recompensa diária liberada e não resgatada.
export default function useEventsBadge() {
  const [n, setN] = useState(0)
  useEffect(() => {
    let alive = true
    fetchEvents()
      .then((d) => {
        if (!alive || !d) return
        const s = d.streak
        setN((d.claimable || 0) + (s?.active && s.eligible_today && !s.claimed_today ? 1 : 0))
      })
      .catch(() => {}) // indicador é enfeite: sem rede, simplesmente não aparece
    return () => { alive = false }
  }, [])
  return n
}
