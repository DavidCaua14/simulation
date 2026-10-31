import test from 'node:test'
import assert from 'node:assert/strict'
import { worldAdvanceDays, createWorldSimulation } from '../src/features/seasons/utils/worldSimulation.js'
const career = () => ({ career: { id: 'user-a' }, coach: { status: 'employed', club_id: 'club-a' }, season: { id: 'season-a', year: 2027, region: 'BRA', status: 'active' }, world: { today: '2027-06-05', needs_sync: false }, next_event: { kind: 'mine', days_until: 3 }, live_match: null })

test('one click continues a partial three-day advance until the next match, then stops', async () => {
  const hub = career(), trace = []
  const sim = createWorldSimulation({ requestId: () => String(trace.length), refresh: async () => structuredClone(hub), advance: async days => {
    trace.push(days)
    const advanced = trace.length === 1 ? 1 : days
    hub.next_event.days_until -= advanced
    hub.world.today = new Date(Date.parse(hub.world.today) + advanced * 86400000).toISOString().slice(0, 10)
    return { days: advanced, matches: 2, more: false, days_remaining: days - advanced }
  } })
  assert.deepEqual(trace, [], 'No background date movement')
  const ready = await sim.prepare(hub)
  assert.deepEqual(trace, [3, 2])
  assert.equal(ready.world.today, '2027-06-08')
  assert.equal(ready.next_event.days_until, 0)
  await sim.prepare(ready)
  assert.deepEqual(trace, [3, 2], 'Never simulate the user match')
})

test('a decision response stops automatic continuation even with a remaining backlog', async () => {
  const hub = career(); let writes = 0
  const sim = createWorldSimulation({ requestId: () => 'decision', advance: async () => {
    writes++; hub.attention = { key: 'offer:1' }
    return { requires_attention: true, more: true, days: 1, matches: 0 }
  }, refresh: async () => hub })
  const result = await sim.prepare(hub)
  assert.equal(writes, 1)
  assert.equal(result.attention.key, 'offer:1')
  await sim.prepare(result)
  assert.equal(writes, 1, 'No advancement until the decision is resolved or explicitly deferred')
})

test('a new controller recovers an ambiguous operation from storage using the original UUID', async () => {
  const values = new Map()
  const storage = { getItem: k => values.get(k), setItem: (k, v) => values.set(k, v), removeItem: k => values.delete(k) }
  const hub = career(), ids = []
  const first = createWorldSimulation({ storage, requestId: () => 'saved-id', refresh: async () => hub, advance: async (days, id) => { ids.push(id); throw new Error('Lost response') } })
  await assert.rejects(first.prepare(hub), /Lost response/)
  const resumed = createWorldSimulation({ storage, requestId: () => 'wrong-new-id', refresh: async () => hub, advance: async (days, id) => { ids.push(id); hub.next_event.days_until = 0; return { days: 3 } } })
  await resumed.prepare(hub)
  assert.deepEqual(ids, ['saved-id', 'saved-id'])
  assert.equal(values.size, 0)
})

test('drains bounded parallel batches, including more=true at match day', async () => {
  const hub = career(), trace = []
  hub.world.needs_sync = true
  const sim = createWorldSimulation({ requestId: () => String(trace.length), refresh: async () => structuredClone(hub), advance: async days => {
    trace.push(days)
    hub.next_event.days_until -= days
    hub.world.needs_sync = trace.length === 2
    return { days, matches: 24, more: hub.world.needs_sync }
  } })
  await sim.prepare(hub)
  assert.deepEqual(trace, [0, 3, 0])
})

test('a sync-only call right after a match continues to the next match in the same click', async () => {
  const hub = career(), trace = []
  hub.world.needs_sync = true
  const sim = createWorldSimulation({ requestId: () => String(trace.length), refresh: async () => structuredClone(hub), advance: async days => {
    trace.push(days)
    if (days === 0) { hub.world.needs_sync = false; return { days: 0, matches: 0, more: false } }
    hub.next_event.days_until -= days
    return { days, matches: 4, more: false }
  } })
  const ready = await sim.prepare(hub)
  assert.deepEqual(trace, [0, 3])
  assert.equal(ready.next_event.days_until, 0)
})

test('pauses for live matches, legacy careers and the new-season boundary', () => {
  const hub = career()
  assert.equal(worldAdvanceDays({ ...hub, live_match: { id: 1 } }), null)
  assert.equal(worldAdvanceDays({ ...hub, world: null }), null)
  hub.season.status = 'finished'; hub.world.today = '2027-12-30'
  assert.equal(worldAdvanceDays(hub), 7)
  hub.world.today = '2028-01-01'
  assert.equal(worldAdvanceDays(hub), null)
  hub.season.region = 'ENG'; hub.world.today = '2028-07-01'
  assert.equal(worldAdvanceDays(hub), null)
  hub.season.status = 'active'; hub.coach.status = 'unemployed'
  assert.equal(worldAdvanceDays(hub), null)
})

