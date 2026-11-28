<script setup>
import { computed, ref } from 'vue'
import { ArrowLeft, Building2, House, Trophy, ChevronRight, ChevronDown, Search, SlidersHorizontal, Check, BarChart3, LineChart, X } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useFilter } from '@/composables/useFilter'
import { searcher } from '@/lib/search'
import { useRentAnalytics, compactUGX, lastPeriods, longMonth, shortMonth, periodOf } from '@/composables/useRentAnalytics'
import { formatUGX, formatDate, millionsUGX, dayOf } from '@/utils/format'
import ColumnChart from '@/components/charts/ColumnChart.vue'
import DropMenu from '@/components/admin/DropMenu.vue'
import EmptyState from '@/components/EmptyState.vue'

// Earnings per rental business (and single house). Every filter works on everything on the page: the period (all
// time, this year, 6 months, this month) sets the totals, the top earner, the ranking and both graphs; the search and
// the filter button choose which rentals are shown (and graphed). Graphs as bars or as a line.
const rental = useRentalStore()
const a = useRentAnalytics()

const range = useFilter('range', 'all', ['all', 'year', '6m', 'month'])
const RANGES = [['all', 'All time'], ['year', 'This year'], ['6m', '6 months'], ['month', 'This month']]
const kind = useFilter('kind', 'all', ['all', 'rental', 'house'])
const KINDS = [['all', 'All', 'Rentals and houses'], ['rental', 'Rental businesses', 'With rooms'], ['house', 'Single houses', 'One house each']]
const order = useFilter('order', 'most', ['most', 'least', 'az'])
const ORDERS = [['most', 'Earned the most'], ['least', 'Earned the least'], ['az', 'Name A–Z']]
const query = useFilter('q', '')
const chart = useFilter('chart', 'bar', ['bar', 'line'])
const filtered = computed(() => kind.value !== 'all' || order.value !== 'most')

const now = new Date()
const today = dayOf(now)
const thisPeriod = periodOf(now)
const rangeText = computed(() => ({ all: 'since you started', year: `in ${now.getFullYear()}`, '6m': 'in the last 6 months', month: `in ${longMonth(thisPeriod)}` })[range.value])

// Each property: its houses / rooms
const places = computed(() => {
  const rentals = rental.rentals.map((r) => {
    const rooms = rental.roomsOf(r.id)
    return { key: r.id, kind: 'rental', name: r.name, location: r.location, rooms: rooms.map((p) => p.name), to: `/landlord/rentals/${r.id}`, ids: new Set(rooms.map((p) => p.id)), units: rooms.length, occupied: rooms.filter((p) => rental.tenantForProperty(p.id)).length }
  })
  const houses = rental.properties
    .filter((p) => !p.rentalId || !rental.rentalById(p.rentalId))
    .map((p) => ({ key: p.id, kind: 'house', name: p.name, location: p.location, rooms: [], to: `/landlord/properties/${p.id}`, ids: new Set([p.id]), units: 1, occupied: rental.tenantForProperty(p.id) ? 1 : 0 }))
  return [...rentals, ...houses]
})

// ── The period: its buckets (days of this month, or months) and which money falls in it ──
const dayLabel = (d) => String(Number(d.slice(8, 10)))
const buckets = computed(() => {
  if (range.value === 'month') {
    const days = []
    for (let d = 1; d <= now.getDate(); d++) days.push(`${thisPeriod}-${String(d).padStart(2, '0')}`)
    return days.map((day) => ({ key: day, label: dayLabel(day), full: formatDate(`${day}T12:00:00`) }))
  }
  let periods
  if (range.value === '6m') periods = lastPeriods(6)
  else if (range.value === 'year') periods = lastPeriods(now.getMonth() + 1)
  else {
    // All time: from the first money in (at least 6 months)
    const first = a.revenue.value.map((r) => (r.at ? periodOf(new Date(r.at)) : '')).filter(Boolean).sort()[0] ?? thisPeriod
    const [y, m] = first.split('-').map(Number)
    const count = (now.getFullYear() - y) * 12 + (now.getMonth() + 1 - m) + 1
    periods = lastPeriods(Math.max(6, count))
  }
  const years = new Set(periods.map((p) => p.slice(0, 4))).size > 1
  return periods.map((p) => ({ key: p, label: years ? `${shortMonth(p)} ${p.slice(2, 4)}` : shortMonth(p), full: longMonth(p) }))
})
const bucketOf = (r) => (!r.at ? '' : range.value === 'month' ? dayOf(r.at) : periodOf(new Date(r.at)))
const first = computed(() => buckets.value[0]?.key ?? '')
// In the period, up to today
const inRange = (r) => {
  if (range.value === 'all') return true
  const b = bucketOf(r)
  return Boolean(b) && b >= first.value && b <= (range.value === 'month' ? today : thisPeriod)
}

