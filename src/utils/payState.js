import { formatUGX, formatDate } from './format.js'

// ONE answer, everywhere in Renta UG, to "has this tenant paid?"
//   paid    Paid       nothing owed AND their paid rental time is still running
//   part    Part paid  paid some of what is due, the rest is still owed
//   unpaid  Not paid   owes rent, has never paid, or their paid time has ended (debt days)
//   left    Moved out  former tenant
// A tenant who owes UGX 0 is NOT "paid" when they have never paid or their time has run out.
const DAY = 86_400_000
const at = (s) => new Date(`${String(s).slice(0, 10)}T00:00:00`)
const todayISO = () => new Date().toLocaleDateString('en-CA')

export const PAY_TONE = {
  paid: { pill: 'bg-emerald-50 text-emerald-700 ring-emerald-600/20', text: 'text-emerald-700', dot: 'bg-emerald-500' },
  part: { pill: 'bg-amber-50 text-amber-800 ring-amber-600/25', text: 'text-amber-700', dot: 'bg-amber-500' },
  unpaid: { pill: 'bg-red-50 text-red-700 ring-red-600/20', text: 'text-red-600', dot: 'bg-red-500' },
  left: { pill: 'bg-slate-100 text-slate-600 ring-slate-500/15', text: 'text-slate-500', dot: 'bg-slate-400' },
}

/**
 * tenant   { propertyId, leaseEnd }
 * charges  this tenant's rent months: { status: 'paid'|'pending'|'overdue', amount, amountPaid, balance, dueDate }
 * rent     the house's monthly rent
 */
export function payState(tenant, charges = [], rent = 0, today = todayISO()) {
  if (!tenant) return null
  if (!tenant.propertyId) return { key: 'left', label: 'Moved out', detail: 'Former tenant', owed: 0, ...PAY_TONE.left }

  const dues = charges.filter((p) => p.status !== 'paid' && p.balance > 0)
  const owedCharged = dues.reduce((s, p) => s + p.balance, 0)
  const overdue = dues.some((p) => p.status === 'overdue')
  const part = dues.some((p) => p.amountPaid > 0)
  const everPaid = charges.some((p) => p.amountPaid > 0)
  const end = tenant.leaseEnd ? String(tenant.leaseEnd).slice(0, 10) : null
  const daysLeft = end ? Math.round((at(end) - at(today)) / DAY) : null
  const base = (key, label, detail, owed) => ({ key, label, detail, owed, overdue, daysLeft, ...PAY_TONE[key] })

  // Never paid anything: their rental time hasn't started
  if (!end && !everPaid) return base('unpaid', 'Not paid', 'Has not paid yet', owedCharged || rent)
  // Owes money on rent months
  if (owedCharged > 0) {
    return base(
      part ? 'part' : 'unpaid',
      part ? 'Part paid' : 'Not paid',
      `${formatUGX(owedCharged)} owed${overdue ? ' · overdue' : ''}`,
      owedCharged,
    )
  }
  // Nothing charged, but the paid time has run out
  if (daysLeft !== null && daysLeft < 0) {
    return base('unpaid', 'Not paid', `Time ended ${-daysLeft} day${daysLeft === -1 ? '' : 's'} ago`, rent)
  }
  return base('paid', 'Paid', end ? `Paid up to ${formatDate(end)}` : 'Paid', 0)
}
