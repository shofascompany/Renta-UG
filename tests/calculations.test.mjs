// Checks the money and time calculations the app shows (they must match the database rules):
//   rent month = 30 days · part payments buy days · paid / part paid / not paid · receipt numbers
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { coverage, coverageParts, debtSplit, durationText, daysFor, addMonths, isoDay, nextCycle, rentCycle } from '../src/utils/rentCycle.js'
import { paymentOf, cashRecordOf } from '../src/utils/paymentGroups.js'
import { payState } from '../src/utils/payState.js'
import { timeLeft } from '../src/utils/format.js'
import { daysLeftAt, rentEnds, subscriptionEnds, ugandaDay, moveDay, DAY_MS } from '../src/utils/exactTime.js'
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

test('debt days are paid first, only the rest is added (database/63)', () => {
  const t = { leaseEnd: '2026-11-15' }
  // 9 debt days on 24 Nov, one month paid: 9 days pay the debt, 21 are added
  const one = coverage({ tenant: t, dues: [], rent: 300000, amount: 300000, payDay: '2026-11-24' })
  assert.equal(one.debtDays, 9)
  assert.deepEqual(debtSplit(one, t), { debtPaid: 9, added: 21, behind: 0, from: '2026-11-15', to: '2026-11-24' })
  // less than the debt: all of it pays debt days, still 4 behind
  const some = coverage({ tenant: t, dues: [], rent: 300000, amount: 50000, payDay: '2026-11-24' })
  assert.deepEqual(debtSplit(some, t), { debtPaid: 5, added: 0, behind: 4, from: '2026-11-15', to: '2026-11-20' })
  // money already waiting pays the debt: all this payment buys is added
  const after = coverage({ tenant: t, dues: [], rent: 300000, amount: 300000, before: 300000, payDay: '2026-11-24' })
  assert.deepEqual(debtSplit(after, t), { debtPaid: 0, added: 30, behind: 0, from: null, to: null })
  // no debt, and a first payment: everything is added
  const fine = coverage({ tenant: { leaseEnd: '2026-12-15' }, dues: [], rent: 300000, amount: 300000, payDay: '2026-11-24' })
  assert.deepEqual(debtSplit(fine, { leaseEnd: '2026-12-15' }), { debtPaid: 0, added: 30, behind: 0, from: null, to: null })
  assert.equal(debtSplit(coverage({ tenant: { leaseEnd: null }, rent: 300000, amount: 300000, payDay: '2026-11-24' }), { leaseEnd: null }).added, 30)
  // whatever is paid, the days always add up
  for (let amount = 10000; amount <= 900000; amount += 10000) {
    const c = coverage({ tenant: t, dues: [], rent: 300000, amount, payDay: '2026-11-24' })
    const s = debtSplit(c, t)
    assert.equal(s.debtPaid + s.added, c.days, `${amount}`)
    assert.equal(s.debtPaid + s.behind, c.debtDays, `${amount}`)
  }
})

test('one payment = every receipt saved together (the rule reversing uses)', () => {
  const at = '2026-11-20T12:00:00+00:00'
  const made = '2026-11-20T15:31:02.123456+00:00'
  const r = (id, paymentId, amount, o = {}) => ({ id, paymentId, tenantId: 't', landlordId: 'l', amount, method: 'Cash', receivedAt: at, createdAt: made, ...o })
  const receipts = [
    r('r1', 'dec', 300000),
    r('r2', 'nov', 300000),
    r('r3', 'jan', 150000, { reference: 'X1' }),
    r('r4', 'jan', 150000, { createdAt: '2026-11-21T08:00:00+00:00' }), // another payment on the same day
    r('r5', 'nov', 300000, { tenantId: 'u' }), // another tenant
  ]
  const period = { nov: '2026-11', dec: '2026-12', jan: '2027-01' }
  const p = paymentOf(receipts, 'r1', (id) => period[id])
  assert.deepEqual(p.receipts.map((x) => x.id), ['r2', 'r1', 'r3']) // earliest month first
  assert.equal(p.total, 750000)
  assert.equal(p.id, 'r2')
  assert.equal(p.reference, 'X1')
  assert.equal(paymentOf(receipts, 'r4').total, 150000)
  assert.equal(paymentOf(receipts, 'nope'), null)
  // Its cash record: confirmed in that same moment (the same instant, however it is written)
  const cash = [{ id: 'c0', tenantId: 't', reviewedAt: '2026-11-19T10:00:00+00:00' }, { id: 'c1', tenantId: 't', reviewedAt: '2026-11-20T18:31:02.123+03:00' }]
  assert.equal(cashRecordOf(p, cash)?.id, 'c1')
  assert.equal(cashRecordOf(paymentOf(receipts, 'r4'), cash), null)
})

