import { useEffect, useState } from 'react'
import { fetchEvents } from './eventsApi'

// Home: quantas recompensas estão prontas (eventos concluídos + sequência diária liberada) e o evento especial
// que merece destaque (o ativo que termina primeiro, senão o próximo a começar). Só dados reais do servidor.
export default function useEventsBadge() {
  const [state, setState] = useState({ count: 0, feature: null })
  useEffect(() => {
    let alive = true
    fetchEvents()
      .then((d) => {
        if (!alive || !d) return
        const s = d.streak
        const count = (d.claimable || 0) + (s?.active && s.eligible_today && !s.claimed_today ? 1 : 0)
        const special = (list) => list.filter((e) => e.category === 'themed' || e.category === 'collection')
        const active = special(d.active || []).sort((a, b) => new Date(a.ends_at) - new Date(b.ends_at))[0]
        const next = special(d.upcoming || [])[0]
        setState({ count, feature: active ? { ...active, live: true } : next ? { ...next, live: false } : null })
      })
      .catch(() => {}) // destaque é enfeite: sem rede, simplesmente não aparece
    return () => { alive = false }
  }, [])
  return state
}
