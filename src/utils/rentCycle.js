// Rent cycles: one month at a time. The first month starts on the day of the first payment (chosen by
// the landlord). Each next month runs on from the day the last one ended. Days after the end that are
// not paid for yet are DEBT DAYS: when the tenant pays, they are taken from that next month.
const DAY = 86_400_000

export const isoDay = (d) => {
  const x = new Date(d)
  return `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, '0')}-${String(x.getDate()).padStart(2, '0')}`
}
const at = (s) => new Date(`${String(s).slice(0, 10)}T00:00:00`)
export const daysBetween = (from, to) => Math.round((at(to) - at(from)) / DAY) // to − from

export function addMonths(d, n) {
  const x = new Date(d)
  const day = x.getDate()
  x.setDate(1)
  x.setMonth(x.getMonth() + n)
  x.setDate(Math.min(day, new Date(x.getFullYear(), x.getMonth() + 1, 0).getDate()))
  return x
}

// tenant: { leaseStart, leaseEnd }; lastPaidOn: day of their latest payment ('YYYY-MM-DD'), if any
export function rentCycle(tenant, lastPaidOn = null) {
  if (!tenant?.leaseEnd) return { started: false, debtDays: 0, daysLeft: null }
  const today = isoDay(new Date())
  const end = String(tenant.leaseEnd).slice(0, 10)
  const start = isoDay(addMonths(at(end), -1)) // the day the current month began
  const daysLeft = daysBetween(today, end)
  const debtDays = daysLeft < 0 ? -daysLeft : 0 // unpaid days since the month ended
  // Paid late for this month? Those days were taken from it.
  const paidOn = lastPaidOn && lastPaidOn > start && lastPaidOn <= end ? lastPaidOn : null
  const lateDays = paidOn ? daysBetween(start, paidOn) : 0
  return {
    started: true,
    start,
    end,
    paidOn: paidOn ?? start,
    daysLeft,
    debtDays,
    lateDays,
    fullDays: daysBetween(start, end), // a whole month (28–31 days)
    paidDays: daysBetween(paidOn ?? start, end), // days actually paid for in this month
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
  const debtDays = Math.max(0, daysBetween(oldEnd, payDay))
  return { from: oldEnd, end, debtDays, days: daysBetween(debtDays ? payDay : oldEnd, end) }
}
