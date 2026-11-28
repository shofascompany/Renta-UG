// Rent cycles: one month at a time. The first month starts on the day of the first payment (chosen by
// the landlord). Each next month runs on from the day the last one ended. Days after the end that are
// not paid for yet are DEBT DAYS: when the tenant pays, they are taken from that next month.
import { DAY_MS, daysLeftAt, rentEnds, ugandaDay } from './exactTime.js'

const DAY = 86_400_000

export const isoDay = (d) => {
  const x = new Date(d)
  return `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, '0')}-${String(x.getDate()).padStart(2, '0')}`
}
const at = (s) => new Date(`${String(s).slice(0, 10)}T00:00:00`)
export const daysBetween = (from, to) => Math.round((at(to) - at(from)) / DAY) // to − from

// A rent month is always 30 days (never 28, 29 or 31), the same as the database (database/52)
export const RENT_MONTH_DAYS = 30
export function addMonths(d, n) {
  const x = new Date(d)
  x.setDate(x.getDate() + n * RENT_MONTH_DAYS)
  return x
}

// tenant: { leaseStart, leaseEnd }; lastPaidOn: day of their latest payment ('YYYY-MM-DD'), if any
export function rentCycle(tenant, lastPaidOn = null, now = Date.now()) {
  if (!tenant?.leaseEnd) return { started: false, debtDays: 0, daysLeft: null }
  const end = String(tenant.leaseEnd).slice(0, 10)
  const start = isoDay(addMonths(at(end), -1)) // the day the current month began
  const daysLeft = daysLeftAt(rentEnds(tenant), now) // 0 or less = ended
  const debtDays = daysLeft < 0 ? -daysLeft : 0 // complete unpaid days since the month ended
  // Paid late for this month? Those days were taken from it.
  const paidOn = lastPaidOn && lastPaidOn > start && lastPaidOn <= end ? lastPaidOn : null
  const lateDays = paidOn ? daysBetween(start, paidOn) : 0
  return {
    started: true,
    start,
    end,
    paidOn: paidOn ?? start,
    daysLeft,
    ended: daysLeft <= 0,
    debtDays,
    lateDays,
    fullDays: daysBetween(start, end), // a whole rent month: 30 days
    paidDays: daysBetween(paidOn ?? start, end), // days actually paid for in this month
  }
}

export function addDays(d, n) {
  const x = new Date(d)
  x.setDate(x.getDate() + n)
  return x
}

// Part payments buy days (same rule as database/52): money paid on a month ÷ its rent × 30 days,
// rounded down. Once a month is paid in full it gives one whole rent month (30 days) instead (minus the
// days it already gave). Money is used on unpaid months first (oldest first), then months ahead.
export const DAYS_PER_MONTH = RENT_MONTH_DAYS
export const daysFor = (paid, rent) => (rent > 0 ? Math.floor((Math.max(0, paid) * DAYS_PER_MONTH) / rent) : 0)

// Debt days on a day: today they are complete 24 hours since the exact end, another day is counted by its date
const debtOn = (tenant, payDay) => {
  if (!tenant?.leaseEnd) return 0
  const now = Date.now()
  return payDay === ugandaDay(now) ? Math.max(0, Math.floor((now - rentEnds(tenant)) / DAY_MS)) : Math.max(0, daysBetween(tenant.leaseEnd, payDay))
}

// What a payment would do to the tenant's rental time.
//   tenant   { leaseEnd }
//   dues     unpaid rent months, oldest first: { amount, amountPaid, creditedDays, monthCredited }
//   rent     the monthly rent (for months ahead)
//   amount   money being paid now
//   before   money already sent and still waiting for the landlord (counted first)
// → { from, end, days, debtDays, endsBeforeToday, months, partDays }
export function coverage({ tenant, dues = [], rent = 0, amount = 0, before = 0, payDay = isoDay(new Date()) }) {
  const run = (money) => {
    let left = money
    let months = 0
    let days = 0
    for (const c of dues) {
      if (left <= 0) break
      const owed = Math.max(0, c.amount - c.amountPaid)
      const take = Math.min(left, owed)
      left -= take
      if (c.monthCredited || c.amount <= 0 || !take) continue
      const paid = c.amountPaid + take
      if (paid >= c.amount) {
        months += 1
        days -= c.creditedDays ?? 0
      } else {
        const d = daysFor(paid, c.amount)
        if (d > (c.creditedDays ?? 0)) days += d - (c.creditedDays ?? 0)
      }
    }
    while (left > 0 && rent > 0) {
      const take = Math.min(left, rent)
      left -= take
      if (take >= rent) months += 1
      else days += daysFor(take, rent)
    }
    return { months, days }
  }
  const start = tenant?.leaseEnd ? String(tenant.leaseEnd).slice(0, 10) : payDay
  const endOf = ({ months, days }) => isoDay(addDays(addMonths(at(start), months), days))
  const from = endOf(run(before)) // after anything already waiting
  const after = run(before + amount)
  const end = endOf(after)
  const debtDays = debtOn(tenant, payDay)
  return {
    from,
    end,
    days: Math.max(0, daysBetween(from, end)), // rental time this payment adds
    debtDays,
    endsBeforeToday: end < payDay, // still behind after paying
    daysFromToday: daysBetween(payDay, end),
    firstPayment: !tenant?.leaseEnd,
  }
}

