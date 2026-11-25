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
