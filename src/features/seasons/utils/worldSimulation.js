// The server owns dates, fixtures, results and the stop before the coach's match.
// This coordinator only drains bounded batches; a retry reuses the same request.
export function automaticWorldDays(hub) {
  if (!hub?.world || hub.live_match) return null
  if (hub.world.needs_sync) return 0
  if (hub.season.status === 'finished') {
    const nextStart = `${hub.season.year + 1}-${hub.season.region === 'ENG' ? '07' : '01'}-01`
    return hub.world.today < nextStart ? 7 : null
  }
  if (hub.coach.status !== 'employed') return null
  if (hub.next_event?.kind === 'mine' && hub.next_event.days_until <= 0) return null
  return Math.min(7, Math.max(1, hub.next_event?.days_until || 7))
}

export function createWorldSimulation({ advance, refresh, requestId }) {
  let pending = null
  let owner = null
  let running = false
  let stoppedAt = null
  const key = hub => JSON.stringify([hub?.career.id, hub?.season.id, hub?.season.status, hub?.coach.club_id, hub?.coach.status, hub?.world.today, hub?.world.needs_sync, hub?.world.due_matches, hub?.next_event])
  const hasWork = hub => Boolean(hub?.world && !hub.live_match && (owner !== hub.career.id || stoppedAt !== key(hub)) && (pending || automaticWorldDays(hub) !== null))
  return {
    hasWork,
    async tick(hub, paused = false) {
      if (running || paused || !hub?.world || hub.live_match) return false
      if (owner !== hub.career.id) {
        owner = hub.career.id
        pending = null
        stoppedAt = null
      }
      const days = automaticWorldDays(hub)
      if (!hasWork(hub)) return false
      running = true
      try {
        pending ||= { days, id: requestId(), completed: false }
        if (!pending.completed) {
          pending.result = await advance(pending.days, pending.id)
          pending.completed = true
        }
        // A failed refresh must never cause another date advance. Retry the read.
        const next = await refresh({ silent: true })
        if (!next) throw new Error('Não foi possível consultar a carreira atualizada.')
        const result = pending.result
        if (result && !result.more && !result.matches && !result.days && key(hub) === key(next)) stoppedAt = key(next)
        pending = null
        return true
      } finally {
        running = false
      }
    },
  }
}