// What a payment pays for, piece by piece and in order, each with its dates (the same rules as coverage() above and
// the database): what is left of each unpaid month first, then whole 30-day months, then the days a part of a month
// buys. Only this payment's own time: money already waiting (before) comes first, so its time is cut off.
//   → [{ from, to, days, kind: 'due' | 'month' | 'part', period, whole, paid, of, cut, passed }]
//     cut     the piece started with the money already waiting (its first days are that money's)
//     passed  the whole piece is time that had already run out (unpaid time) by the pay day
export function coverageParts({ tenant, dues = [], rent = 0, amount = 0, before = 0, payDay = isoDay(new Date()) }) {
  const all = []
  let cursor = at(tenant?.leaseEnd ? String(tenant.leaseEnd).slice(0, 10) : payDay)
  const add = (days, piece) => {
    if (days <= 0) return
    const from = isoDay(cursor)
    cursor = addDays(cursor, days)
    all.push({ ...piece, from, to: isoDay(cursor), days })
  }
  let left = before + amount
  for (const c of dues) {
    if (left <= 0) break
    const owed = Math.max(0, c.amount - c.amountPaid)
    const take = Math.min(left, owed)
    left -= take
    if (c.monthCredited || c.amount <= 0 || !take) continue
    const whole = c.amountPaid + take >= c.amount
    const credited = c.creditedDays ?? 0
    add(whole ? RENT_MONTH_DAYS - credited : daysFor(c.amountPaid + take, c.amount) - credited, { kind: 'due', period: c.period, whole, paid: take, of: owed })
  }
  while (left > 0 && rent > 0) {
    const take = Math.min(left, rent)
    left -= take
    add(take >= rent ? RENT_MONTH_DAYS : daysFor(take, rent), { kind: take >= rent ? 'month' : 'part', paid: take, of: rent })
  }
  const { from } = coverage({ tenant, dues, rent, amount, before, payDay })
  return all
    .filter((p) => p.to > from)
    .map((p) => (p.from < from ? { ...p, from, days: daysBetween(from, p.to), cut: true } : { ...p, cut: false }))
    .map((p) => ({ ...p, passed: p.to <= payDay }))
}

// A tenant whose paid time has run out has debt days. Money they pay covers those days first; only the rest is added
// (the same as the database: the new time runs on from the old end, database/52 + 63).
//   cover   coverage() of the payment
//   tenant  { leaseEnd }
// → { debtPaid, added, behind, from, to }   debt days this payment pays (from → to), days added after them, and the
//                                           debt days still unpaid after it
export function debtSplit(cover, tenant) {
  const days = cover?.days ?? 0
  if (!cover || !tenant?.leaseEnd || !cover.debtDays) return { debtPaid: 0, added: days, behind: 0, from: null, to: null }
  const debtTo = isoDay(addDays(at(String(tenant.leaseEnd).slice(0, 10)), cover.debtDays)) // where the debt days end
  const to = cover.end < debtTo ? cover.end : debtTo
  const debtPaid = Math.min(days, Math.max(0, daysBetween(cover.from, to)))
  return { debtPaid, added: days - debtPaid, behind: Math.max(0, daysBetween(cover.end, debtTo)), from: debtPaid ? cover.from : null, to: debtPaid ? to : null }
}

// Days as rent months and days: 75 → "2 months and 15 days", 30 → "1 month", 15 → "15 days"
export function durationText(days) {
  const m = Math.floor(days / RENT_MONTH_DAYS)
  const d = days % RENT_MONTH_DAYS
  const months = m ? `${m} month${m === 1 ? '' : 's'}` : ''
  const rest = d ? `${d} day${d === 1 ? '' : 's'}` : ''
  return months && rest ? `${months} and ${rest}` : months || rest || '0 days'
}

// After paying one month now: when it ends and how many days it really gives
export function nextCycle(tenant, payDay = isoDay(new Date())) {
  if (!tenant?.leaseEnd) {
    const end = isoDay(addMonths(at(payDay), 1))
    return { from: payDay, end, debtDays: 0, days: daysBetween(payDay, end) }
  }
  const oldEnd = String(tenant.leaseEnd).slice(0, 10)
  const end = isoDay(addMonths(at(oldEnd), 1))
  const debtDays = debtOn(tenant, payDay)
  return { from: oldEnd, end, debtDays, days: daysBetween(oldEnd < payDay ? payDay : oldEnd, end) }
}
