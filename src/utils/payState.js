import { formatUGX, formatDate } from './format.js'
import { RENT_MONTH_DAYS } from './rentCycle.js'
import { DAY_MS, daysLeftAt, momentOf, moveDay, rentEnds, ugandaDay } from './exactTime.js'

// ONE answer, everywhere in Renta UG, to "has this tenant paid?"
//   paid    Paid       nothing owed AND their paid rental time is still running
//   part    Part paid  paid some of what is due, the rest is still owed
//   unpaid  Not paid   owes rent, has never paid, or their paid time has ended (debt days)
//   left    Moved out  former tenant
// A tenant who owes UGX 0 is NOT "paid" when they have never paid or their time has run out.
//
// What they owe = every month in debt × the room's rent. A month counts from the moment it begins: from the exact end
// of the paid time = 1 month, 30 × 24 hours later = 2 months… A month that is part paid counts only what is left of it.
// It is exactly the money that brings them up to date (same rules as the database, see utils/rentCycle.js).

export const PAY_TONE = {
  paid: { pill: 'bg-emerald-50 text-emerald-700 ring-emerald-600/20', text: 'text-emerald-700', dot: 'bg-emerald-500' },
  part: { pill: 'bg-amber-50 text-amber-800 ring-amber-600/25', text: 'text-amber-700', dot: 'bg-amber-500' },
  unpaid: { pill: 'bg-red-50 text-red-700 ring-red-600/20', text: 'text-red-600', dot: 'bg-red-500' },
  left: { pill: 'bg-slate-100 text-slate-600 ring-slate-500/15', text: 'text-slate-500', dot: 'bg-slate-400' },
}

// How the total is made up: "3 months × 300,000", "2 months + 150,000", "Rest of 1 month"
function howMuch(months, rent) {
  const n = (k) => `${k} month${k === 1 ? '' : 's'}`
  const money = (v) => Number(v).toLocaleString('en-UG')
  const full = months.filter((m) => !m.part && m.amount === rent).length
  const rest = months.filter((m) => m.part || m.amount !== rent).reduce((s, m) => s + m.amount, 0)
  if (full) return rest ? `${n(full)} + ${money(rest)}` : `${n(full)} × ${money(rent)}`
  return months.every((m) => m.part) ? `Rest of ${n(months.length)}` : n(months.length)
}

/**
 * tenant   { propertyId, leaseEnd, leaseClock }
 * charges  this tenant's rent months: { status: 'paid'|'pending'|'overdue', amount, amountPaid, balance, dueDate,
 *          creditedDays, monthCredited }
 * rent     the house's monthly rent
 * when     now (a moment, or a day like 2026-11-25)
 * → { key, label, detail, owed, months: [{ amount, from }] oldest first, how: '3 months × 300,000', … }
 */
export function payState(tenant, charges = [], rent = 0, when = Date.now()) {
  if (!tenant) return null
  if (!tenant.propertyId) return { key: 'left', label: 'Moved out', detail: 'Former tenant', owed: 0, months: [], how: '', ...PAY_TONE.left }

  const dues = charges.filter((p) => p.status !== 'paid' && p.balance > 0)
  const owedCharged = dues.reduce((s, p) => s + p.balance, 0)
  const overdue = dues.some((p) => p.status === 'overdue')
  const part = dues.some((p) => p.amountPaid > 0)
  const everPaid = charges.some((p) => p.amountPaid > 0)
  const end = tenant.leaseEnd ? String(tenant.leaseEnd).slice(0, 10) : null
  const now = momentOf(when)
  const ends = rentEnds(tenant)
  const daysLeft = daysLeftAt(ends, now) // 0 or less = ended
  const ended = ends !== null && ends <= now

  // The months in debt: the ones already charged, then every month begun since
  const months = [...dues]
    .sort((a, b) => String(a.dueDate).localeCompare(String(b.dueDate)))
    .map((p) => ({ amount: p.balance, from: p.dueDate, propertyId: p.propertyId, part: p.amountPaid > 0 }))
  if (!end && !everPaid) {
    if (!months.length && rent > 0) months.push({ amount: rent, from: ugandaDay(now), part: false }) // the first month
  } else if (end && rent > 0) {
    // Paying the charged months would move the paid time here…
    const given = dues.reduce((s, p) => s + (p.monthCredited ? 0 : Math.max(0, RENT_MONTH_DAYS - (p.creditedDays ?? 0))), 0)
    const paidTo = ends + given * DAY_MS
    // …and every month begun after that is in debt too
    const begun = paidTo > now ? 0 : Math.floor((now - paidTo) / (RENT_MONTH_DAYS * DAY_MS)) + 1
    for (let i = 0; i < begun; i++) months.push({ amount: rent, from: moveDay(end, given + i * RENT_MONTH_DAYS), part: false })
  }
  const owedAll = months.reduce((s, m) => s + m.amount, 0)

  const base = (key, label, detail, owed) => ({
    key, label, detail, owed, overdue, daysLeft, ended, ...PAY_TONE[key],
    months: owed ? months : [],
    how: owed ? howMuch(months, rent) : '',
    late: key !== 'paid' && (overdue || ended), // what every "Overdue" filter shows
  })

  // Never paid anything: their rental time hasn't started
  if (!end && !everPaid) return base('unpaid', 'Not paid', 'Has not paid yet', owedAll)
  // Owes money on rent months
  if (owedCharged > 0) {
    return base(
      part ? 'part' : 'unpaid',
      part ? 'Part paid' : 'Not paid',
      `${formatUGX(owedAll)} owed${overdue || ended ? ' · overdue' : ''}`,
      owedAll,
    )
  }
  // Nothing charged, but the paid time has run out
  if (ended) {
    return base('unpaid', 'Not paid', daysLeft ? `Time ended ${-daysLeft} day${daysLeft === -1 ? '' : 's'} ago` : 'Time has ended', owedAll)
  }
  return base('paid', 'Paid', end ? `Paid up to ${formatDate(end)}` : 'Paid', 0)
}
