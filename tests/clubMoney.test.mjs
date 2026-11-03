import test from 'node:test'
import assert from 'node:assert/strict'
import { clubMoney, toClubReais, fromClubReais, personalCoins } from '../src/features/seasons/utils/clubMoney.js'

test('existing contracts use the real club denomination without changing their stored value', () => {
  assert.match(clubMoney(50), /50\.000/)
  assert.match(clubMoney(80), /80\.000/)
  assert.match(clubMoney(100), /100\.000/)
  assert.match(clubMoney(3216), /3\.216\.000/)
  assert.match(clubMoney(-270), /270\.000/)
  assert.equal(toClubReais(3216), 3216000)
  assert.equal(fromClubReais('3216000'), 3216)
})
test('empty optional amounts remain editable and personal coins are not inflated', () => {
  assert.equal(toClubReais(''), '')
  assert.equal(fromClubReais(''), '')
  assert.equal(fromClubReais('0'), 0)
  assert.equal(personalCoins(1250), '1.250')
  assert.match(clubMoney(1), /1\.000/)
})
