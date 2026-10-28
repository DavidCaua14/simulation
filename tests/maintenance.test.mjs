import { test } from 'node:test'
import assert from 'node:assert/strict'
import { isMaintenanceAdmin, parseMaintenance, DEFAULT_MESSAGE } from '../src/features/maintenance/policy.js'

test('only the designated session email bypasses maintenance', () => {
  assert.equal(isMaintenanceAdmin({ email: 'contatodavidcaua@gmail.com' }), true)
  assert.equal(isMaintenanceAdmin({ email: 'CONTATODAVIDCAUA@GMAIL.COM' }), true)
  for (const user of [null, {}, { email: 'tester@example.com' }, { user_metadata: { email: 'contatodavidcaua@gmail.com' } }]) {
    assert.equal(isMaintenanceAdmin(user), false)
  }
})

test('only an explicit boolean can release maintenance', () => {
  assert.equal(parseMaintenance({ enabled: false }).enabled, false)
  assert.equal(parseMaintenance({ enabled: true }).enabled, true)
  for (const value of [null, {}, { enabled: 'false' }, { enabled: 0 }]) {
    assert.throws(() => parseMaintenance(value))
  }
  assert.equal(parseMaintenance({ enabled: true, message: '' }).message, DEFAULT_MESSAGE)
})
