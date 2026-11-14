import { computed } from 'vue'
import { useRentalStore } from '@/stores/rental'
import { channelOf } from '@/composables/useRentAnalytics'

// Main admin: platform-wide figures, computed from everything the store has loaded.
// Money "collected" = what tenants have actually paid against rent (payments.amount_paid),
// so it matches the landlords' own pages. Transactions come from payment_receipts.
const pad = (n) => String(n).padStart(2, '0')
const periodOf = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}`
const shortMonth = (period) => {
  const [y, m] = period.split('-').map(Number)
  return new Date(y, m - 1, 1).toLocaleDateString('en-GB', { month: 'short' })
}

export function usePlatformStats() {
  const rental = useRentalStore()
  const thisPeriod = periodOf(new Date())

  const lastPeriods = (n) =>
    Array.from({ length: n }, (_, i) => {
      const d = new Date()
      d.setDate(1)
      d.setMonth(d.getMonth() - (n - 1 - i))
      return periodOf(d)
    })

  const totalCollected = computed(() => rental.payments.reduce((s, p) => s + p.amountPaid, 0))
  const monthCollected = computed(() => rental.payments.filter((p) => p.period === thisPeriod).reduce((s, p) => s + p.amountPaid, 0))
  const monthBilled = computed(() => rental.payments.filter((p) => p.period === thisPeriod).reduce((s, p) => s + p.amount, 0))
  const outstanding = computed(() => rental.payments.reduce((s, p) => s + p.balance, 0))
  const overdueTenants = computed(() => new Set(rental.payments.filter((p) => p.status === 'overdue').map((p) => p.tenantId)).size)

  // Money received per calendar month (by the day it came in)
  const byMonth = computed(() =>
    lastPeriods(6).map((period) => ({
      period,
      label: shortMonth(period),
      value: rental.payment_receipts.filter((r) => String(r.receivedAt).slice(0, 7) === period).reduce((s, r) => s + r.amount, 0),
    })),
  )

  const channels = computed(() => {
    const out = { 'Mobile money': { label: 'Mobile money', value: 0, count: 0 }, Cash: { label: 'Cash', value: 0, count: 0 } }
    for (const r of rental.payment_receipts) {
      const c = out[channelOf(r.method)]
      c.value += r.amount
      c.count += 1
    }
    const total = out['Mobile money'].value + out.Cash.value
    return Object.values(out).map((c) => ({ ...c, share: total ? Math.round((c.value / total) * 100) : 0 }))
  })

  const occupancy = computed(() => {
    const occupied = new Set(rental.tenants.filter((t) => t.propertyId).map((t) => t.propertyId))
    const total = rental.properties.length
    const used = rental.properties.filter((p) => occupied.has(p.id)).length
    return { total, used, vacant: total - used, rate: total ? Math.round((used / total) * 100) : 0 }
  })

  const landlordName = (id) => rental.landlords.find((l) => l.id === id)?.name ?? 'Unknown landlord'

  // Collected per landlord, largest first
  const byLandlord = computed(() =>
    rental.landlords
      .map((l) => ({
        id: l.id,
        label: l.name ?? l.email,
        value: rental.payments.filter((p) => p.landlordId === l.id).reduce((s, p) => s + p.amountPaid, 0),
      }))
      .sort((a, b) => b.value - a.value),
  )

  const recentReceipts = computed(() => [...rental.payment_receipts].sort((a, b) => String(b.receivedAt).localeCompare(String(a.receivedAt))))

  return {
    thisPeriod,
    totalCollected,
    monthCollected,
    monthBilled,
    outstanding,
    overdueTenants,
    byMonth,
    channels,
    occupancy,
    byLandlord,
    recentReceipts,
    landlordName,
  }
}
