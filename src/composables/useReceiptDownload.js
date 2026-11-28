import { ref } from 'vue'
import { useRentalStore } from '@/stores/rental'
import { useAuthStore } from '@/stores/auth'
import { downloadReceipt, shareReceiptImage, canShareReceiptImage } from '@/lib/receiptImage'
import { isoDay, addDays, daysFor, RENT_MONTH_DAYS } from '@/utils/rentCycle'
import { cashRecordOf } from '@/utils/paymentGroups'
import { formatPeriod } from '@/utils/format'

// Save a payment receipt as a landscape image (PNG), for landlords and tenants alike.
//   saveRevenue(r)  one amount received ({ id, paymentId, tenantId, propertyId, period, amount, method, reference, note, at })
//   saveCash(c)     a confirmed cash / mobile money payment (may cover several months)
//   savePayment(p)  a whole payment (utils/paymentGroups.js paymentOf): its total and every month it paid
//   instalmentsFor(paymentId)  every payment made towards one rent month, in order, with the days each bought
//   windowsFor(tenantId)       for each payment of a tenant: the rental time it bought (from, to, days), worked back
//                              from the day their rent ends now
//   shareRevenue(r) / shareCash(c)  the same PNG receipts, saved and then sent as an image (WhatsApp) through the share sheet
//   canShare                   true on devices that can send the picture; the WhatsApp buttons only show then
// When a month was paid in several turns, the receipt lists every instalment, the total, the balance and
// the days covered.
export function useReceiptDownload() {
  const rental = useRentalStore()
  const auth = useAuthStore()
  const saving = ref(null)

  const landlordName = (landlordId) =>
    auth.isLandlord
      ? auth.user?.name || 'Landlord'
      : rental.owner?.full_name || rental.payAccountsOf(landlordId)[0]?.accountName || 'Your landlord'

  const base = (tenantId, propertyId) => {
    const t = rental.tenantById(tenantId)
    const pid = propertyId ?? t?.propertyId ?? t?.lastPropertyId
    return {
      tenantName: t?.name ?? 'Tenant',
      tenantPhone: t?.phone,
      property: pid && rental.propertyById(pid) ? rental.placeName(pid) : '—',
      landlordName: landlordName(t?.landlordId),
    }
  }

  // All payments towards one rent month, oldest first: amount, running total and the days each one bought
  function instalmentsFor(paymentId) {
    const charge = rental.payments.find((p) => p.id === paymentId)
    if (!charge) return null
    const list = rental.payment_receipts
      .filter((r) => r.paymentId === paymentId)
      .sort((a, b) => String(a.receivedAt).localeCompare(String(b.receivedAt)))
    let total = 0
    let given = 0
    const rows = list.map((r, i) => {
      total += r.amount
      // Paid in full → the whole 30-day month. (Months that counted under the old 60% rule did so at 60%.)
      const full = total >= charge.amount || (charge.monthCredited && !charge.creditedDays && total * 10 >= charge.amount * 6)
      const upTo = full ? RENT_MONTH_DAYS : daysFor(total, charge.amount)
      const days = Math.max(0, upTo - given)
      given = Math.max(given, upTo)
      return { id: r.id, n: i + 1, at: r.receivedAt, method: r.method, amount: r.amount, days, totalAfter: total, reference: r.reference, note: r.note }
    })
    const paid = Math.max(charge.amountPaid, total)
    return {
      period: charge.period,
      rent: charge.amount,
      paid,
      balance: Math.max(0, charge.amount - paid),
      days: Math.min(RENT_MONTH_DAYS, given),
      rows,
    }
  }

  // Rental time each payment of a tenant bought. Rent months run on from each other, so working back from the
  // day the rent ends now, every payment's time sits right after the one before it.
  function windowsFor(tenantId) {
    const out = new Map()
    const tenant = rental.tenantById(tenantId)
    if (!tenant?.leaseEnd) return out
    const plans = new Map()
    const periodOf = (r) => rental.payments.find((p) => p.id === r.paymentId)?.period ?? ''
    const daysOf = (r) => {
      if (!plans.has(r.paymentId)) plans.set(r.paymentId, instalmentsFor(r.paymentId))
      return plans.get(r.paymentId)?.rows.find((x) => x.id === r.id)?.days ?? 0
    }
    const list = rental.payment_receipts
      .filter((r) => r.tenantId === tenantId)
      // One payment covering several months has the same time on each: the earlier rent month comes first
      .sort((a, b) => String(a.receivedAt).localeCompare(String(b.receivedAt)) || periodOf(a).localeCompare(periodOf(b)) || String(a.id).localeCompare(String(b.id)))
    let end = String(tenant.leaseEnd).slice(0, 10)
    for (let i = list.length - 1; i >= 0; i--) {
      const days = daysOf(list[i])
      const from = isoDay(addDays(new Date(`${end}T12:00:00`), -days))
      out.set(list[i].id, { from, to: end, days })
      end = from
    }
    return out
  }

  // Window for one receipt, or the combined window of several (a payment spread over months)
  const windowOf = (tenantId, receiptIds) => {
    const map = windowsFor(tenantId)
    const parts = receiptIds.map((id) => map.get(id)).filter(Boolean)
    if (!parts.length) return null
    return {
      from: parts.map((p) => p.from).sort()[0],
      to: parts.map((p) => p.to).sort().at(-1),
      days: parts.reduce((s, p) => s + p.days, 0),
    }
  }

  async function save(id, data) {
    if (saving.value) return
    saving.value = id
    try {
      await downloadReceipt({ id, ...data })
    } finally {
      saving.value = null
    }
  }

  // WhatsApp: only opens the share list with the picture. Nothing is downloaded, and nothing on the page says so.
  let sharing = false
  async function share(id, data) {
    if (sharing) return
    sharing = true
    try {
      await shareReceiptImage({ id, ...data })
    } finally {
      sharing = false
    }
  }

  function revenueReceipt(r) {
    const plan = r.paymentId ? instalmentsFor(r.paymentId) : null
    return {
      ...base(r.tenantId, r.propertyId),
      amount: r.amount,
      method: /cash/i.test(r.method ?? '') ? 'Cash' : r.method || 'Mobile money',
      paidOn: r.at,
      confirmedOn: r.at,
      confirmedBy: 'Landlord',
      months: r.period ? [formatPeriod(r.period)] : [],
      details: r.reference || r.note,
      // Paid in turns (or not finished yet): list every instalment on the receipt
      window: windowOf(r.tenantId, [r.id]),
      instalments: plan && (plan.rows.length > 1 || plan.balance > 0) ? { ...plan, period: formatPeriod(plan.period), current: r.id } : null,
    }
  }
  const saveRevenue = (r) => save(r.id, revenueReceipt(r))
  const shareRevenue = (r) => share(r.id, revenueReceipt(r))

  function cashReceipt(c) {
    const parts = rental.payment_receipts.filter(
      (r) => r.tenantId === c.tenantId && (r.note ?? null) === (c.note ?? null) && isoDay(r.receivedAt) === c.paidOn,
    )
    const paymentIds = [...new Set(parts.map((r) => r.paymentId))]
    const periods = paymentIds.map((id) => rental.payments.find((p) => p.id === id)?.period).filter(Boolean)
    const plan = paymentIds.length === 1 ? instalmentsFor(paymentIds[0]) : null
    return {
      ...base(c.tenantId),
      amount: c.confirmedAmount ?? c.amount,
      method: c.method === 'mobile_money' ? ({ mtn: 'MTN Mobile Money', airtel: 'Airtel Money' }[c.network] ?? 'Mobile money') : 'Cash',
      paidOn: c.paidOn,
      confirmedOn: c.reviewedAt ?? c.paidOn,
      confirmedBy: c.reviewedRole === 'superadmin' ? 'Renta UG' : 'Landlord',
      months: [...new Set(periods)].sort().map(formatPeriod),
      details: c.note,
      window: windowOf(c.tenantId, parts.map((x) => x.id)),
      instalments: plan && (plan.rows.length > 1 || plan.balance > 0) ? { ...plan, period: formatPeriod(plan.period), current: parts[0]?.id } : null,
    }
  }
  const saveCash = (c) => save(c.id, cashReceipt(c))
  const shareCash = (c) => share(c.id, cashReceipt(c))

  // A whole payment (utils/paymentGroups.js): its total, every month it paid and the rental time it bought
  function paymentReceipt(p) {
    const cash = cashRecordOf(p, rental.cash_payments)
    const first = p.receipts[0]
    const charge = rental.payments.find((x) => x.id === first?.paymentId)
    const periods = p.receipts.map((r) => rental.payments.find((x) => x.id === r.paymentId)?.period).filter(Boolean)
    const plan = p.receipts.length === 1 && first?.paymentId ? instalmentsFor(first.paymentId) : null
    return {
      ...base(p.tenantId, charge?.propertyId),
      amount: p.total,
      method: /cash/i.test(p.method ?? '') ? 'Cash' : p.method || 'Mobile money',
      paidOn: p.at,
      confirmedOn: cash?.reviewedAt ?? p.at,
      confirmedBy: cash?.reviewedRole === 'superadmin' ? 'Renta UG' : 'Landlord',
      months: [...new Set(periods)].sort().map(formatPeriod),
      details: p.reference || p.note,
      window: windowOf(p.tenantId, p.receipts.map((r) => r.id)),
      instalments: plan && (plan.rows.length > 1 || plan.balance > 0) ? { ...plan, period: formatPeriod(plan.period), current: first.id } : null,
    }
  }
  const savePayment = (p) => save(p.id, paymentReceipt(p))
  const sharePayment = (p) => share(p.id, paymentReceipt(p))

  const canShare = canShareReceiptImage()
  return { saving, saveRevenue, saveCash, savePayment, shareRevenue, shareCash, sharePayment, canShare, instalmentsFor, windowsFor }
}
