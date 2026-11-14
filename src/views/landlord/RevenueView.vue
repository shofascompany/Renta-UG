<script setup>
import { computed, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ArrowLeft, ArrowDownLeft, Banknote, Search, Download, Hash, CalendarDays, Home, User, StickyNote, Smartphone } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useRentAnalytics, downloadCSV, longMonth, periodOf } from '@/composables/useRentAnalytics'
import { formatUGX, formatDate, formatPeriod } from '@/utils/format'
import ListRow from '@/components/admin/ListRow.vue'
import BaseModal from '@/components/BaseModal.vue'

// Every amount received, grouped by month. Tap a row for its details.
const rental = useRentalStore()
const a = useRentAnalytics()
const route = useRoute()
const router = useRouter()

const channel = ref('all') // all | Mobile money | Cash
const query = ref('')

const tenantName = (id) => rental.tenantById(id)?.name ?? 'Former tenant'
const place = (id) => (id && rental.propertyById(id) ? rental.placeName(id) : 'Removed house')

const list = computed(() => {
  const q = query.value.trim().toLowerCase()
  return a.revenue.value
    .filter((r) => channel.value === 'all' || r.channel === channel.value)
    .filter((r) => !q || `${tenantName(r.tenantId)} ${place(r.propertyId)} ${r.reference ?? ''} ${r.method ?? ''}`.toLowerCase().includes(q))
})
const total = computed(() => list.value.reduce((s, r) => s + r.amount, 0))

const groups = computed(() => {
  const map = new Map()
  for (const r of list.value) {
    const key = r.at ? periodOf(new Date(r.at)) : 'unknown'
    if (!map.has(key)) map.set(key, { key, label: key === 'unknown' ? 'Date unknown' : longMonth(key), rows: [], total: 0 })
    const g = map.get(key)
    g.rows.push(r)
    g.total += r.amount
  }
  return [...map.values()]
})

const counts = computed(() => ({
  all: a.revenue.value.length,
  'Mobile money': a.channels.value[0].count,
  Cash: a.channels.value[1].count,
}))

// Details sheet (also opened from the overview with ?open=<id>)
const openId = ref(route.query.open ?? null)
const open = computed(() => a.revenue.value.find((r) => r.id === openId.value) ?? null)
watch(openId, (id) => {
  if (!id && route.query.open) router.replace({ query: {} })
})