// Every place with what it earned in the period
const rows = computed(() => {
  const list = places.value.map((p) => {
    const money = a.revenue.value.filter((r) => p.ids.has(r.propertyId) && inRange(r))
    return { ...p, value: money.reduce((s, r) => s + r.amount, 0), count: money.length }
  })
  const total = list.reduce((s, p) => s + p.value, 0)
  return list.map((p) => ({ ...p, share: total ? Math.round((p.value / total) * 100) : 0 })).sort((x, y) => y.value - x.value)
})
const total = computed(() => rows.value.reduce((s, p) => s + p.value, 0))
const top = computed(() => (rows.value[0]?.value ? rows.value[0] : null))
const businesses = computed(() => rows.value.filter((p) => p.kind === 'rental').length)

// What the search and the filter button leave, in the chosen order
const shown = computed(() => {
  const hit = searcher(query.value)
  const list = rows.value.filter((p) => (kind.value === 'all' || p.kind === kind.value) && hit(p.name, p.location, ...p.rooms))
  if (order.value === 'least') return [...list].sort((x, y) => x.value - y.value || x.name.localeCompare(y.name))
  if (order.value === 'az') return [...list].sort((x, y) => x.name.localeCompare(y.name))
  return list
})
const shownTotal = computed(() => shown.value.reduce((s, p) => s + p.value, 0))
const max = computed(() => Math.max(1, ...shown.value.map((p) => p.value)))
const narrowed = computed(() => shown.value.length !== rows.value.length)

// The graph: money in per day / month of the period, for the places shown (or for one place)
function seriesOf(ids) {
  const sums = Object.fromEntries(buckets.value.map((b) => [b.key, 0]))
  for (const r of a.revenue.value) {
    if (!ids.has(r.propertyId)) continue
    const b = bucketOf(r)
    if (b in sums) sums[b] += r.amount
  }
  return buckets.value.map((b) => ({ label: b.label, full: b.full, value: sums[b.key] }))
}
const series = computed(() => seriesOf(new Set(shown.value.flatMap((p) => [...p.ids]))))
const graphTitle = computed(() => (range.value === 'month' ? 'Money in, day by day' : 'Money in, month by month'))

// Tap a row → its own graph
const open = ref(null)
function clearFilters() {
  query.value = ''
  kind.value = 'all'
  order.value = 'most'
}
</script>

