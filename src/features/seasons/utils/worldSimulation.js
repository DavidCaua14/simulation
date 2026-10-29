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

// Falhas passageiras (rede, tempo limite do banco): repete a MESMA requisição (mesmo UUID, o servidor não duplica).
const TRANSIENT = /timeout|timed out|failed to fetch|network|fetch failed|load failed|503|502|504|tempo limite/i
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

// peek: leitura leve do hub entre os lotes (sem recarregar todos os jogos); o refresh completo fica para o fim.
export function createWorldSimulation({ advance, refresh, peek = refresh, requestId, retries = 2, retryDelay = 800 }) {
  let pending = null
  let owner = null
  let preparing = null
  async function send(p) {
    for (let attempt = 0; ; attempt++) {
      try {
        return await advance(p.days, p.id)
      } catch (e) {
        if (attempt >= retries || !TRANSIENT.test(e?.message || '')) throw e
        await wait(retryDelay * (attempt + 1))
      }
    }
  }
  async function step(hub, known) {
    if (owner !== hub.career.id) { owner = hub.career.id; pending = null }
    const days = known ?? worldAdvanceDays(hub)
    if (!pending && days === null) return null
    pending ||= { days, id: requestId(), completed: false }
    if (!pending.completed) {
      pending.result = await send(pending)
      pending.completed = true
    }
    const result = pending.result
    // Lote parcial: o servidor ainda tem partidas do dia para processar. Continua sem reler o hub.
    if (result?.more) {
      pending = null
      return { hub, next: 0, result }
    }
    // An ambiguous write retries its UUID; a failed read retries only the read.
    const next = await peek({ silent: true })
    if (!next) throw new Error('Não foi possível consultar a carreira atualizada. Toque novamente para continuar.')
    const asked = pending.days
    pending = null
    // Pedido de 0 dias só sincroniza o mundo (ex.: logo após a sua partida): sem jogos nem dias é normal, segue o avanço.
    if (asked > 0 && !result?.matches && !result?.days && worldAdvanceDays(next) !== null) {
      throw new Error('O calendário não avançou. Toque novamente para continuar a preparação.')
    }
    return { hub: next, next: undefined, result }
  }
  return {
    prepare(hub, { isActive = () => true, onProgress = () => {} } = {}) {
      if (preparing) return preparing
      preparing = (async () => {
        let current = hub
        let known
        let moved = false
        try {
          for (let batch = 0; batch < 240 && isActive(); batch++) {
            const out = await step(current, known)
            if (!out) return current
            moved = true
            current = out.hub
            known = out.next
            onProgress(current, out.result)
            if (known === undefined && (current.live_match || worldAdvanceDays(current) === null)) return current
          }
          if (!isActive()) return null
          throw new Error('A preparação foi pausada. Toque novamente para continuar de onde parou.')
        } finally {
          // Recarrega jogos e tabelas uma única vez, ao final (ou ao parar no meio), se o calendário andou.
          if (moved && peek !== refresh && isActive()) {
            await refresh({ silent: true }).catch(() => null)
          }
        }
      })().finally(() => { preparing = null })
      return preparing
    },
  }
}