const time = (d) => (d ? new Date(d).toLocaleString('en-GB', { day: 'numeric', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : '—')

function exportCSV() {
  downloadCSV(`renta-revenue-${new Date().toLocaleDateString('en-CA')}.csv`, [
    { label: 'Date', value: (r) => (r.at ? new Date(r.at).toLocaleString('en-GB') : '') },
    { label: 'Tenant', value: (r) => tenantName(r.tenantId) },
    { label: 'House / room', value: (r) => place(r.propertyId) },
    { label: 'Rent month', value: (r) => (r.period ? formatPeriod(r.period) : '') },
    { label: 'Amount (UGX)', value: (r) => r.amount },
    { label: 'Paid by', value: (r) => r.channel },
    { label: 'Method', value: (r) => r.method ?? '' },
    { label: 'Reference', value: (r) => r.reference ?? '' },
  ], list.value)
}
</script>

<template>
  <div class="mx-auto max-w-4xl">
    <RouterLink to="/landlord" class="mb-4 inline-flex items-center gap-1.5 py-1 text-sm font-medium text-slate-500 hover:text-slate-900">
      <ArrowLeft class="size-4" /> Overview
    </RouterLink>

    <section class="page-hero rise px-5 py-6 sm:px-8 sm:py-7">
      <p class="text-xs font-semibold tracking-[0.14em] text-white/70 uppercase">Transactions</p>
      <p class="mt-3 text-sm text-white/80">{{ channel === 'all' ? 'Total collected' : `Collected by ${channel.toLowerCase()}` }}</p>
      <p class="mt-1 text-4xl font-bold tracking-tight tabular-nums">{{ formatUGX(total) }}</p>
      <p class="mt-1 text-sm text-white/70">{{ list.length }} payment{{ list.length === 1 ? '' : 's' }}</p>
      <div class="mt-5 grid grid-cols-2 gap-2 sm:max-w-md">
        <div class="hero-stat"><p class="hero-stat-label">Mobile money</p><p class="hero-stat-value text-base">{{ formatUGX(a.channels.value[0].value) }}</p></div>
        <div class="hero-stat"><p class="hero-stat-label">Cash</p><p class="hero-stat-value text-base">{{ formatUGX(a.channels.value[1].value) }}</p></div>
      </div>
    </section>

    <!-- Filters -->
    <div class="mt-5 flex flex-col gap-3 sm:flex-row sm:items-center">
      <div class="relative flex-1">
        <Search class="pointer-events-none absolute top-1/2 left-3.5 size-4 -translate-y-1/2 text-slate-400" />
        <input v-model="query" class="input h-11 rounded-xl bg-white pl-10" placeholder="Search tenant, house or reference" />
      </div>
      <div class="flex gap-2">
        <div class="grid flex-1 grid-cols-3 rounded-xl bg-slate-100 p-1 text-sm sm:flex-none">
          <button
            v-for="f in [['all', 'All'], ['Mobile money', 'Mobile'], ['Cash', 'Cash']]"
            :key="f[0]"
            class="h-9 rounded-lg px-3 font-medium transition"
            :class="channel === f[0] ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500'"
            @click="channel = f[0]"
          >{{ f[1] }} <span class="text-xs opacity-60">{{ counts[f[0]] }}</span></button>
        </div>
        <button class="btn-secondary h-11 shrink-0 rounded-xl" :disabled="!list.length" aria-label="Download CSV" @click="exportCSV"><Download class="size-4" /><span class="hidden sm:inline">CSV</span></button>
      </div>
    </div>

    <!-- Months -->
    <section v-for="(g, gi) in groups" :key="g.key" class="rise mt-6" :style="{ '--d': `${80 + gi * 40}ms` }">
      <div class="mb-2.5 flex items-baseline justify-between px-1">
        <h2 class="text-xs font-semibold tracking-[0.12em] text-slate-500 uppercase">{{ g.label }}</h2>
        <p class="text-sm font-semibold text-slate-900 tabular-nums">{{ formatUGX(g.total) }}</p>
      </div>
      <div class="sheet">
        <ul class="divide-y divide-slate-100">
          <ListRow
            v-for="r in g.rows"
            :key="r.id"
            :title="tenantName(r.tenantId)"
            :subtitle="`${place(r.propertyId)} · ${formatDate(r.at)}`"
            :value="formatUGX(r.amount)"
            :value-sub="r.channel === 'Cash' ? 'Cash' : r.method || 'Mobile money'"
            value-class="text-emerald-700"
            @click="openId = r.id"
          >
            <template #icon>
              <span class="icon-disc" :class="r.channel === 'Cash' ? 'disc-amber' : 'disc-emerald'">
                <Banknote v-if="r.channel === 'Cash'" class="size-5" />
                <ArrowDownLeft v-else class="size-5" />
              </span>
            </template>
          </ListRow>
        </ul>
      </div>
    </section>

    <div v-if="!groups.length" class="sheet mt-6 px-6 py-14 text-center">
      <p class="font-semibold text-slate-900">{{ a.revenue.value.length ? 'No payments match' : 'No revenue yet' }}</p>
      <p class="mt-1 text-sm text-slate-500">{{ a.revenue.value.length ? 'Try another search or filter.' : 'Payments from tenants appear here as they come in.' }}</p>
    </div>

    <!-- Details -->
    <BaseModal :model-value="Boolean(open)" title="Payment details" width="max-w-md" @update:model-value="!$event && (openId = null)">
      <div v-if="open" class="space-y-5">
        <div class="rounded-2xl px-5 py-5 text-center text-white" style="background: linear-gradient(135deg, #14918a, #0a3b38)">
          <p class="text-xs font-semibold tracking-wider text-white/70 uppercase">Received</p>
          <p class="mt-1 text-3xl font-bold tabular-nums">{{ formatUGX(open.amount) }}</p>
          <p class="mt-1 inline-flex items-center gap-1.5 text-sm text-white/80">
            <Banknote v-if="open.channel === 'Cash'" class="size-4" /><Smartphone v-else class="size-4" />
            {{ open.channel === 'Cash' ? 'Cash' : open.method || 'Mobile money' }}
          </p>
        </div>
        <dl class="divide-y divide-slate-100 text-sm">
          <div class="flex items-center gap-3 py-3"><User class="size-4 text-slate-400" /><dt class="flex-1 text-slate-500">Tenant</dt><dd class="font-medium text-slate-900">{{ tenantName(open.tenantId) }}</dd></div>
          <div class="flex items-center gap-3 py-3"><Home class="size-4 text-slate-400" /><dt class="flex-1 text-slate-500">House / room</dt><dd class="text-right font-medium text-slate-900">{{ place(open.propertyId) }}</dd></div>
          <div v-if="open.period" class="flex items-center gap-3 py-3"><CalendarDays class="size-4 text-slate-400" /><dt class="flex-1 text-slate-500">Rent for</dt><dd class="font-medium text-slate-900">{{ formatPeriod(open.period) }}</dd></div>
          <div class="flex items-center gap-3 py-3"><CalendarDays class="size-4 text-slate-400" /><dt class="flex-1 text-slate-500">Date</dt><dd class="text-right font-medium text-slate-900">{{ time(open.at) }}</dd></div>
          <div v-if="open.reference" class="flex items-center gap-3 py-3"><Hash class="size-4 text-slate-400" /><dt class="flex-1 text-slate-500">Reference</dt><dd class="font-mono text-xs font-medium text-slate-900">{{ open.reference }}</dd></div>
          <div v-if="open.note" class="flex items-start gap-3 py-3"><StickyNote class="mt-0.5 size-4 text-slate-400" /><dt class="flex-1 text-slate-500">Note</dt><dd class="max-w-[60%] text-right text-slate-900">{{ open.note }}</dd></div>
        </dl>
        <RouterLink v-if="open.propertyId && rental.propertyById(open.propertyId)" :to="`/landlord/properties/${open.propertyId}`" class="btn-secondary h-11 w-full">Open the house</RouterLink>
      </div>
    </BaseModal>
  </div>
</template>
