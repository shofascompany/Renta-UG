<script setup>
import { computed, ref } from 'vue'
import { ArrowLeft, Building2, House, Trophy, ChevronRight, ChevronDown } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useRentAnalytics, compactUGX, lastPeriods, longMonth, shortMonth, periodOf } from '@/composables/useRentAnalytics'
import { formatUGX } from '@/utils/format'
import ColumnChart from '@/components/charts/ColumnChart.vue'

// Earnings per rental business (and single house): ranked bars for the chosen period,
// tap one to see its last 6 months.
const rental = useRentalStore()
const a = useRentAnalytics()

const range = ref('all') // all | year | 6m | month
const RANGES = [['all', 'All time'], ['year', 'This year'], ['6m', '6 months'], ['month', 'This month']]
const now = new Date()
const fromPeriod = computed(
  () => ({ all: '0000-00', year: `${now.getFullYear()}-01`, '6m': lastPeriods(6)[0], month: periodOf(now) })[range.value],
)
const rangeText = computed(() => ({ all: 'since you started', year: `in ${now.getFullYear()}`, '6m': 'in the last 6 months', month: `in ${longMonth(periodOf(now))}` })[range.value])

// Each property: its houses / rooms
const places = computed(() => {
  const rentals = rental.rentals.map((r) => {
    const rooms = rental.roomsOf(r.id)
    return { key: r.id, kind: 'rental', name: r.name, to: `/landlord/rentals/${r.id}`, ids: new Set(rooms.map((p) => p.id)), units: rooms.length, occupied: rooms.filter((p) => rental.tenantForProperty(p.id)).length }
  })
  const houses = rental.properties
    .filter((p) => !p.rentalId || !rental.rentalById(p.rentalId))
    .map((p) => ({ key: p.id, kind: 'house', name: p.name, to: `/landlord/properties/${p.id}`, ids: new Set([p.id]), units: 1, occupied: rental.tenantForProperty(p.id) ? 1 : 0 }))
  return [...rentals, ...houses]
})

const received = (r) => (r.at ? periodOf(new Date(r.at)) : '')
const rows = computed(() => {
  const list = places.value.map((p) => {
    const money = a.revenue.value.filter((r) => p.ids.has(r.propertyId) && received(r) >= fromPeriod.value)
    return { ...p, value: money.reduce((s, r) => s + r.amount, 0), count: money.length }
  })
  const total = list.reduce((s, p) => s + p.value, 0)
  return list.map((p) => ({ ...p, share: total ? Math.round((p.value / total) * 100) : 0 })).sort((x, y) => y.value - x.value)
})
const total = computed(() => rows.value.reduce((s, p) => s + p.value, 0))
const max = computed(() => Math.max(1, ...rows.value.map((p) => p.value)))
const top = computed(() => (rows.value[0]?.value ? rows.value[0] : null))
const businesses = computed(() => rows.value.filter((p) => p.kind === 'rental').length)

// Tap a row → its last 6 months
const open = ref(null)
function monthsOf(p) {
  return lastPeriods(6).map((period) => ({
    label: shortMonth(period),
    full: longMonth(period),
    value: a.revenue.value.filter((r) => p.ids.has(r.propertyId) && received(r) === period).reduce((s, r) => s + r.amount, 0),
  }))
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

      <div v-if="top" class="mt-5 flex items-center gap-3 rounded-2xl bg-white/10 p-3.5 ring-1 ring-white/15 ring-inset">
        <span class="flex size-11 shrink-0 items-center justify-center rounded-xl text-amber-950" style="background: linear-gradient(140deg, #fde68a, #f59e0b)"><Trophy class="size-5" /></span>
        <div class="min-w-0 flex-1">
          <p class="text-[11px] font-semibold tracking-wider text-white/70 uppercase">Top earner</p>
          <p class="truncate font-semibold">{{ top.name }}</p>
        </div>
        <p class="shrink-0 text-lg font-bold tabular-nums">{{ compactUGX(top.value) }}</p>
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
        @click="range = r[0]"
      >{{ r[1] }}</button>
    </div>

    <!-- Ranked bar chart: one row per business; tap for its months -->
    <section class="rise mt-6" style="--d: 60ms">
      <h2 class="section-title">Earnings by rental</h2>
      <div class="sheet viz">
        <ul v-if="rows.length" class="divide-y divide-slate-100">
          <li v-for="(p, i) in rows" :key="p.key">
            <button
              type="button"
              class="group block w-full px-4 py-4 text-left transition-colors hover:bg-slate-50 sm:px-5"
              :aria-expanded="open === p.key"
              @click="open = open === p.key ? null : p.key"
            >
              <div class="flex items-center gap-3.5">
                <span class="icon-tile" :class="i === 0 && p.value ? 'tile-amber' : p.kind === 'rental' ? 'tile-teal' : 'tile-sky'">
                  <Trophy v-if="i === 0 && p.value" class="size-[1.3rem]" />
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

            <!-- Its last 6 months -->
            <div v-if="open === p.key" class="border-t border-slate-100 bg-slate-50/60 px-4 pt-4 pb-5 sm:px-5">
              <p class="mb-2 text-xs font-semibold tracking-wider text-slate-500 uppercase">{{ p.name }} · last 6 months</p>
              <ColumnChart :data="monthsOf(p)" value-label="Earned" :format="formatUGX" :tick="compactUGX" :height="190" />
              <RouterLink :to="p.to" class="btn-secondary mt-4 h-11 w-full">
                Open {{ p.kind === 'rental' ? 'rental' : 'house' }} <ChevronRight class="size-4" />
              </RouterLink>
            </div>
          </li>
        </ul>
        <p v-else class="px-5 py-14 text-center text-sm text-slate-500">Add a rental to see its earnings here.</p>
      </div>
      <p v-if="rows.length" class="mt-2 px-1 text-xs text-slate-400">Tap a rental to see its earnings month by month.</p>
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
</style>
