<script setup>
import { computed, ref } from 'vue'
import { Download, Wallet, Percent, AlertCircle, TrendingUp, Table2, BarChart3 } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useRentAnalytics, compactUGX, longMonth, downloadCSV } from '@/composables/useRentAnalytics'
import { formatUGX, formatDate, formatPeriod } from '@/utils/format'
import AdminHeader from '@/components/admin/AdminHeader.vue'
import Panel from '@/components/admin/Panel.vue'
import KpiCard from '@/components/charts/KpiCard.vue'
import ColumnChart from '@/components/charts/ColumnChart.vue'
import SegmentBar from '@/components/charts/SegmentBar.vue'
import RankBars from '@/components/charts/RankBars.vue'

// Landlord reports: income over time, how tenants pay, how late unpaid rent is, income per house.
const rental = useRentalStore()
const a = useRentAnalytics()

const range = ref(12) // months
const months = computed(() => (range.value === 12 ? a.months12.value : a.months6.value))
const totals = computed(() => {
  const billed = months.value.reduce((s, m) => s + m.billed, 0)
  const collected = months.value.reduce((s, m) => s + m.collected, 0)
  const active = months.value.filter((m) => m.billed)
  return {
    billed,
    collected,
    rate: billed ? Math.round((collected / billed) * 100) : 0,
    average: active.length ? Math.round(collected / active.length) : 0,
    best: [...months.value].sort((x, y) => y.collected - x.collected)[0],
  }
})
const chart = computed(() => months.value.map((m) => ({ label: m.label, full: longMonth(m.period), value: m.collected, ghost: m.billed })))
const view = ref('chart') // chart | table (the same numbers as a table)

const houses = computed(() =>
  a.byHouse.value.map((h) => ({ label: h.label, sub: h.occupied ? '' : 'vacant', value: h.value })),
)
const aging = computed(() => a.aging.value.map((b) => ({ label: b.label, sub: b.count ? `${b.count} charge${b.count === 1 ? '' : 's'}` : '', value: b.value })))

// ── Exports ──
const stamp = () => new Date().toLocaleDateString('en-CA')
function exportMonthly() {
  downloadCSV(`renta-monthly-report-${stamp()}.csv`, [
    { label: 'Month', value: (m) => longMonth(m.period) },
    { label: 'Billed (UGX)', value: (m) => m.billed },
    { label: 'Collected (UGX)', value: (m) => m.collected },
    { label: 'Unpaid (UGX)', value: (m) => m.billed - m.collected },
    { label: 'Collection rate (%)', value: (m) => m.rate },
  ], months.value)
}
function exportPayments() {
  const rows = [...rental.payments].sort((x, y) => y.period.localeCompare(x.period))
  downloadCSV(`renta-payments-${stamp()}.csv`, [
    { label: 'Month', value: (p) => formatPeriod(p.period) },
    { label: 'Tenant', value: (p) => rental.tenantById(p.tenantId)?.name ?? '' },
    { label: 'House', value: (p) => rental.placeName(p.propertyId) },
    { label: 'Rent (UGX)', value: (p) => p.amount },
    { label: 'Paid (UGX)', value: (p) => p.amountPaid },
    { label: 'Balance (UGX)', value: (p) => p.balance },
    { label: 'Due date', value: (p) => p.dueDate },
    { label: 'Paid on', value: (p) => (p.paidAt ? formatDate(p.paidAt) : '') },
    { label: 'Method', value: (p) => p.method ?? '' },
    { label: 'Reference', value: (p) => p.reference ?? '' },
    { label: 'Status', value: (p) => p.status },
  ], rows)
}
function exportHouses() {
  downloadCSV(`renta-income-by-house-${stamp()}.csv`, [
    { label: 'House', value: (h) => h.label },
    { label: 'Collected (UGX)', value: (h) => h.value },
    { label: 'Unpaid (UGX)', value: (h) => h.owed },
    { label: 'Occupied', value: (h) => (h.occupied ? 'Yes' : 'No') },
  ], a.byHouse.value)
}
</script>

