import test from 'node:test'
import assert from 'node:assert/strict'
import { automaticWorldDays, createWorldSimulation } from '../src/features/seasons/utils/worldSimulation.js'

function career() {
  return { career: { id: 'user-a' }, coach: { status: 'employed', club_id: 'club-a' }, season: { id: 'season-a', year: 2026, region: 'BRA', status: 'active' }, world: { today: '2026-01-01', needs_sync: true }, next_event: { kind: 'mine', days_until: 14 }, live_match: null }
}

test('drains partial parallel batches automatically and stops before the user match', async () => {
  const hub = career()
  const trace = []
  let partial = false
  const sim = createWorldSimulation({
    requestId: () => String(trace.length),
    refresh: async () => structuredClone(hub),
    advance: async days => {
      trace.push(days)
      let advanced = days
      if (hub.world.needs_sync) hub.world.needs_sync = false
      else if (!partial) { partial = true; advanced = 2; hub.world.needs_sync = true }
      hub.next_event.days_until -= advanced
      hub.world.today = new Date(Date.parse(hub.world.today) + advanced * 86400000).toISOString().slice(0, 10)
      return { days: advanced, matches: 24, more: hub.world.needs_sync, stopped_for_match: hub.next_event.days_until === 0 }
    },
  })
  for (let i = 0; i < 10 && sim.hasWork(hub); i++) await sim.tick(hub)
  assert.deepEqual(trace, [0, 7, 0, 7, 5])
  assert.equal(hub.world.today, '2026-01-15')
  assert.equal(automaticWorldDays(hub), null)
  assert.equal(await sim.tick(hub), false)
  // Finishing the user's game exposes the next fixture and restarts background work.
  hub.next_event = { kind: 'mine', fixture_id: 2, days_until: 3 }
  await sim.tick(hub)
  assert.equal(trace.at(-1), 3)
})

test('pauses for live matches, user actions and legacy careers; next seasons require an explicit start', async () => {
  const hub = career()
  let calls = 0
  const sim = createWorldSimulation({ advance: async () => { calls++ }, refresh: async () => hub, requestId: () => 'a' })
  await sim.tick(hub, true)
  hub.live_match = { id: 1 }
  await sim.tick(hub)
  assert.equal(automaticWorldDays(hub), null)
  hub.live_match = null
  assert.equal(automaticWorldDays({ ...hub, world: null }), null)
  hub.world.needs_sync = false
  hub.season.status = 'finished'
  hub.world.today = '2026-12-30'
  assert.equal(automaticWorldDays(hub), 7)
  hub.world.today = '2027-01-01'
  assert.equal(automaticWorldDays(hub), null)
  hub.season.region = 'ENG'
  hub.world.today = '2027-07-01'
  assert.equal(automaticWorldDays(hub), null)
  hub.season.status = 'active'
  hub.coach.status = 'unemployed'
  assert.equal(automaticWorldDays(hub), null)
  assert.equal(calls, 0)
})

test('retries an ambiguous write with the same request id, without a second simulation', async () => {
  const hub = career()
  const ids = []
  let attempts = 0
  const sim = createWorldSimulation({
    requestId: () => String(++attempts), refresh: async () => hub,
    advance: async (days, id) => { ids.push(id); if (ids.length === 1) throw new Error('Lost response'); return { matches: 24, more: true } },
  })
  await assert.rejects(sim.tick(hub), /Lost response/)
  await sim.tick(hub)
  assert.deepEqual(ids, ['1', '1'])
  assert.equal(attempts, 1)
})

test('retries a failed hub read without repeating a successful advance', async () => {
  const hub = career()
  let writes = 0, reads = 0
  const sim = createWorldSimulation({ requestId: () => 'a', advance: async () => { writes++; return { matches: 24, more: true } }, refresh: async () => ++reads === 1 ? null : hub })
  await assert.rejects(sim.tick(hub), /consultar/)
  await sim.tick(hub)
  assert.equal(writes, 1)
  assert.equal(reads, 2)
})

test('serializes overlapping ticks, stops empty batches and isolates pending requests by owner', async () => {
  const hub = career()
  let release
  let calls = 0
  const sim = createWorldSimulation({ requestId: () => String(calls), advance: async () => { calls++; await new Promise(resolve => { release = resolve }); return { days: 0, matches: 0, more: false } }, refresh: async () => hub })
  const first = sim.tick(hub)
  assert.equal(await sim.tick(hub), false)
  release()
  await first
  assert.equal(await sim.tick(hub), false)
  assert.equal(calls, 1)
  hub.career.id = 'user-b'
  assert.equal(sim.hasWork(hub), true)
  const second = sim.tick(hub)
  release()
  await second
  assert.equal(calls, 2)
})
