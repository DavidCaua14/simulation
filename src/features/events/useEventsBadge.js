import { useEffect, useState } from 'react'
import { fetchEvents } from './eventsApi'

// Home uses the same overview as the claim screen, including earlier periods.
export default function useEventsBadge() {
  const [state, setState] = useState({ count: 0, feature: null })
  useEffect(() => {
    let alive = true
    let request = 0
    let timer
    const load = () => {
      const current = ++request
      return fetchEvents().then((d) => {
        if (!alive || current !== request || !d) return
        const s = d.streak
        const count = (Number(d.claimable) || 0) + (s?.active && s.eligible_today && !s.claimed_today ? 1 : 0)
        const special = (list) => list.filter((e) => e.category === 'themed' || e.category === 'collection')
        const active = special(d.active || []).sort((a, b) => new Date(a.ends_at) - new Date(b.ends_at))[0]
        const next = special(d.upcoming || [])[0]
        setState({ count, feature: active ? { ...active, live: true } : next ? { ...next, live: false } : null })
        // Refresh at the next renewal/expiry, without repeatedly polling the database.
        const cards = [...(d.active || []), ...(d.ended || [])]
        const edges = [s?.resets_at, ...(d.upcoming || []).map((e) => e.starts_at),
          ...cards.flatMap((e) => [e.period_end, e.ends_at, e.completion?.claim_until]),
          ...(d.pending_rewards || []).map((r) => r.claim_until)]
          .map((t) => new Date(t).getTime()).filter((t) => t > Date.now())
        clearTimeout(timer)
        if (edges.length) timer = setTimeout(load, Math.min(Math.min(...edges) - Date.now() + 100, 86400000))
      }).catch(() => {})
    }
    const onVisible = () => { if (!document.hidden) load() }
    load()
    window.addEventListener('focus', load)
    window.addEventListener('game:events', load)
    document.addEventListener('visibilitychange', onVisible)
    return () => {
      alive = false
      clearTimeout(timer)
      window.removeEventListener('focus', load)
      window.removeEventListener('game:events', load)
      document.removeEventListener('visibilitychange', onVisible)
    }
  }, [])
  return state
}
