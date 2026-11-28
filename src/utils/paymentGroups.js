// One payment = every receipt one confirmation saved: one per rent month it paid, all written together (the same
// tenant, the same moment, the same day received). The same rule as the database uses to reverse it (database/63).
export const paymentKey = (r) => `${r.tenantId}|${r.createdAt ?? ''}|${r.receivedAt ?? ''}`

const sameMoment = (a, b) => Boolean(a && b) && Date.parse(a) === Date.parse(b)

/**
 * The whole payment a receipt belongs to.
 *   receipts   rental.payment_receipts
 *   receiptId  any one of its receipts
 *   periodOf   (paymentId) → 'YYYY-MM' of that rent month, to list the months in order
 * → { key, id, tenantId, landlordId, receipts (earliest month first), total, at, createdAt, method, reference, note }
 */
export function paymentOf(receipts, receiptId, periodOf = () => '') {
  const r = receipts.find((x) => x.id === receiptId)
  if (!r) return null
  const key = paymentKey(r)
  const list = receipts
    .filter((x) => paymentKey(x) === key)
    .sort((a, b) => String(periodOf(a.paymentId)).localeCompare(String(periodOf(b.paymentId))) || String(a.id).localeCompare(String(b.id)))
  return {
    key,
    id: list[0].id,
    tenantId: r.tenantId,
    landlordId: r.landlordId,
    receipts: list,
    total: list.reduce((s, x) => s + x.amount, 0),
    at: r.receivedAt,
    createdAt: r.createdAt ?? null,
    method: r.method,
    reference: list.find((x) => x.reference)?.reference ?? null,
    note: r.note ?? null,
  }
}

// The cash / mobile money record a payment came from: confirmed in the same moment its receipts were saved
export const cashRecordOf = (payment, cashPayments) =>
  payment?.createdAt ? cashPayments.find((c) => c.tenantId === payment.tenantId && sameMoment(c.reviewedAt, payment.createdAt)) ?? null : null
