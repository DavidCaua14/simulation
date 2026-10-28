import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createSessionFetch, onSessionExpired, resetSessionRecovery } from '../src/lib/sessionRecovery.js'

const base = 'https://example.supabase.co'
test('invalid JWT ends session once and never retries a match mutation', async () => {
  resetSessionRecovery()
  let expired = 0
  let calls = 0
  const off = onSessionExpired(() => expired++)
  const fetcher = createSessionFetch(async (url, init) => {
    calls++
    assert.equal(init.method, 'POST')
    return new Response(JSON.stringify({ code: 'PGRST301', message: 'JWT expired' }), { status: 401 })
  }, base)
  const response = await fetcher(base + '/rest/v1/rpc/mgr_match_step', { method: 'POST' })
  assert.equal(expired, 1)
  assert.equal(calls, 1)
  assert.equal((await response.json()).code, 'PGRST301')
  await fetcher(base + '/rest/v1/rpc/mgr_match_step', { method: 'POST' })
  assert.equal(expired, 1)
  off()
})

test('network/server/permissions/maintenance errors do not end a session', async () => {
  resetSessionRecovery()
  let expired = 0
  const off = onSessionExpired(() => expired++)
  for (const [status, code] of [[503, 'PT503'], [403, '42501'], [500, 'XX000'], [401, 'OTHER']]) {
    await createSessionFetch(async () => new Response(JSON.stringify({ code }), { status }), base)(base + '/rest/v1/careers')
  }
  await assert.rejects(createSessionFetch(async () => { throw new TypeError('offline') }, base)(base + '/rest/v1/careers'))
  assert.equal(expired, 0)
  off()
})

test('revoked refresh token ends session; successful refresh does not', async () => {
  resetSessionRecovery()
  let expired = 0
  const off = onSessionExpired(() => expired++)
  const url = base + '/auth/v1/token?grant_type=refresh_token'
  await createSessionFetch(async () => new Response('{}', { status: 200 }), base)(url)
  assert.equal(expired, 0)
  await createSessionFetch(async () => new Response('{"code":"refresh_token_not_found"}', { status: 400 }), base)(url)
  assert.equal(expired, 1)
  off()
})


test('a delayed response from an older token does not log out the new session', async () => {
  resetSessionRecovery()
  let expired = 0
  const off = onSessionExpired(() => expired++)
  const fetcher = createSessionFetch(async () => new Response('{"code":"PGRST301"}', { status: 401 }), base, () => 'new-token')
  await fetcher(base + '/rest/v1/careers', { headers: { Authorization: 'Bearer old-token' } })
  assert.equal(expired, 0)
  off()
})