test('a payment, piece by piece, with its dates', () => {
  const row = (p) => [p.from, p.to, p.days, p.kind]
  // more than a month: whole months, then the days the rest buys
  assert.deepEqual(coverageParts({ tenant: { leaseEnd: '2026-11-25' }, rent: 300000, amount: 750000, payDay: '2026-11-20' }).map(row), [
    ['2026-11-25', '2026-12-25', 30, 'month'],
    ['2026-12-25', '2027-01-24', 30, 'month'],
    ['2027-01-24', '2027-02-08', 15, 'part'],
  ])
  assert.equal(durationText(75), '2 months and 15 days')
  assert.equal(durationText(30), '1 month')
  assert.equal(durationText(61), '2 months and 1 day')
  assert.equal(durationText(1), '1 day')
  assert.equal(durationText(0), '0 days')
  // an unpaid month first: only what is left of it (it had given 10 days), then a whole month
  const half = [{ ...charge({ amountPaid: 100000, creditedDays: 10 }), period: '2026-11' }]
  assert.deepEqual(coverageParts({ tenant: { leaseEnd: '2026-11-10' }, dues: half, rent: 300000, amount: 500000, payDay: '2026-11-20' }).map((p) => [...row(p), p.whole ?? null]), [
    ['2026-11-10', '2026-11-30', 20, 'due', true],
    ['2026-11-30', '2026-12-30', 30, 'month', null],
  ])
  // money already waiting comes first: this payment completes that month, then buys 15 days
  assert.deepEqual(coverageParts({ tenant: { leaseEnd: '2026-11-25' }, rent: 300000, amount: 300000, before: 150000, payDay: '2026-11-20' }).map((p) => [...row(p), p.cut]), [
    ['2026-12-10', '2026-12-25', 15, 'month', true],
    ['2026-12-25', '2027-01-09', 15, 'part', false],
  ])
  // time that had already run out is marked
  assert.deepEqual(coverageParts({ tenant: { leaseEnd: '2026-09-16' }, rent: 300000, amount: 900000, payDay: '2026-11-25' }).map((p) => p.passed), [true, true, false])
  // a first payment starts on the pay day
  assert.deepEqual(coverageParts({ tenant: { leaseEnd: null }, rent: 300000, amount: 450000, payDay: '2026-11-27' }).map(row), [
    ['2026-11-27', '2026-12-27', 30, 'month'],
    ['2026-12-27', '2027-01-11', 15, 'part'],
  ])
})

