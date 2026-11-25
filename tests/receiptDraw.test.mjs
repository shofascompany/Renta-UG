import test from 'node:test'
import assert from 'node:assert/strict'

// A stand-in canvas that records what is drawn, so the receipt layout can be checked without a browser
function fakeCanvas() {
  const texts = []
  const ctx = new Proxy({}, {
    get: (_, k) => (k === 'measureText' ? (t) => ({ width: String(t).length * 11 }) : k === 'fillText' ? (t) => texts.push(String(t)) : () => {}),
    set: () => true,
  })
  return { width: 0, height: 0, getContext: () => ctx, texts }
}
globalThis.document = { createElement: () => fakeCanvas() }
const { drawReceipt, rentalTime, receiptNumber } = await import('../src/lib/receiptImage.js')

const base = {
  id: 'abc123def456', amount: 500000, method: 'Cash', paidOn: '2026-11-03T09:30:00Z', confirmedOn: '2026-11-03', confirmedBy: 'Landlord', months: ['November 2026'],
  tenantName: 'Sarah Nakato', tenantPhone: '+256772123456', property: 'Room 3 · Kira Rentals', landlordName: 'John Mukasa', details: 'Ref 4455',
}

test('the receipt keeps its original layout: 1600 wide, same facts', () => {
  const c = drawReceipt(base)
  assert.equal(c.width, 1600)
  assert.equal(c.height, 900)
  for (const label of ['Received from', 'Tenant phone', 'Property', 'Paid to (landlord)', 'Rent for', 'Payment method', 'Date paid', 'Confirmed on', 'Confirmed by', 'Details']) {
    assert.ok(c.texts.includes(label), `missing ${label}`)
  }
  assert.ok(c.texts.includes(`Receipt No. ${receiptNumber(base.id)}`))
})

test('without rental-time information "Rent for" is the rent month, as before', () => {
  assert.ok(drawReceipt(base).texts.includes('November 2026'))
})

test('"Rent for" shows when it was paid, how long it lasts and when it ends', () => {
  const c = drawReceipt({ ...base, window: { from: '2026-11-03', to: '2026-12-03', days: 30 } })
  const line = c.texts.find((t) => /^Paid \d/.test(t))
  assert.ok(line, 'no rent-for line')
  assert.match(line, /^Paid 3 Nov 2026 · 1 month · ends 3 Dec 2026$/)
})

test('rental time reads as days or months', () => {
  assert.equal(rentalTime(30), '1 month')
  assert.equal(rentalTime(60), '2 months')
  assert.equal(rentalTime(45), '1 month 15 days')
  assert.equal(rentalTime(12), '12 days')
  assert.equal(rentalTime(1), '1 day')
  assert.equal(rentalTime(0), '—')
})

test('a part-paid month adds the payments table below, as before', () => {
  const c = drawReceipt({
    ...base,
    instalments: { period: 'November 2026', rent: 500000, paid: 300000, balance: 200000, days: 18, current: 'x2',
      rows: [{ id: 'x1', n: 1, at: '2026-11-03T08:00:00Z', method: 'Cash', amount: 100000, days: 6 }, { id: 'x2', n: 2, at: '2026-11-10T08:00:00Z', method: 'Cash', amount: 200000, days: 12 }] },
  })
  assert.equal(c.height, 900 + 150 + 2 * 50 + 70)
})