<template>
  <div class="mx-auto max-w-4xl">
    <RouterLink to="/landlord" class="mb-4 inline-flex items-center gap-1.5 py-1 text-sm font-medium text-slate-500 hover:text-slate-900">
      <ArrowLeft class="size-4" /> Overview
    </RouterLink>

    <!-- Summary -->
    <section class="page-hero rise px-5 py-6 sm:px-8 sm:py-7">
      <p class="text-xs font-semibold tracking-[0.14em] text-white/70 uppercase">Earnings</p>
      <h1 class="mt-2 text-2xl font-bold tracking-tight sm:text-3xl">Your rental businesses</h1>
      <p class="mt-1 text-sm text-white/80">{{ formatUGX(total) }} earned {{ rangeText }} · {{ businesses }} rental{{ businesses === 1 ? '' : 's' }}{{ rows.length > businesses ? ` · ${rows.length - businesses} house${rows.length - businesses === 1 ? '' : 's'}` : '' }}</p>

      <div v-if="top" class="mt-5 flex items-center gap-3 rounded-2xl bg-white/10 p-3.5 ring-1 ring-white/15 ring-inset" data-top-earner>
        <span class="flex size-11 shrink-0 items-center justify-center rounded-xl text-amber-950" style="background: linear-gradient(140deg, #fbbf24, #d97706)"><Trophy class="size-5" /></span>
        <div class="min-w-0 flex-1">
          <p class="text-[11px] font-semibold tracking-wider text-white/70 uppercase">Top earner</p>
          <p class="truncate font-semibold">{{ top.name }}</p>
        </div>
        <!-- Exact to the thousand, like Total revenue on the overview -->
        <p class="top-money shrink-0 text-lg font-bold tabular-nums" :title="formatUGX(top.value)"><span class="top-cur">UGX</span> {{ millionsUGX(top.value) }}</p>
      </div>
    </section>

    <!-- Period -->
    <div class="mt-5 grid grid-cols-4 rounded-2xl bg-slate-100 p-1 text-sm" role="tablist" aria-label="Period">
      <button
        v-for="r in RANGES"
        :key="r[0]"
        role="tab"
        :aria-selected="range === r[0]"
        class="h-10 rounded-xl px-1 font-medium transition"
        :class="range === r[0] ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500 hover:text-slate-700'"
        :data-range="r[0]"
        @click="range = r[0]; open = null"
      >{{ r[1] }}</button>
    </div>

    <!-- Search and filter -->
    <div class="mt-4 flex items-center gap-2">
      <div class="relative min-w-0 flex-1">
        <Search class="pointer-events-none absolute top-1/2 left-3.5 size-4 -translate-y-1/2 text-slate-400" />
        <input v-model="query" class="input h-11 rounded-xl bg-white pl-10" placeholder="Search a rental, house or room" aria-label="Search rentals" data-earn-search />
      </div>
      <DropMenu label="Filter" title="Show" width="w-64" trigger-class="tool-btn tool-icon" :class="filtered && 'is-on'">
        <template #trigger><SlidersHorizontal class="size-[1.15rem]" /><span v-if="filtered" class="tool-dot" /></template>
        <template #default="{ close }">
          <button v-for="k in KINDS" :key="k[0]" type="button" class="menu-item" :class="kind === k[0] && 'menu-item-on'" :data-kind="k[0]" @click="kind = k[0]; close()">
            <span class="flex-1 text-left">{{ k[1] }}<span class="menu-sub">{{ k[2] }}</span></span>
            <span v-if="kind === k[0]" class="menu-check"><Check class="size-3" stroke-width="3" /></span>
          </button>
          <p class="menu-title">Order</p>
          <button v-for="o in ORDERS" :key="o[0]" type="button" class="menu-item" :class="order === o[0] && 'menu-item-on'" :data-order="o[0]" @click="order = o[0]; close()">
            <span class="flex-1 text-left">{{ o[1] }}</span>
            <span v-if="order === o[0]" class="menu-check"><Check class="size-3" stroke-width="3" /></span>
          </button>
        </template>
      </DropMenu>
    </div>
    <p v-if="narrowed || filtered" class="mt-2 flex flex-wrap items-center gap-x-2 px-1 text-xs text-slate-500" data-earn-showing>
      Showing {{ shown.length }} of {{ rows.length }} · {{ formatUGX(shownTotal) }}
      <button type="button" class="inline-flex items-center gap-0.5 font-semibold text-brand-700" @click="clearFilters"><X class="size-3.5" /> Clear</button>
    </p>

    <!-- The graph: bars or a line -->
    <section class="rise mt-6" style="--d: 40ms">
      <div class="mb-2.5 flex items-center justify-between gap-3">
        <h2 class="section-title mb-0">{{ graphTitle }}</h2>
        <div class="flex rounded-lg bg-slate-100 p-0.5 text-xs" role="group" aria-label="Graph">
          <button type="button" class="flex h-8 items-center gap-1 rounded-md px-2.5 font-medium" :class="chart === 'bar' ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500'" :aria-pressed="chart === 'bar'" data-chart-bar @click="chart = 'bar'"><BarChart3 class="size-3.5" /> Bars</button>
          <button type="button" class="flex h-8 items-center gap-1 rounded-md px-2.5 font-medium" :class="chart === 'line' ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500'" :aria-pressed="chart === 'line'" data-chart-line @click="chart = 'line'"><LineChart class="size-3.5" /> Line</button>
        </div>
      </div>
      <div class="sheet p-4 sm:p-5">
        <ColumnChart :data="series" :type="chart" value-label="Earned" :format="formatUGX" :tick="compactUGX" :height="220" />
        <p class="mt-2 text-xs text-slate-500">{{ formatUGX(shownTotal) }} {{ rangeText }}{{ narrowed ? ` · the ${shown.length} shown` : '' }}</p>
      </div>
    </section>

    <!-- Ranked: one row per business; tap for its own graph -->
    <section class="rise mt-6" style="--d: 60ms">
      <h2 class="section-title">Earnings by rental</h2>
      <div class="sheet viz">
        <ul v-if="shown.length" class="divide-y divide-slate-100" data-earn-rows>
          <li v-for="p in shown" :key="p.key">
            <button
              type="button"
              class="group block w-full px-4 py-4 text-left transition-colors hover:bg-slate-50 sm:px-5"
              :aria-expanded="open === p.key"
              @click="open = open === p.key ? null : p.key"
            >
              <div class="flex items-center gap-3.5">
                <span class="icon-tile" :class="top && p.key === top.key ? 'tile-amber' : p.kind === 'rental' ? 'tile-teal' : 'tile-sky'">
                  <Trophy v-if="top && p.key === top.key" class="size-[1.3rem]" />
                  <Building2 v-else-if="p.kind === 'rental'" class="size-[1.3rem]" />
                  <House v-else class="size-[1.3rem]" />
                </span>
                <div class="min-w-0 flex-1">
                  <div class="flex items-baseline justify-between gap-3">
                    <p class="truncate font-semibold text-slate-900">{{ p.name }}</p>
                    <p class="shrink-0 font-bold text-slate-900 tabular-nums">{{ formatUGX(p.value) }}</p>
                  </div>
                  <div class="mt-2 flex items-center gap-3">
                    <div class="h-2.5 flex-1 overflow-hidden rounded-full" style="background: var(--series-track)">
                      <div
                        class="bar h-full rounded-full"
                        :style="{ width: `${p.value ? Math.max(3, (p.value / max) * 100) : 0}%`, background: 'var(--series-1)' }"
                      />
                    </div>
                    <span class="w-9 shrink-0 text-right text-xs font-medium text-slate-500 tabular-nums">{{ p.share }}%</span>
                  </div>
                  <p class="mt-1.5 text-xs text-slate-500">
                    {{ p.kind === 'rental' ? `${p.units} room${p.units === 1 ? '' : 's'} · ${p.occupied} occupied` : p.occupied ? 'Occupied' : 'Vacant' }}
                    · {{ p.count }} payment{{ p.count === 1 ? '' : 's' }}
                  </p>
                </div>
                <ChevronDown class="size-4 shrink-0 text-slate-300 transition group-hover:text-slate-500" :class="open === p.key && 'rotate-180'" />
              </div>
            </button>

            <!-- Its own graph, for the same period -->
            <div v-if="open === p.key" class="border-t border-slate-100 bg-slate-50/60 px-4 pt-4 pb-5 sm:px-5">
              <p class="mb-2 text-xs font-semibold tracking-wider text-slate-500 uppercase">{{ p.name }} · {{ RANGES.find((r) => r[0] === range)[1].toLowerCase() }}</p>
              <ColumnChart :data="seriesOf(p.ids)" :type="chart" value-label="Earned" :format="formatUGX" :tick="compactUGX" :height="190" />
              <RouterLink :to="p.to" class="btn-secondary mt-4 h-11 w-full">
                Open {{ p.kind === 'rental' ? 'rental' : 'house' }} <ChevronRight class="size-4" />
              </RouterLink>
            </div>
          </li>
        </ul>
        <EmptyState v-else-if="rows.length" kind="money" title="Nothing matches" text="Try another search or filter." />
        <EmptyState v-else kind="money" title="No earnings yet" text="Add a rental to see its earnings here." to="/landlord/properties" action="My properties" />
      </div>
      <p v-if="shown.length" class="mt-2 px-1 text-xs text-slate-400">Tap a rental to see its own graph for this period.</p>
    </section>
  </div>