<template>
  <div class="mx-auto max-w-6xl">
    <AdminHeader eyebrow="Statistics" title="Reports" subtitle="Your rental income, how tenants pay and where money is owed.">
      <div class="range-switch flex rounded-lg border border-slate-200 bg-white p-0.5 text-sm">
        <button
          v-for="r in [6, 12]"
          :key="r"
          class="h-9 flex-1 rounded-md px-3 font-medium transition"
          :class="range === r ? 'bg-slate-900 text-white' : 'text-slate-600 hover:text-slate-900'"
          @click="range = r"
        >{{ r }} months</button>
      </div>
      <button class="btn-secondary h-10" @click="exportMonthly"><Download class="size-4" /> Export</button>
    </AdminHeader>

    <!-- Period totals -->
    <div class="kpi-row">
      <KpiCard :label="`Collected · ${range} months`" :value="formatUGX(totals.collected)" :icon="Wallet" tone="emerald" :trend="months.map((m) => m.collected)" />
      <KpiCard label="Collection rate" :value="`${totals.rate}%`" :icon="Percent" tone="sky" :hint="`of ${formatUGX(totals.billed)} billed`" />
      <KpiCard label="Average per month" :value="formatUGX(totals.average)" :icon="TrendingUp" tone="brand" :hint="totals.best?.collected ? `Best: ${longMonth(totals.best.period)}` : 'No income yet'" />
      <KpiCard label="Unpaid now" :value="formatUGX(a.outstanding.value)" :icon="AlertCircle" tone="red" :hint="`${formatUGX(a.overdueTotal.value)} overdue`" />
    </div>

    <!-- Income over time -->
    <Panel class="mt-6" title="Billed vs collected" :subtitle="`Rent per month · last ${range} months`">
      <template #action>
        <div class="flex rounded-lg bg-slate-100 p-0.5 text-xs">
          <button class="flex h-7 items-center gap-1 rounded-md px-2.5 font-medium" :class="view === 'chart' ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500'" @click="view = 'chart'"><BarChart3 class="size-3.5" /> Chart</button>
          <button class="flex h-7 items-center gap-1 rounded-md px-2.5 font-medium" :class="view === 'table' ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500'" @click="view = 'table'"><Table2 class="size-3.5" /> Table</button>
        </div>
      </template>
      <ColumnChart v-if="view === 'chart'" :data="chart" value-label="Collected" ghost-label="Billed" :format="formatUGX" :tick="compactUGX" :height="260" />
      <div v-else class="-mx-5 -my-5 overflow-x-auto">
        <table class="min-w-full text-sm">
          <thead class="bg-slate-50 text-left text-xs font-semibold tracking-wide text-slate-500 uppercase">
            <tr><th class="px-5 py-3">Month</th><th class="px-5 py-3 text-right">Billed</th><th class="px-5 py-3 text-right">Collected</th><th class="px-5 py-3 text-right">Unpaid</th><th class="px-5 py-3 text-right">Rate</th></tr>
          </thead>
          <tbody class="divide-y divide-slate-100 tabular-nums">
            <tr v-for="m in [...months].reverse()" :key="m.period">
              <td class="px-5 py-3 font-medium text-slate-900">{{ longMonth(m.period) }}</td>
              <td class="px-5 py-3 text-right text-slate-600">{{ formatUGX(m.billed) }}</td>
              <td class="px-5 py-3 text-right font-medium text-slate-900">{{ formatUGX(m.collected) }}</td>
              <td class="px-5 py-3 text-right text-slate-600">{{ formatUGX(m.billed - m.collected) }}</td>
              <td class="px-5 py-3 text-right font-semibold" :class="m.rate >= 90 ? 'text-emerald-700' : m.rate >= 60 ? 'text-slate-900' : 'text-red-600'">{{ m.billed ? `${m.rate}%` : '—' }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </Panel>

    <div class="mt-6 grid gap-6 lg:grid-cols-2">
      <Panel title="How tenants pay" subtitle="Share of all money received">
        <SegmentBar :parts="a.methods.value" :format="formatUGX" />
      </Panel>

      <Panel title="Unpaid rent by age" subtitle="How late the money owed is">
        <RankBars :rows="aging" :format="formatUGX" ramp :limit="5" />
      </Panel>

      <Panel class="lg:col-span-2" title="Income per house" subtitle="Everything collected so far">
        <template #action>
          <button class="inline-flex items-center gap-1 text-xs font-semibold text-brand-700 hover:text-brand-600" @click="exportHouses"><Download class="size-3.5" /> CSV</button>
        </template>
        <RankBars :rows="houses" :format="formatUGX" :limit="12" />
      </Panel>
    </div>

    <!-- Downloads -->
    <Panel class="mt-6" title="Download your data" subtitle="CSV files open in Excel or Google Sheets">
      <div class="grid gap-3 sm:grid-cols-3">
        <button v-for="d in [
          { label: 'Monthly report', sub: `Billed, collected, rate · ${range} months`, run: exportMonthly },
          { label: 'All payments', sub: `${rental.payments.length} rent charges with status`, run: exportPayments },
          { label: 'Income per house', sub: `${rental.properties.length} houses`, run: exportHouses },
        ]" :key="d.label" class="flex items-center gap-3 rounded-xl border border-slate-200 p-4 text-left transition hover:border-brand-200 hover:bg-brand-50/40" @click="d.run">
          <span class="icon-disc disc-brand"><Download class="size-5" /></span>
          <span class="min-w-0">
            <span class="block font-semibold text-slate-900">{{ d.label }}</span>
            <span class="block truncate text-xs text-slate-500">{{ d.sub }}</span>
          </span>
        </button>
      </div>
    </Panel>
  </div>
</template>
