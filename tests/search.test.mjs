import test from 'node:test'
import assert from 'node:assert/strict'
import { compare, searcher } from '../src/lib/search.js'
import { monthOf } from '../src/utils/format.js'
import { payState } from '../src/utils/payState.js'

const found = (q, ...fields) => searcher(q)(...fields)

test('search: any order, capitals, accents, spaces', () => {
  for (const q of ['', '  ', 'sarah', 'NAKATO sarah', 'nakato  sarah ', 'sara room 3', 'kira']) assert.ok(found(q, 'Sarah Nakato', 'Room 3 · Kira Rentals'), q)
  assert.ok(found('jose', 'José'))
  assert.ok(!found('john', 'Sarah Nakato', 'Room 3'))
  assert.ok(!found('sarah room 4', 'Sarah Nakato', 'Room 3'))
  assert.ok(found('x', null, undefined, ['a', ['x']]))
})

test('search: a phone number, however it is typed', () => {
  for (const saved of ['+256772123456', '0772123456', '0772 123 456', '256772123456'])
    for (const q of ['0772', '0772 123', '772123', '+256 772 123', '256772123456', '0772123456', '123456', '00256772']) assert.ok(found(q, 'Sarah', saved), `${q} in ${saved}`)
  assert.ok(!found('0773', 'Sarah', '+256772123456'))
  assert.ok(found('+254 712', 'Kenyan', '+254712345678'))
})

test('search: a small number finds that room, not every phone number', () => {
  assert.ok(found('room 1', 'Sarah', 'Room 1', '+256772123456'))
  assert.ok(found('room 1', 'Sarah', 'Room 12'))
  assert.ok(!found('room 1', 'Sarah', 'Room 5', '+256772123456'))
  assert.ok(!found('room 2', 'Sarah', '+256772123456', 'Room 1'))
})

test('sorting: numbers, natural order, empty values always last', () => {
  const sorted = (list, dir) => [...list].sort((a, b) => compare(a, b, dir))
  assert.deepEqual(sorted([30, null, 2, 10], 1), [2, 10, 30, null])
  assert.deepEqual(sorted([30, null, 2, 10], -1), [30, 10, 2, null])
  assert.deepEqual(sorted([0, -5, 3], 1), [-5, 0, 3])
  assert.deepEqual(sorted(['Room 10', 'room 2', ''], 1), ['room 2', 'Room 10', ''])
})

test('a payment just after midnight belongs to its local month', () => {
  const midnight = new Date(2026, 10, 1, 0, 30)
  assert.equal(monthOf(midnight.toISOString()), '2026-11')
  assert.equal(monthOf(null), '')
})

test('"Overdue" is an overdue month or paid time that has run out, never a paid tenant', () => {
  const t = (leaseEnd) => ({ propertyId: 'p', leaseEnd })
  const paid = { status: 'paid', amount: 100, amountPaid: 100, balance: 0 }
  const owes = (status) => ({ status, amount: 100, amountPaid: 0, balance: 100 })
  assert.equal(payState(t('2026-12-30'), [paid], 100, '2026-12-01').late, false)
  assert.equal(payState(t('2026-11-20'), [paid], 100, '2026-12-01').late, true)
  assert.equal(payState(t('2026-12-30'), [paid, owes('overdue')], 100, '2026-12-01').late, true)
  assert.equal(payState(t('2026-12-30'), [paid, owes('pending')], 100, '2026-12-01').late, false)
  assert.equal(payState(t(null), [], 100, '2026-12-01').late, false)
})
