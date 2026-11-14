<script setup>
import { computed, ref } from 'vue'
import {
  Wallet, TrendingUp, TrendingDown, Percent, Building2, Users, Smartphone, Clock, CalendarCheck2, Star, Hourglass, Receipt,
  CalendarClock, UserPlus, Briefcase, DoorOpen, Download,
} from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { usePlatformStats } from '@/composables/usePlatformStats'
import { compactUGX, downloadCSV } from '@/composables/useRentAnalytics'
import { formatUGX, formatPeriod } from '@/utils/format'
import SuperHero from '@/components/super/SuperHero.vue'
import StatTile from '@/components/super/StatTile.vue'
import Panel from '@/components/admin/Panel.vue'
import ColumnChart from '@/components/charts/ColumnChart.vue'
import RankBars from '@/components/charts/RankBars.vue'
import SegmentBar from '@/components/charts/SegmentBar.vue'

// Main admin: platform statistics — money, collection, arrears, occupancy, growth, adoption, tenancies.
// Everything is computed from live data, so the numbers always match the rest of the app.
const rental = useRentalStore()
const p = usePlatformStats()
const range = ref(6) // months shown in the charts

const pad = (n) => String(n).padStart(2, '0')
const periodOf = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}`
const periods = computed(() =>
  Array.from({ length: range.value }, (_, i) => {
    const d = new Date()
    d.setDate(1)
    d.setMonth(d.getMonth() - (range.value - 1 - i))
    return periodOf(d)
  }),
)
const short = (period) => new Date(`${period}-01T00:00:00`).toLocaleDateString('en-GB', { month: 'short' })
const thisP = periodOf(new Date())
const lastP = (() => {
  const d = new Date()
  d.setDate(1)
  d.setMonth(d.getMonth() - 1)
  return periodOf(d)
})()
const today = new Date().toLocaleDateString('en-CA')
const days = (a, b) => Math.round((new Date(b) - new Date(a)) / 86400000)
const pct = (a, b) => (b ? Math.round((a / b) * 100) : 0)
const sum = (arr, f) => arr.reduce((s, x) => s + f(x), 0)

// ── Money ──
const receivedIn = (period) => sum(rental.payment_receipts.filter((r) => String(r.receivedAt).startsWith(period)), (r) => r.amount)
const thisMonth = computed(() => receivedIn(thisP))
const lastMonth = computed(() => receivedIn(lastP))
const growth = computed(() => (lastMonth.value ? Math.round(((thisMonth.value - lastMonth.value) / lastMonth.value) * 100) : null))
const billedVsCollected = computed(() =>
  periods.value.map((period) => {
    const charges = rental.payments.filter((x) => x.period === period)
    return { label: short(period), value: sum(charges, (x) => x.amountPaid), ghost: sum(charges, (x) => x.amount) }
  }),
)
const billedAll = computed(() => sum(rental.payments, (x) => x.amount))
const collectionRate = computed(() => pct(p.totalCollected.value, billedAll.value))
const avgPayment = computed(() => (rental.payment_receipts.length ? Math.round(sum(rental.payment_receipts, (r) => r.amount) / rental.payment_receipts.length) : 0))
const paymentsThisMonth = computed(() => rental.payment_receipts.filter((r) => String(r.receivedAt).startsWith(thisP)).length)

// On time: fully paid on or before the due date
const paidCharges = computed(() => rental.payments.filter((x) => x.status === 'paid' && x.paidAt))
const onTimeRate = computed(() => pct(paidCharges.value.filter((x) => String(x.paidAt).slice(0, 10) <= x.dueDate).length, paidCharges.value.length))
const monthsAhead = computed(() => rental.payments.filter((x) => x.status === 'paid' && x.period > thisP).length)

// By network
const networks = computed(() => {
  const groups = { 'MTN Mobile Money': 0, 'Airtel Money': 0, Cash: 0, Other: 0 }
  for (const r of rental.payment_receipts) {
    const m = r.method ?? ''
    const k = /cash/i.test(m) ? 'Cash' : /mtn/i.test(m) ? 'MTN Mobile Money' : /airtel/i.test(m) ? 'Airtel Money' : 'Other'
    groups[k] += r.amount
  }
  return Object.entries(groups).filter(([, v]) => v).map(([label, value]) => ({ label, value }))
})

// Arrears by age (how long unpaid rent has been overdue)
const arrears = computed(() => {
  const b = [
    { label: '1–30 days', value: 0 },
    { label: '31–60 days', value: 0 },
    { label: '61–90 days', value: 0 },
    { label: 'Over 90 days', value: 0 },
  ]
  for (const x of rental.payments.filter((y) => y.status === 'overdue')) {
    const d = days(x.dueDate, today)
    b[d <= 30 ? 0 : d <= 60 ? 1 : d <= 90 ? 2 : 3].value += x.balance
  }
  return b
})

// ── Places ──
const occupiedSet = computed(() => new Set(rental.tenants.filter((t) => t.propertyId).map((t) => t.propertyId)))
const rents = computed(() => rental.properties.map((x) => x.rent).filter((r) => r > 0).sort((a, b) => a - b))
const avgRent = computed(() => (rents.value.length ? Math.round(sum(rents.value, (r) => r) / rents.value.length) : 0))
const medianRent = computed(() => (rents.value.length ? rents.value[Math.floor(rents.value.length / 2)] : 0))
const rentRoll = computed(() => sum(rental.properties.filter((x) => occupiedSet.value.has(x.id)), (x) => x.rent))
const vacantLoss = computed(() => sum(rental.properties.filter((x) => !occupiedSet.value.has(x.id)), (x) => x.rent))
const occupancyByLandlord = computed(() =>
  rental.landlords
    .map((l) => {
      const mine = rental.properties.filter((x) => x.landlordId === l.id)
      return { label: l.name ?? l.email, value: pct(mine.filter((x) => occupiedSet.value.has(x.id)).length, mine.length), sub: `${mine.length} place${mine.length === 1 ? '' : 's'}` }
    })
    .filter((r) => r.sub !== '0 places')
    .sort((a, b) => b.value - a.value),
)
const topPlaces = computed(() =>
  rental.properties
    .map((x) => ({ label: rental.placeName(x.id), value: sum(rental.payments.filter((y) => y.propertyId === x.id), (y) => y.amountPaid) }))
    .filter((r) => r.value)
    .sort((a, b) => b.value - a.value),
)
const rentBands = computed(() => {
  const b = [
    { label: 'Under 200K', value: 0 },
    { label: '200K–500K', value: 0 },
    { label: '500K–1M', value: 0 },
    { label: 'Over 1M', value: 0 },
  ]
  for (const r of rents.value) b[r < 200000 ? 0 : r < 500000 ? 1 : r < 1000000 ? 2 : 3].value += 1
  return b
})

// ── People & growth ──
const joinedIn = (list, field, period) => list.filter((x) => String(x[field] ?? '').startsWith(period)).length
const growthChart = computed(() => periods.value.map((period) => ({ label: short(period), value: joinedIn(rental.tenants, 'createdAt', period) })))
const newLandlords = computed(() => joinedIn(rental.landlords, 'createdAt', thisP))
const newTenants = computed(() => joinedIn(rental.tenants, 'createdAt', thisP))
const current = computed(() => rental.tenants.filter((t) => t.propertyId))
const adoption = computed(() => pct(current.value.filter((t) => t.userId).length, current.value.length))
const managedShare = computed(() => pct(current.value.filter((t) => t.managedByLandlord).length, current.value.length))
const avgStay = computed(() => {
  const ended = rental.tenants.filter((t) => !t.propertyId && t.endedAt)
  if (!ended.length) return null
  return Math.round(sum(ended, (t) => days(t.leaseStart ?? t.createdAt, t.endedAt)) / ended.length / 30)
})
const notStarted = computed(() => current.value.filter((t) => !t.leaseEnd).length)
const ending7 = computed(() => current.value.filter((t) => t.leaseEnd && days(today, t.leaseEnd) >= 0 && days(today, t.leaseEnd) <= 7).length)
const ending30 = computed(() => current.value.filter((t) => t.leaseEnd && days(today, t.leaseEnd) >= 0 && days(today, t.leaseEnd) <= 30).length)
const expired = computed(() => current.value.filter((t) => t.leaseEnd && t.leaseEnd < today).length)

// ── Leaving ──
const moveOuts = computed(() => rental.move_out_requests.filter((m) => m.status !== 'cancelled'))
const avgRating = computed(() => {
  const rated = moveOuts.value.filter((m) => m.rating)
  return rated.length ? (sum(rated, (m) => m.rating) / rated.length).toFixed(1) : '—'
})
const reasons = computed(() => {
  const map = new Map()
  for (const m of moveOuts.value) map.set(m.reason, (map.get(m.reason) ?? 0) + 1)
  return [...map.entries()].map(([label, value]) => ({ label, value })).sort((a, b) => b.value - a.value)
})

function exportSummary() {
  const rows = [
    ['Collected all time (UGX)', p.totalCollected.value],
    ['Received this month (UGX)', thisMonth.value],
    ['Received last month (UGX)', lastMonth.value],
    ['Collection rate (%)', collectionRate.value],
    ['On-time payments (%)', onTimeRate.value],
    ['Unpaid rent (UGX)', p.outstanding.value],
    ['Monthly rent roll (UGX)', rentRoll.value],
    ['Rent lost to vacancy per month (UGX)', vacantLoss.value],
    ['Occupancy (%)', p.occupancy.value.rate],
    ['Average rent (UGX)', avgRent.value],
    ['Landlords', rental.landlords.length],
    ['Tenants renting', current.value.length],
    ['App adoption (%)', adoption.value],
    ['Months paid ahead', monthsAhead.value],
  ]
  downloadCSV(`renta-statistics-${thisP}.csv`, [{ label: 'Measure', value: (r) => r[0] }, { label: 'Value', value: (r) => r[1] }], rows)
}
</script>

<template>
  <div>
    <SuperHero eyebrow="Insights" title="Statistics" subtitle="How the whole platform is doing: money, collection, places, people and trends." tone="violet">
      <button class="btn-primary" @click="exportSummary"><Download class="size-4" /> Download summary</button>
      <template #stats>
        <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <StatTile glass label="This month" :value="formatUGX(thisMonth)" :hint="growth === null ? 'No payments last month' : `${growth >= 0 ? '+' : ''}${growth}% vs last month`" :icon="growth !== null && growth < 0 ? TrendingDown : TrendingUp" />
          <StatTile glass label="Collection rate" :value="`${collectionRate}%`" :hint="`${formatUGX(p.totalCollected.value)} of ${formatUGX(billedAll)}`" :icon="Percent" tile="tile-sky" />
          <StatTile glass label="On-time payments" :value="`${onTimeRate}%`" hint="Paid by the due date" :icon="CalendarCheck2" tile="tile-amber" />
          <StatTile glass label="App adoption" :value="`${adoption}%`" hint="Tenants using the app" :icon="Smartphone" tile="tile-violet" />
        </div>
      </template>
    </SuperHero>

    <div class="mb-5 flex items-center justify-between gap-3">
      <h2 class="section-title !mb-0">Charts show the last</h2>
      <div class="grid grid-cols-3 rounded-2xl bg-slate-100 p-1 text-sm">
        <button v-for="n in [3, 6, 12]" :key="n" type="button" class="h-9 rounded-xl px-4 font-medium transition" :class="range === n ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500'" @click="range = n">{{ n }} months</button>
      </div>
    </div>

    <!-- Money -->
    <h2 class="section-title">Money</h2>
    <div class="mb-4 grid grid-cols-2 gap-3 lg:grid-cols-4">
      <StatTile label="Collected all time" :value="formatUGX(p.totalCollected.value)" :hint="`${rental.payment_receipts.length} payments`" :icon="Wallet" />
      <StatTile label="Average payment" :value="formatUGX(avgPayment)" :hint="`${paymentsThisMonth} payments this month`" :icon="Receipt" tile="tile-sky" />
      <StatTile label="Unpaid rent" :value="formatUGX(p.outstanding.value)" :hint="`${p.overdueTenants.value} tenants overdue`" :icon="Clock" tile="tile-amber" :alert="p.outstanding.value > 0" />
      <StatTile label="Months paid ahead" :value="monthsAhead" hint="Rent already paid for later months" :icon="CalendarCheck2" tile="tile-violet" />
    </div>
    <div class="grid gap-4 lg:grid-cols-3">
      <Panel class="lg:col-span-2" title="Billed vs collected" subtitle="Each rent month: dark = collected, light = billed">
        <ColumnChart :data="billedVsCollected" value-label="Collected" ghost-label="Billed" :format="formatUGX" :tick="compactUGX" />
      </Panel>
      <Panel title="Unpaid rent by age" subtitle="How long it has been overdue">
        <RankBars :rows="arrears" :format="formatUGX" ramp :limit="4" />
      </Panel>
      <Panel title="How money comes in" subtitle="By network and cash">
        <SegmentBar :parts="networks" :format="formatUGX" />
      </Panel>
      <Panel class="lg:col-span-2" title="Top earning places" subtitle="Rent collected, all time">
        <RankBars :rows="topPlaces" :format="formatUGX" :limit="6" />
      </Panel>
    </div>

    <!-- Places -->
    <h2 class="section-title mt-8">Places</h2>
    <div class="mb-4 grid grid-cols-2 gap-3 lg:grid-cols-4">
      <StatTile label="Occupancy" :value="`${p.occupancy.value.rate}%`" :hint="`${p.occupancy.value.used} of ${p.occupancy.value.total} rented`" :icon="Building2" to="/admin2026/properties" />
      <StatTile label="Monthly rent roll" :value="formatUGX(rentRoll)" hint="From rented places" :icon="Wallet" tile="tile-sky" />
      <StatTile label="Lost to vacancy" :value="formatUGX(vacantLoss)" hint="Per month, empty places" :icon="DoorOpen" tile="tile-slate" :alert="vacantLoss > 0" to="/admin2026/properties?show=vacant" />
      <StatTile label="Average rent" :value="formatUGX(avgRent)" :hint="`Median ${formatUGX(medianRent)}`" :icon="Receipt" tile="tile-violet" />
    </div>
    <div class="grid gap-4 lg:grid-cols-2">
      <Panel title="Occupancy by landlord" subtitle="Share of their places that are rented">
        <RankBars :rows="occupancyByLandlord" :format="(v) => `${v}%`" :limit="8" />
      </Panel>
      <Panel title="Rent levels" subtitle="Number of places in each price band">
        <RankBars :rows="rentBands" :format="(v) => `${v} place${v === 1 ? '' : 's'}`" ramp :limit="4" />
      </Panel>
    </div>

    <!-- People -->
    <h2 class="section-title mt-8">People</h2>
    <div class="mb-4 grid grid-cols-2 gap-3 lg:grid-cols-4">
      <StatTile label="New this month" :value="newTenants" :hint="`tenants · ${newLandlords} new landlord${newLandlords === 1 ? '' : 's'}`" :icon="UserPlus" />
      <StatTile label="Renting now" :value="current.length" :hint="`${rental.landlords.length} landlords`" :icon="Users" tile="tile-sky" to="/admin2026/tenants" />
      <StatTile label="No smartphone" :value="`${managedShare}%`" hint="Managed by their landlord" :icon="Briefcase" tile="tile-violet" />
      <StatTile label="Average stay" :value="avgStay === null ? '—' : `${avgStay} mo`" hint="Tenants who moved out" :icon="Hourglass" tile="tile-amber" />
    </div>
    <div class="grid gap-4 lg:grid-cols-3">
      <Panel class="lg:col-span-2" title="New tenants" subtitle="Registered each month">
        <ColumnChart :data="growthChart" value-label="New tenants" :format="(v) => `${v} tenant${v === 1 ? '' : 's'}`" :tick="(v) => String(Math.round(v))" />
      </Panel>
      <Panel title="Rental time" subtitle="Where tenants are right now">
        <ul class="space-y-2.5 text-sm">
          <li v-for="r in [
            { label: 'Ends within 7 days', n: ending7, tone: 'bg-amber-50 text-amber-800' },
            { label: 'Ends within 30 days', n: ending30, tone: 'bg-sky-50 text-sky-800' },
            { label: 'Paid time ended', n: expired, tone: 'bg-red-50 text-red-800' },
            { label: 'Not paid yet (not started)', n: notStarted, tone: 'bg-slate-50 text-slate-700' },
          ]" :key="r.label" class="flex items-center justify-between rounded-xl px-3.5 py-3" :class="r.tone">
            <span class="flex items-center gap-2"><CalendarClock class="size-4" /> {{ r.label }}</span>
            <strong class="tabular-nums">{{ r.n }}</strong>
          </li>
        </ul>
      </Panel>
    </div>

    <!-- Leaving -->
    <h2 class="section-title mt-8">Moving out</h2>
    <div class="grid gap-4 lg:grid-cols-3">
      <div class="grid grid-cols-2 gap-3 lg:grid-cols-1">
        <StatTile label="Requests to leave" :value="moveOuts.length" :hint="`${moveOuts.filter((m) => m.status === 'approved').length} approved`" :icon="DoorOpen" tile="tile-slate" />
        <StatTile label="Average rating" :value="avgRating === '—' ? '—' : `${avgRating} / 5`" hint="Given by leaving tenants" :icon="Star" tile="tile-amber" />
      </div>
      <Panel class="lg:col-span-2" title="Why tenants leave" subtitle="Reasons given when asking to leave">
        <RankBars :rows="reasons" :format="(v) => `${v}`" :limit="6" />
      </Panel>
    </div>

    <p class="mt-6 text-center text-xs text-slate-400">Rent months like "{{ formatPeriod(thisP) }}" follow when rent was billed; money received follows the day it arrived.</p>
  </div>
</template>
