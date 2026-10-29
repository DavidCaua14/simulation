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