test('the pieces always add up to exactly what coverage() says', () => {
  let n = 0
  const dueSets = [[], [charge()], [charge({ amountPaid: 150000, creditedDays: 15 })], [charge({ amountPaid: 200000, monthCredited: true })], [charge({ amountPaid: 50000, creditedDays: 5 }), charge({ dueDate: '2027-01-01' })]]
  for (const leaseEnd of [null, '2026-11-25', '2026-09-01'])
    for (const dues of dueSets)
      for (const amount of [0, 5000, 100000, 299999, 300000, 450000, 750000, 1000000])
        for (const before of [0, 150000, 300000]) {
          const a = { tenant: { leaseEnd }, dues, rent: 300000, amount, before, payDay: '2026-11-25' }
          const c = coverage(a)
          const parts = coverageParts(a)
          assert.equal(parts.reduce((s, p) => s + p.days, 0), c.days, JSON.stringify(a))
          if (parts.length) {
            assert.equal(parts[0].from, c.from, JSON.stringify(a))
            assert.equal(parts.at(-1).to, c.end, JSON.stringify(a))
            parts.forEach((p, i) => i && assert.equal(p.from, parts[i - 1].to))
          } else assert.equal(c.days, 0)
          n++
        }
  assert.ok(n > 300)
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

test('exact time: a day is 24 complete hours', () => {
  const t = { propertyId: 'p1', leaseEnd: '2026-12-25', leaseClock: '14:30:15' }
  const start = Date.parse('2026-11-25T14:30:15+03:00')
  assert.equal(rentEnds(t), start + 30 * DAY_MS)
  const left = (ms) => daysLeftAt(rentEnds(t), start + ms)
  assert.equal(left(0), 30)
  assert.equal(left(DAY_MS - 1), 30) // one second short of 24 hours: still 30
  assert.equal(left(DAY_MS), 29)
  assert.equal(left(30 * DAY_MS - 1), 1)
  assert.equal(left(30 * DAY_MS), 0) // ended, to the moment
  assert.equal(left(31 * DAY_MS - 1), 0)
  assert.equal(left(31 * DAY_MS), -1) // one complete debt day
  // the same for paid / not paid and the money
  const paid = [charge({ status: 'paid', amountPaid: 300000 })]
  const at = (ms) => payState(t, paid, 300000, start + ms)
  assert.equal(at(30 * DAY_MS - 1000).key, 'paid')
  assert.equal(at(30 * DAY_MS).key, 'unpaid')
  assert.equal(at(30 * DAY_MS).detail, 'Time has ended')
  assert.equal(at(30 * DAY_MS).owed, 300000)
  assert.equal(at(60 * DAY_MS - 1000).owed, 300000)
  assert.equal(at(60 * DAY_MS).owed, 600000)
  assert.equal(at(32 * DAY_MS).detail, 'Time ended 2 days ago')
  assert.equal(rentCycle(t, null, start + 33 * DAY_MS).debtDays, 3)
  // subscription: confirmed 1 Nov 14:00, 30 days → last whole day 30 Nov → ends 1 Dec 14:00
  assert.equal(subscriptionEnds('2026-11-30', '14:00:00.123'), Date.parse('2026-12-01T14:00:00+03:00'))
  assert.equal(subscriptionEnds('2026-11-30', null), Date.parse('2026-12-01T00:00:00+03:00'))
  assert.equal(ugandaDay(Date.parse('2026-11-30T22:00:00Z')), '2026-12-01')
  assert.equal(moveDay('2026-12-31', 1), '2027-01-01')
  assert.equal(daysLeftAt(rentEnds({}), start), null)
  assert.equal(JSON.stringify(left(30 * DAY_MS)), '0')
})

test('unpaid rent: every month in debt × the rent', () => {
  const owes = (leaseEnd, today, charges = [], rent = 300000) => payState({ propertyId: 'p1', leaseEnd }, charges, rent, today)
  const paidBefore = [charge({ status: 'paid', amountPaid: 300000 })]
  const is = (leaseEnd, today, months) => {
    const s = owes(leaseEnd, today, paidBefore)
    assert.equal(s.owed, months * 300000, `${leaseEnd} → ${today}`)
    assert.equal(s.months.length, months)
    assert.equal(s.how, months ? `${months} month${months === 1 ? '' : 's'} × 300,000` : '')
  }
  is('2026-11-25', '2026-11-25', 0) // the last paid day
  is('2026-11-24', '2026-11-25', 1)
  is('2026-10-26', '2026-11-25', 1) // 30 days
  is('2026-10-25', '2026-11-25', 2) // 31 days
  is('2026-09-30', '2026-11-25', 2)
  is('2026-07-31', '2026-11-25', 4)
  is('2025-11-25', '2026-11-25', 13) // 365 days
  assert.deepEqual(owes('2026-09-30', '2026-11-25', paidBefore).months.map((m) => m.from), ['2026-09-30', '2026-10-30'])

  // Part paid: what is left of that month + the months begun after it
  const half = charge({ amountPaid: 150000, creditedDays: 15, status: 'overdue' })
  const s = owes('2026-09-15', '2026-11-25', [half]) // that month runs to 30 Sep, then 2 more
  assert.equal(s.owed, 150000 + 2 * 300000)
  assert.equal(s.how, '2 months + 150,000')
  assert.equal(s.key, 'part')
  assert.equal(owes('2026-11-20', '2026-11-25', [half]).owed, 150000) // still inside the part-paid month
  assert.equal(owes('2026-11-20', '2026-11-25', [half]).how, 'Rest of 1 month')
  // Never paid: the first month (their rental time starts the day they pay). No rent set: nothing
  assert.equal(owes(null, '2026-11-25').how, '1 month × 300,000')
  assert.equal(owes('2026-07-31', '2026-11-25', paidBefore, 0).owed, 0)
  assert.equal(payState({ propertyId: null, leaseEnd: '2026-07-31' }, [], 300000, '2026-11-25').owed, 0)
})

test('unpaid rent is exactly the money that brings a tenant up to date', () => {
  const today = '2026-11-25'
  let n = 0
  for (let late = 0; late <= 200; late += 3)
    for (const paid of [null, 0, 100000, 150000, 290000]) {
      const rent = 300000
      const dues = paid === null ? [] : [charge({ amountPaid: paid, creditedDays: daysFor(paid, rent) })]
      const end = isoDay(new Date(new Date(`${today}T00:00:00`).getTime() - late * 86400000 + 3600000))
      const tenant = { propertyId: 'p1', leaseEnd: end }
      const { owed, months } = payState(tenant, dues, rent, today)
      if (!owed) continue
      n++
      assert.equal(coverage({ tenant, dues, rent, amount: owed, payDay: today }).endsBeforeToday, false, `${late} days, ${paid}`)
      if (months.length > dues.length) // one month less is not enough
        assert.equal(coverage({ tenant, dues, rent, amount: owed - rent, payDay: today }).endsBeforeToday, true, `${late} days, ${paid}`)
    }
  assert.ok(n > 200)
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