</template>

<style scoped>
.bar {
  animation: grow 0.8s cubic-bezier(0.22, 1, 0.36, 1) backwards;
  transform-origin: left;
}
@keyframes grow {
  from { transform: scaleX(0); }
}
@media (prefers-reduced-motion: reduce) {
  .bar { animation: none; }
}
.top-cur { margin-right: 0.1rem; font-size: 0.65em; font-weight: 700; letter-spacing: 0.04em; color: #fde68a; }
/* Toolbar button (filter), as on Payments */
:deep(.tool-btn) {
  position: relative;
  display: inline-flex;
  height: 2.75rem;
  min-width: 2.75rem;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  border-radius: 0.875rem;
  border: 1px solid var(--color-slate-200);
  background: var(--color-white);
  padding: 0 0.85rem;
  font-size: 0.875rem;
  font-weight: 500;
  color: var(--color-slate-700);
  transition: background-color 0.15s ease, border-color 0.15s ease;
}
:deep(.tool-btn:hover) { background: var(--color-slate-50); }
:deep(.tool-btn[aria-expanded='true']) { border-color: var(--color-brand-200); background: var(--color-brand-50); color: var(--color-brand-700); }
:deep(.tool-icon) { padding: 0; }
.is-on :deep(.tool-btn) { border-color: var(--color-brand-200); color: var(--color-brand-700); }
.tool-dot {
  position: absolute;
  top: 0.45rem;
  right: 0.45rem;
  width: 0.5rem;
  height: 0.5rem;
  border-radius: 9999px;
  background: var(--color-brand-600);
  box-shadow: 0 0 0 2px var(--color-white);
}
</style>
