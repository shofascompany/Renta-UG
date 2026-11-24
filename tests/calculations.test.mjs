// Checks the money and time calculations the app shows (they must match the database rules):
//   rent month = 30 days · part payments buy days · paid / part paid / not paid · receipt numbers
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { coverage, daysFor, addMonths, isoDay, nextCycle, rentCycle } from '../src/utils/rentCycle.js'
import { payState } from '../src/utils/payState.js'
import { timeLeft } from '../src/utils/format.js'
import { receiptNumber, receiptFileName } from '../src/lib/receiptImage.js'

const charge = (o = {}) => ({ amount: 300000, amountPaid: 0, creditedDays: 0, monthCredited: false, status: 'pending', dueDate: '2026-12-01', ...o, balance: (o.amount ?? 300000) - (o.amountPaid ?? 0) })

test('a rent month is always 30 days', () => {
  assert.equal(isoDay(addMonths(new Date('2026-01-31T00:00:00'), 1)), '2026-03-02') // not 28 Feb
  assert.equal(isoDay(addMonths(new Date('2026-11-20T00:00:00'), 1)), '2026-12-20')
  assert.equal(isoDay(addMonths(new Date('2026-11-20T00:00:00'), 12)), '2027-11-15') // 360 days
  assert.equal(nextCycle({ leaseEnd: '2026-11-20' }, '2026-11-18').end, '2026-12-20')
  assert.equal(rentCycle({ leaseEnd: '2026-12-20' }).fullDays, 30)
})

test('part payments buy days in proportion (rent ÷ 30)', () => {
  assert.equal(daysFor(150000, 300000), 15)
  assert.equal(daysFor(100000, 300000), 10)
  assert.equal(daysFor(9999, 300000), 0) // rounded down
  assert.equal(daysFor(300000, 300000), 30)
})

test('coverage: half, then the rest, adds up to exactly 30 days', () => {
  const half = coverage({ tenant: { leaseEnd: '2026-11-20' }, dues: [charge()], rent: 300000, amount: 150000, payDay: '2026-11-18' })
  assert.equal(half.days, 15)
  assert.equal(half.end, '2026-12-05')
  const rest = coverage({ tenant: { leaseEnd: '2026-12-05' }, dues: [charge({ amountPaid: 150000, creditedDays: 15 })], rent: 300000, amount: 150000, payDay: '2026-11-25' })
  assert.equal(rest.days, 15)
  assert.equal(rest.end, '2026-12-20') // 20 Nov + 30 days
})

test('coverage: first payment, months ahead, debt days, money already waiting', () => {
  const first = coverage({ tenant: { leaseEnd: null }, dues: [], rent: 300000, amount: 300000, payDay: '2026-11-24' })
  assert.equal(first.firstPayment, true)
  assert.equal(first.end, '2026-12-24')
  const ahead = coverage({ tenant: { leaseEnd: '2026-12-01' }, dues: [], rent: 300000, amount: 900000, payDay: '2026-11-24' })
  assert.equal(ahead.days, 90)
  const late = coverage({ tenant: { leaseEnd: '2026-11-01' }, dues: [charge()], rent: 300000, amount: 60000, payDay: '2026-11-24' })
  assert.equal(late.debtDays, 23)
  assert.equal(late.days, 6)
  assert.equal(late.endsBeforeToday, true)
  const waiting = coverage({ tenant: { leaseEnd: '2026-12-01' }, dues: [], rent: 300000, amount: 150000, before: 300000, payDay: '2026-11-24' })
  assert.equal(waiting.from, '2026-12-31') // the waiting month is counted first
  assert.equal(waiting.days, 15)
})

test('coverage: a month already credited (old 60% rule) gives no extra days', () => {
  const c = coverage({ tenant: { leaseEnd: '2026-12-20' }, dues: [charge({ amountPaid: 200000, monthCredited: true })], rent: 300000, amount: 100000, payDay: '2026-11-24' })
  assert.equal(c.days, 0)
})

test('paid / part paid / not paid', () => {
  const t = (o) => ({ propertyId: 'p1', leaseEnd: null, ...o })
  assert.equal(payState(t(), [], 300000, '2026-11-24').key, 'unpaid') // never paid, nothing charged
  assert.equal(payState(t(), [], 300000, '2026-11-24').owed, 300000)
  assert.equal(payState(t({ leaseEnd: '2026-12-10' }), [charge({ status: 'paid', amountPaid: 300000 })], 300000, '2026-11-24').key, 'paid')
  assert.equal(payState(t({ leaseEnd: '2026-11-10' }), [charge({ status: 'paid', amountPaid: 300000 })], 300000, '2026-11-24').key, 'unpaid') // time ended
  const part = payState(t({ leaseEnd: '2026-12-05' }), [charge({ amountPaid: 150000 })], 300000, '2026-11-24')
  assert.equal(part.key, 'part')
  assert.equal(part.owed, 150000)
  assert.equal(payState(t({ leaseEnd: '2026-12-05' }), [charge({ status: 'overdue' })], 300000, '2026-11-24').label, 'Not paid')
  assert.equal(payState({ propertyId: null }, [], 0).key, 'left')
})

test('time left uses 30-day months', () => {
  assert.equal(timeLeft(29), '29 days left')
  assert.equal(timeLeft(30), '1 month left')
  assert.equal(timeLeft(45), '1 month, 15 days left')
  assert.equal(timeLeft(-3), '3 debt days')
})

test('receipt number and file name', () => {
  const id = '1a2b3c4d-0000-4000-8000-000000000000'
  assert.match(receiptNumber(id), /^\d{8}$/)
  assert.equal(receiptNumber(id), receiptNumber(id)) // always the same for the same payment
  assert.equal(receiptFileName({ id, tenantName: 'john  kamera' }), `John Kamera Receipt No. ${receiptNumber(id)}.png`)
  assert.equal(receiptFileName({ id, tenantName: 'a/b:c' }), `A B C Receipt No. ${receiptNumber(id)}.png`)
})
