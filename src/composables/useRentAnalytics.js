import { computed } from 'vue'
import { useRentalStore } from '@/stores/rental'
import { timeLeft } from '@/utils/format'

export { timeLeft }

// Landlord statistics, all derived from the data already loaded (payments, receipts, houses, tenants).
// "Billed" = rent charges for a month; "collected" = what has been paid against those charges.

const pad = (n) => String(n).padStart(2, '0')
export const periodOf = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}`
export const shortMonth = (period) => {
  const [y, m] = period.split('-').map(Number)
  return new Date(y, m - 1, 1).toLocaleDateString('en-GB', { month: 'short' })
}
export const longMonth = (period) => {
  const [y, m] = period.split('-').map(Number)
  return new Date(y, m - 1, 1).toLocaleDateString('en-GB', { month: 'long', year: 'numeric' })
}
export function lastPeriods(count, from = new Date()) {
  return Array.from({ length: count }, (_, i) => periodOf(new Date(from.getFullYear(), from.getMonth() - (count - 1 - i), 1)))
}

// Compact money for axes and tiles: 1.2M, 850K, 9,500
export function compactUGX(n) {
  const v = Number(n) || 0
  if (Math.abs(v) >= 1e6) return `${(v / 1e6).toFixed(v >= 1e7 ? 0 : 1).replace(/\.0$/, '')}M`
  if (Math.abs(v) >= 1e4) return `${Math.round(v / 1e3)}K`
  return v.toLocaleString('en-UG')
}

const daysUntil = (d) => Math.ceil((new Date(d).setHours(0, 0, 0, 0) - new Date().setHours(0, 0, 0, 0)) / 86400000)

export const channelOf = (method) => (/cash/i.test(method ?? '') ? 'Cash' : 'Mobile money')

export function useRentAnalytics() {
  const rental = useRentalStore()
  const today = () => new Date().toLocaleDateString('en-CA')

  // Billed vs collected per rent month
  const byMonth = (count) =>
    lastPeriods(count).map((period) => {
      const charges = rental.payments.filter((p) => p.period === period)
      const billed = charges.reduce((s, p) => s + p.amount, 0)
      const collected = charges.reduce((s, p) => s + p.amountPaid, 0)
      return { period, label: shortMonth(period), billed, collected, rate: billed ? Math.round((collected / billed) * 100) : 0 }
    })
  const months6 = computed(() => byMonth(6))
  const months12 = computed(() => byMonth(12))

  const thisMonth = computed(() => months6.value.at(-1))
  const lastMonth = computed(() => months6.value.at(-2))
  // Change vs last month, in % (null when there's nothing to compare with)
  const delta = (now, before) => (before ? Math.round(((now - before) / before) * 100) : null)
  const collectedDelta = computed(() => delta(thisMonth.value.collected, lastMonth.value.collected))

  const outstanding = computed(() => rental.payments.filter((p) => p.status !== 'paid').reduce((s, p) => s + p.balance, 0))
  const overdueTotal = computed(() => rental.payments.filter((p) => p.status === 'overdue').reduce((s, p) => s + p.balance, 0))
  const totalCollected = computed(() => rental.payments.reduce((s, p) => s + p.amountPaid, 0))

  const occupancy = computed(() => {
    const total = rental.properties.length
    const occupied = rental.properties.filter((p) => rental.tenantForProperty(p.id)).length
    return { total, occupied, vacant: total - occupied, rate: total ? Math.round((occupied / total) * 100) : 0 }
  })
  const potentialMonthly = computed(() => rental.properties.reduce((s, p) => s + (p.rent || 0), 0))
  const occupiedMonthly = computed(() =>
    rental.properties.filter((p) => rental.tenantForProperty(p.id)).reduce((s, p) => s + (p.rent || 0), 0),
  )

  // How money arrived: from receipts when available (each amount), else from paid charges
  const methods = computed(() => {
    const rows = rental.payment_receipts.length
      ? rental.payment_receipts.map((r) => ({ method: r.method, amount: r.amount }))
      : rental.payments.filter((p) => p.amountPaid).map((p) => ({ method: p.method, amount: p.amountPaid }))
    const bucket = (m) => (/mtn/i.test(m ?? '') ? 'MTN MoMo' : /airtel/i.test(m ?? '') ? 'Airtel Money' : /cash/i.test(m ?? '') ? 'Cash' : 'Other')
    const totals = { 'MTN MoMo': 0, 'Airtel Money': 0, Cash: 0, Other: 0 }
    for (const r of rows) totals[bucket(r.method)] += r.amount
    const sum = Object.values(totals).reduce((a, b) => a + b, 0)
    return Object.entries(totals)
      .filter(([, v]) => v > 0)
      .map(([label, value]) => ({ label, value, share: sum ? Math.round((value / sum) * 100) : 0 }))
  })

  // Unpaid rent by how late it is
  const aging = computed(() => {
    const now = new Date(today()).getTime()
    const buckets = [
      { label: 'Not due yet', min: -Infinity, max: 0, value: 0, count: 0 },
      { label: '1–30 days', min: 1, max: 30, value: 0, count: 0 },
      { label: '31–60 days', min: 31, max: 60, value: 0, count: 0 },
      { label: '61–90 days', min: 61, max: 90, value: 0, count: 0 },
      { label: '90+ days', min: 91, max: Infinity, value: 0, count: 0 },
    ]
    for (const p of rental.payments.filter((x) => x.status !== 'paid')) {
      const late = Math.floor((now - new Date(p.dueDate).getTime()) / 86400000)
      const b = buckets.find((x) => late >= x.min && late <= x.max)
      b.value += p.balance
      b.count += 1
    }
    return buckets
  })

  // Income per house (everything collected so far)
  const byHouse = computed(() =>
    rental.properties
      .map((h) => {
        const charges = rental.payments.filter((p) => p.propertyId === h.id)
        return {
          id: h.id,
          label: rental.placeName(h.id),
          value: charges.reduce((s, p) => s + p.amountPaid, 0),
          owed: charges.reduce((s, p) => s + p.balance, 0),
          occupied: Boolean(rental.tenantForProperty(h.id)),
        }
      })
      .sort((a, b) => b.value - a.value),
  )

  // Tenants with the most unpaid rent
  const topDebtors = computed(() =>
    rental.currentTenants
      .map((t) => ({ ...t, owed: rental.duesForTenant(t.id).reduce((s, p) => s + p.balance, 0) }))
      .filter((t) => t.owed > 0)
      .sort((a, b) => b.owed - a.owed),
  )

  // Every amount received, newest first (receipts when available, else paid charges)
  const revenue = computed(() => {
    const payment = (id) => rental.payments.find((p) => p.id === id)
    const fromReceipts = rental.payment_receipts.map((r) => {
      const p = payment(r.paymentId)
      return { id: r.id, tenantId: r.tenantId, propertyId: p?.propertyId, period: p?.period, amount: r.amount, method: r.method, reference: r.reference, note: r.note, at: r.receivedAt }
    })
    // Money paid on a rent charge that has no receipt behind it (e.g. paid before receipts existed):
    // still counted, so Transactions / Revenue always match what the rent charges say was paid.
    const receipted = {}
    for (const r of rental.payment_receipts) receipted[r.paymentId] = (receipted[r.paymentId] ?? 0) + r.amount
    const uncovered = rental.payments
      .filter((p) => p.amountPaid > (receipted[p.id] ?? 0))
      .map((p) => ({
        id: `charge-${p.id}`, tenantId: p.tenantId, propertyId: p.propertyId, period: p.period,
        amount: p.amountPaid - (receipted[p.id] ?? 0), method: p.method, reference: p.reference, note: null, at: p.paidAt ?? p.dueDate,
      }))
    const rows = [...fromReceipts, ...uncovered]
    return rows
      .map((r) => ({ ...r, channel: channelOf(r.method) }))
      .sort((a, b) => (b.at ?? '').localeCompare(a.at ?? ''))
  })
  const totalRevenue = computed(() => revenue.value.reduce((s, r) => s + r.amount, 0))

  // Cash vs mobile money: amount, number of payments, share of the money
  const channels = computed(() => {
    const out = ['Mobile money', 'Cash'].map((label) => {
      const rows = revenue.value.filter((r) => r.channel === label)
      return { label, value: rows.reduce((s, r) => s + r.amount, 0), count: rows.length }
    })
    const sum = out.reduce((s, c) => s + c.value, 0)
    return out.map((c) => ({ ...c, share: sum ? Math.round((c.value / sum) * 100) : 0 }))
  })
  // Used most often = the most payments (not the most money)
  const topChannel = computed(() => {
    const [m, c] = channels.value
    if (!m.count && !c.count) return null
    return m.count >= c.count ? m : c
  })

  // Time each current tenant has left in their room
  const tenancies = computed(() =>
    rental.currentTenants
      .map((t) => {
        const daysLeft = t.leaseEnd ? daysUntil(t.leaseEnd) : null
        const total = t.leaseStart && t.leaseEnd ? Math.max(1, daysUntil(t.leaseEnd) - daysUntil(t.leaseStart)) : null
        const used = total && daysLeft !== null ? Math.min(100, Math.max(0, Math.round(((total - daysLeft) / total) * 100))) : null
        return { ...t, daysLeft, used, left: timeLeft(daysLeft) }
      })
      .sort((a, b) => (a.daysLeft ?? Infinity) - (b.daysLeft ?? Infinity)),
  )

  return {
    months6, months12, thisMonth, lastMonth, collectedDelta, outstanding, overdueTotal, totalCollected,
    occupancy, potentialMonthly, occupiedMonthly, methods, aging, byHouse, topDebtors,
    revenue, totalRevenue, channels, topChannel, tenancies,
  }
}

// Download rows as a CSV file (opens in Excel / Google Sheets)
export function downloadCSV(filename, columns, rows) {
  const esc = (v) => {
    const s = v == null ? '' : String(v)
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
  }
  const lines = [columns.map((c) => esc(c.label)).join(','), ...rows.map((r) => columns.map((c) => esc(c.value(r))).join(','))]
  const blob = new Blob(['﻿' + lines.join('\n')], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = Object.assign(document.createElement('a'), { href: url, download: filename })
  document.body.appendChild(a)
  a.click()
  a.remove()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}
