// Dates and match results remain server-owned. A click prepares the next match;
// partial batches continue here, without depending on a background browser timer.
export function worldAdvanceDays(hub) {
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
  let preparing = null
  async function step(hub) {
    if (owner !== hub.career.id) { owner = hub.career.id; pending = null }
    const days = worldAdvanceDays(hub)
    if (!pending && days === null) return null
    pending ||= { days, id: requestId(), completed: false }
    if (!pending.completed) {
      pending.result = await advance(pending.days, pending.id)
      pending.completed = true
    }
    // An ambiguous write retries its UUID; a failed read retries only the read.
    const next = await refresh({ silent: true })
    if (!next) throw new Error('Não foi possível consultar a carreira atualizada. Toque novamente para continuar.')
    const result = pending.result
    pending = null
    if (!result?.more && !result?.matches && !result?.days && worldAdvanceDays(next) !== null) {
      throw new Error('O calendário não avançou. Toque novamente para continuar a preparação.')
    }
    return next
  }
  return {
    prepare(hub, { isActive = () => true, onProgress = () => {} } = {}) {
      if (preparing) return preparing
      preparing = (async () => {
        let current = hub
        for (let batch = 0; batch < 240 && isActive(); batch++) {
          const next = await step(current)
          if (!next) return current
          current = next
          onProgress(current)
          if (current.live_match || worldAdvanceDays(current) === null) return current
        }
        if (!isActive()) return null
        throw new Error('A preparação foi pausada. Toque novamente para continuar de onde parou.')
      })().finally(() => { preparing = null })
      return preparing
    },
  }
}
