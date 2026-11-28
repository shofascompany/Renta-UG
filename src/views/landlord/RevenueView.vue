<script setup>
import { computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ArrowLeft, ArrowDownLeft, Banknote, Search, Download, ImageDown, Loader2, MessageCircle } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useFilter } from '@/composables/useFilter'
import { searcher } from '@/lib/search'
import { useReceiptDownload } from '@/composables/useReceiptDownload'
import { useRentAnalytics, downloadCSV, longMonth, periodOf } from '@/composables/useRentAnalytics'
import { formatUGX, formatDate, formatPeriod } from '@/utils/format'
import ListRow from '@/components/admin/ListRow.vue'
import EmptyState from '@/components/EmptyState.vue'

// Every amount received, grouped by month. Tap a row → the payment's own page (the whole payment, its receipt,
// WhatsApp and Reverse payment: PaymentDetailView).
const rental = useRentalStore()
const a = useRentAnalytics()
const { saving, saveRevenue, shareRevenue, canShare } = useReceiptDownload() // receipts as images, like the tenant's
const route = useRoute()
const router = useRouter()

const channel = useFilter('by', 'all', ['all', 'Mobile money', 'Cash'])
const query = useFilter('q', '')

const tenantName = (id) => rental.tenantById(id)?.name ?? 'Former tenant'
const place = (id) => (id && rental.propertyById(id) ? rental.placeName(id) : 'Removed house')

const found = computed(() => {
  const hit = searcher(query.value)
  return a.revenue.value.filter((r) =>
    hit(tenantName(r.tenantId), rental.tenantById(r.tenantId)?.phone, place(r.propertyId), r.reference, r.method, r.note, r.period && formatPeriod(r.period), formatDate(r.at), String(r.amount), formatUGX(r.amount)),
  )
})
const list = computed(() => found.value.filter((r) => channel.value === 'all' || r.channel === channel.value))
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
  all: found.value.length,
  'Mobile money': found.value.filter((r) => r.channel === 'Mobile money').length,
  Cash: found.value.filter((r) => r.channel === 'Cash').length,
}))

// A payment's page: its rent month, with this payment shown first. (Money with no receipt behind it: just the month.)
const pageOf = (r) => ({ path: `/landlord/payments/${r.paymentId}`, query: String(r.id).startsWith('charge-') ? {} : { receipt: r.id } })
const openPayment = (r) => r.paymentId && router.push(pageOf(r))
// Older links (?open=<id>) go straight to that payment's page
onMounted(() => {
  const r = route.query.open && a.revenue.value.find((x) => x.id === route.query.open)
  if (r?.paymentId) router.replace(pageOf(r))
})

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
      <p class="mt-3 text-sm text-white/80">Total collected · all money received</p>
      <p class="mt-1 text-4xl font-bold tracking-tight tabular-nums">{{ formatUGX(a.totalRevenue.value) }}</p>
      <p class="mt-1 text-sm text-white/70">
        {{ a.revenue.value.length }} payment{{ a.revenue.value.length === 1 ? '' : 's' }}
        <template v-if="list.length !== a.revenue.value.length || channel !== 'all'"> · showing {{ list.length }} worth {{ formatUGX(total) }}</template>
      </p>
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
            @click="openPayment(r)"
          >
            <template #below>
              <!-- (a span: the row itself is already a button) -->
              <span role="button" tabindex="0" class="rc-link mt-1.5" :aria-label="`Download the receipt for ${formatUGX(r.amount)}`" @click.stop="saveRevenue(r)" @keydown.enter.stop.prevent="saveRevenue(r)">
                <Loader2 v-if="saving === r.id" class="size-3.5 animate-spin" /><ImageDown v-else class="size-3.5" />
                {{ saving === r.id ? 'Saving…' : 'Receipt' }}
              </span>
              <span v-if="canShare" role="button" tabindex="0" class="rc-link rc-wa mt-1.5 ml-1.5" :aria-label="`Share the receipt for ${formatUGX(r.amount)} on WhatsApp`" @click.stop="shareRevenue(r)" @keydown.enter.stop.prevent="shareRevenue(r)">
                <MessageCircle class="size-3.5" /> WhatsApp
              </span>
            </template>
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

    <div v-if="!groups.length" class="sheet mt-6"><EmptyState kind="money" :title="a.revenue.value.length ? 'No payments match' : 'No revenue yet'" :text="a.revenue.value.length ? 'Try another search or filter.' : 'Payments from tenants appear here as they come in.'" /></div>
  </div>
</template>

<style scoped>
.rc-link { display: inline-flex; align-items: center; gap: 0.3rem; border-radius: 9999px; padding: 0.15rem 0.55rem; font-size: 0.72rem; font-weight: 600; color: var(--color-brand-700); background: var(--color-brand-50); }
.rc-link:active { transform: scale(0.96); }
.rc-wa { color: #128c4a; background: #e8f8ef; }
</style>
