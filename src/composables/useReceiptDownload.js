import { ref } from 'vue'
import { useRentalStore } from '@/stores/rental'
import { useAuthStore } from '@/stores/auth'
import { downloadReceipt } from '@/lib/receiptImage'
import { isoDay, daysFor, RENT_MONTH_DAYS } from '@/utils/rentCycle'
import { formatPeriod } from '@/utils/format'

// Save a payment receipt as a landscape image (PNG), for landlords and tenants alike.
//   saveRevenue(r)  one amount received ({ id, paymentId, tenantId, propertyId, period, amount, method, reference, note, at })
//   saveCash(c)     a confirmed cash / mobile money payment (may cover several months)
//   instalmentsFor(paymentId)  every payment made towards one rent month, in order, with the days each bought
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

  async function save(id, data) {
    if (saving.value) return
    saving.value = id
    try {
      await downloadReceipt({ id, ...data })
    } finally {
      saving.value = null
    }
  }

  function saveRevenue(r) {
    const plan = r.paymentId ? instalmentsFor(r.paymentId) : null
    return save(r.id, {
      ...base(r.tenantId, r.propertyId),
      amount: r.amount,
      method: /cash/i.test(r.method ?? '') ? 'Cash' : r.method || 'Mobile money',
      paidOn: r.at,
      confirmedOn: r.at,
      confirmedBy: 'Landlord',
      months: r.period ? [formatPeriod(r.period)] : [],
      details: r.reference || r.note,
      // Paid in turns (or not finished yet): list every instalment on the receipt
      instalments: plan && (plan.rows.length > 1 || plan.balance > 0) ? { ...plan, period: formatPeriod(plan.period), current: r.id } : null,
    })
  }

  function saveCash(c) {
    const parts = rental.payment_receipts.filter(
      (r) => r.tenantId === c.tenantId && (r.note ?? null) === (c.note ?? null) && isoDay(r.receivedAt) === c.paidOn,
    )
    const paymentIds = [...new Set(parts.map((r) => r.paymentId))]
    const periods = paymentIds.map((id) => rental.payments.find((p) => p.id === id)?.period).filter(Boolean)
    const plan = paymentIds.length === 1 ? instalmentsFor(paymentIds[0]) : null
    return save(c.id, {
      ...base(c.tenantId),
      amount: c.confirmedAmount ?? c.amount,
      method: c.method === 'mobile_money' ? ({ mtn: 'MTN Mobile Money', airtel: 'Airtel Money' }[c.network] ?? 'Mobile money') : 'Cash',
      paidOn: c.paidOn,
      confirmedOn: c.reviewedAt ?? c.paidOn,
      confirmedBy: c.reviewedRole === 'superadmin' ? 'Renta UG' : 'Landlord',
      months: [...new Set(periods)].sort().map(formatPeriod),
      details: c.note,
      instalments: plan && (plan.rows.length > 1 || plan.balance > 0) ? { ...plan, period: formatPeriod(plan.period), current: parts[0]?.id } : null,
    })
  }

  return { saving, saveRevenue, saveCash, instalmentsFor }
}