test('retry after an ambiguous write uses the same UUID', async () => {
  const hub = career(), ids = []
  let nextId = 0
  const sim = createWorldSimulation({ requestId: () => String(++nextId), refresh: async () => hub, advance: async (days, id) => {
    ids.push(id)
    if (ids.length === 1) throw new Error('Lost response')
    hub.next_event.days_until = 0
    return { days, matches: 2, more: false }
  } })
  await assert.rejects(sim.prepare(hub), /Lost response/)
  await sim.prepare(hub)
  assert.deepEqual(ids, ['1', '1'])
})

test('a failed refresh retries the read and never repeats a successful advance', async () => {
  const hub = career(); let writes = 0, reads = 0
  const sim = createWorldSimulation({ requestId: () => 'a', advance: async () => { writes++; hub.next_event.days_until = 0; return { days: 3 } }, refresh: async () => ++reads === 1 ? null : hub })
  await assert.rejects(sim.prepare(hub), /consultar/)
  await sim.prepare(hub)
  assert.equal(writes, 1); assert.equal(reads, 2)
})

test('double clicks share a single preparation; empty batches report a recoverable error', async () => {
  const hub = career(); let release, writes = 0
  const sim = createWorldSimulation({ requestId: () => 'a', advance: async () => { writes++; await new Promise(resolve => { release = resolve }); return { days: 0, matches: 0, more: false } }, refresh: async () => hub })
  const first = sim.prepare(hub), second = sim.prepare(hub)
  assert.equal(first, second)
  release()
  await assert.rejects(first, /calendário não avançou/)
  assert.equal(writes, 1)
})

test('owner changes discard pending requests; unmount stops the continuation', async () => {
  const hub = career(), ids = []; let count = 0
  const sim = createWorldSimulation({ requestId: () => String(++count), advance: async (days, id) => { ids.push(id); throw new Error('Offline') }, refresh: async () => hub })
  await assert.rejects(sim.prepare(hub))
  hub.career.id = 'user-b'
  await assert.rejects(sim.prepare(hub))
  assert.deepEqual(ids, ['1', '2'])
  assert.equal(await sim.prepare(hub, { isActive: () => false }), null)
})

test('reads only the light hub between batches and reloads everything once at the end', async () => {
  const hub = career(), trace = []; let peeks = 0, refreshes = 0
  hub.next_event.days_until = 5
  const sim = createWorldSimulation({ requestId: () => String(trace.length),
    peek: async () => { peeks++; return structuredClone(hub) },
    refresh: async () => { refreshes++; return structuredClone(hub) },
    advance: async days => {
      trace.push(days)
      const more = trace.length === 1
      hub.next_event.days_until -= days
      return { days, matches: 24, more }
    } })
  const ready = await sim.prepare(hub)
  assert.deepEqual(trace, [5, 0])
  assert.equal(peeks, 1, 'partial batches continue without re-reading the hub')
  assert.equal(refreshes, 1)
  assert.equal(ready.next_event.days_until, 0)
})

test('transient timeouts retry the same request id before failing', async () => {
  const hub = career(), ids = []
  const sim = createWorldSimulation({ requestId: () => 'same', retryDelay: 1, refresh: async () => hub, advance: async (days, id) => {
    ids.push(id)
    if (ids.length < 3) throw new Error('canceling statement due to statement timeout')
    hub.next_event.days_until = 0
    return { days, matches: 1, more: false }
  } })
  await sim.prepare(hub)
  assert.deepEqual(ids, ['same', 'same', 'same'])
})

test('a stale browser tab refreshes once and stops without a second advance', async () => {
  const hub = { ...career(), runtime_version: 3 }; const calls = []
  const sim = createWorldSimulation({ requestId: () => 'tab-b', refresh: async () => ({ ...hub, runtime_version: 4 }), advance: async (days, id, version) => {
    calls.push({ days, id, version }); return { requires_refresh: true, state_version: 4, days: 0, matches: 0 }
  } })
  const result = await sim.prepare(hub)
  assert.equal(calls.length, 1)
  assert.equal(calls[0].version, 3)
  assert.equal(result.runtime_version, 4)
})

test('a partial batch carries the returned version into its continuation', async () => {
  const hub = { ...career(), runtime_version: 3 }; const versions = []
  const sim = createWorldSimulation({ requestId: () => String(versions.length), refresh: async () => ({ ...hub, next_event: { kind: 'mine', days_until: 0 } }), advance: async (days, id, version) => {
    versions.push(version); return { more: versions.length === 1, state_version: version + 1, matches: 1 }
  } })
  await sim.prepare(hub)
  assert.deepEqual(versions, [3, 4])
})


test('an ambiguous request created on the old backend uses the migration guard after upgrade', async () => {
  const values = new Map([['career-advance:user-a', JSON.stringify({ id: 'legacy-request', days: 3, completed: false })]])
  const storage = { getItem: k => values.get(k), setItem: (k, v) => values.set(k, v), removeItem: k => values.delete(k) }
  const hub = { ...career(), runtime_version: 0 }; const versions = []
  const sim = createWorldSimulation({ storage, requestId: () => 'unused', refresh: async () => hub, advance: async (days, id, version) => {
    assert.equal(id, 'legacy-request'); versions.push(version); return { requires_refresh: true, days: 0, matches: 0 }
  } })
  await sim.prepare(hub)
  assert.deepEqual(versions, [-1], 'A legacy UUID with no receipt must not become a fresh unguarded write')
})
