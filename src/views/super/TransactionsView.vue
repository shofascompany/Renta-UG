<script setup>
import { computed, ref } from 'vue'
import { Search, Download, ArrowDownLeft, Banknote, Smartphone, Wallet, Receipt } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { usePlatformStats } from '@/composables/usePlatformStats'
import { downloadCSV } from '@/composables/useRentAnalytics'
import { formatUGX, formatDate } from '@/utils/format'
import SuperHero from '@/components/super/SuperHero.vue'
import StatTile from '@/components/super/StatTile.vue'
import ListRow from '@/components/admin/ListRow.vue'

// Main admin: every amount received on the platform (mobile money and confirmed cash), filterable + CSV.
const rental = useRentalStore()
const p = usePlatformStats()
const query = ref('')
const method = ref('all') // all | mobile | cash
const landlordFilter = ref('')
const month = ref('') // YYYY-MM or ''
const isCash = (r) => /cash/i.test(r.method ?? '')
const tenantName = (id) => rental.tenantById(id)?.name ?? 'Tenant'

const months = computed(() => [...new Set(rental.payment_receipts.map((r) => String(r.receivedAt).slice(0, 7)))].sort().reverse())
const monthLabel = (m) => new Date(`${m}-01T00:00:00`).toLocaleDateString('en-GB', { month: 'long', year: 'numeric' })

const list = computed(() => {
  const q = query.value.trim().toLowerCase()
  return p.recentReceipts.value
    .filter((r) => method.value === 'all' || (method.value === 'cash') === isCash(r))
    .filter((r) => !landlordFilter.value || r.landlordId === landlordFilter.value)
    .filter((r) => !month.value || String(r.receivedAt).startsWith(month.value))
    .filter((r) => !q || `${tenantName(r.tenantId)} ${p.landlordName(r.landlordId)} ${r.reference ?? ''} ${r.method}`.toLowerCase().includes(q))
})
const total = computed(() => list.value.reduce((s, r) => s + r.amount, 0))
const cashTotal = computed(() => list.value.filter(isCash).reduce((s, r) => s + r.amount, 0))
const shown = ref(40)

function exportCsv() {
  downloadCSV(`renta-transactions${month.value ? `-${month.value}` : ''}.csv`, [
    { label: 'Date', value: (r) => String(r.receivedAt).slice(0, 10) },
    { label: 'Tenant', value: (r) => tenantName(r.tenantId) },
    { label: 'Place', value: (r) => rental.placeName(rental.tenantById(r.tenantId)?.propertyId ?? rental.tenantById(r.tenantId)?.lastPropertyId) },
    { label: 'Landlord', value: (r) => p.landlordName(r.landlordId) },
    { label: 'Method', value: (r) => r.method },
    { label: 'Reference', value: (r) => r.reference ?? '' },
    { label: 'Amount (UGX)', value: (r) => r.amount },
  ], list.value)
}
</script>

<template>
  <div>
    <SuperHero eyebrow="Money" title="Transactions" subtitle="Every payment received on Renta UG: mobile money and confirmed cash." tone="sky">
      <button class="btn-primary" :disabled="!list.length" @click="exportCsv"><Download class="size-4" /> Download CSV</button>
      <template #stats>
        <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <StatTile glass label="Shown total" :value="formatUGX(total)" :hint="`${list.length} payment${list.length === 1 ? '' : 's'}`" :icon="Wallet" />
          <StatTile glass label="Mobile money" :value="formatUGX(total - cashTotal)" hint="MTN & Airtel" :icon="Smartphone" tile="tile-sky" />
          <StatTile glass label="Cash" :value="formatUGX(cashTotal)" hint="Confirmed" :icon="Banknote" tile="tile-amber" />
          <StatTile glass label="All time" :value="formatUGX(p.totalCollected.value)" hint="Rent paid" :icon="Receipt" tile="tile-violet" />
        </div>
      </template>
    </SuperHero>

    <div class="mb-4 grid gap-3 lg:grid-cols-[1fr_auto_auto_auto] lg:items-center">
      <div class="relative">
        <Search class="pointer-events-none absolute top-1/2 left-3.5 size-4 -translate-y-1/2 text-slate-400" />
        <input v-model="query" class="input pl-10" placeholder="Search tenant, landlord or reference" />
      </div>
      <div class="grid grid-cols-3 rounded-2xl bg-slate-100 p-1 text-sm lg:w-72">
        <button v-for="f in [['all', 'All'], ['mobile', 'Mobile'], ['cash', 'Cash']]" :key="f[0]" type="button" class="h-9 rounded-xl font-medium transition" :class="method === f[0] ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500'" @click="method = f[0]">{{ f[1] }}</button>
      </div>
      <select v-model="month" class="input lg:w-48">
        <option value="">All months</option>
        <option v-for="m in months" :key="m" :value="m">{{ monthLabel(m) }}</option>
      </select>
      <select v-model="landlordFilter" class="input lg:w-52">
        <option value="">All landlords</option>
        <option v-for="l in rental.landlords" :key="l.id" :value="l.id">{{ l.name }}</option>
      </select>
    </div>

    <div class="sheet">
      <ul v-if="list.length" class="divide-y divide-slate-100">
        <ListRow
          v-for="r in list.slice(0, shown)"
          :key="r.id"
          :to="`/admin2026/tenants/${r.tenantId}`"
          :title="tenantName(r.tenantId)"
          :subtitle="`${isCash(r) ? 'Cash' : r.method} · ${p.landlordName(r.landlordId)} · ${formatDate(r.receivedAt)}`"
          :value="formatUGX(r.amount)"
          :value-sub="r.reference ? String(r.reference).slice(0, 14) : ''"
          value-class="text-emerald-700"
        >
          <template #icon>
            <span class="icon-disc" :class="isCash(r) ? 'disc-amber' : 'disc-emerald'"><Banknote v-if="isCash(r)" class="size-5" /><ArrowDownLeft v-else class="size-5" /></span>
          </template>
        </ListRow>
      </ul>
      <p v-else class="px-5 py-12 text-center text-sm text-slate-500">No payments match.</p>
      <button v-if="list.length > shown" type="button" class="w-full border-t border-slate-100 py-3.5 text-sm font-semibold text-brand-700 hover:bg-slate-50" @click="shown += 40">Show more ({{ list.length - shown }} left)</button>
    </div>
  </div>
</template>
