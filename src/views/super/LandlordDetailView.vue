<script setup>
import { computed } from 'vue'
import { ArrowLeft, Mail, Phone, Building2, Users, Wallet, TriangleAlert } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useLandlordStats } from '@/composables/useLandlordStats'
import { formatUGX, formatDate, formatPeriod } from '@/utils/format'
import StatCard from '@/components/StatCard.vue'
import StatusBadge from '@/components/StatusBadge.vue'

// Main admin: read-only view of one landlord's properties, tenants and payments.
const props = defineProps({ id: String })
const rental = useRentalStore()
const { statsFor } = useLandlordStats()

const landlord = computed(() => rental.landlords.find((l) => l.id === props.id))
const s = computed(() => statsFor(props.id))
const properties = computed(() => rental.properties.filter((p) => p.landlordId === props.id))
const tenants = computed(() => rental.tenants.filter((t) => t.landlordId === props.id))
const payments = computed(() =>
  rental.payments.filter((p) => p.landlordId === props.id).sort((a, b) => b.dueDate.localeCompare(a.dueDate)).slice(0, 15),
)

function balanceFor(tenantId) {
  return rental.duesForTenant(tenantId).reduce((sum, p) => sum + p.balance, 0)
}
function rentStatus(tenantId) {
  const dues = rental.duesForTenant(tenantId)
  return dues.some((p) => p.status === 'overdue') ? 'overdue' : dues.length ? 'pending' : 'paid'
}
</script>

<template>
  <RouterLink to="/admin2026/landlords" class="mb-6 inline-flex items-center gap-1.5 text-sm text-slate-500 hover:text-slate-900">
    <ArrowLeft class="size-4" /> Landlords
  </RouterLink>

  <div v-if="!landlord" class="py-20 text-center text-sm text-slate-500">Landlord not found.</div>

  <template v-else>
    <div class="mb-8 flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
      <div>
        <div class="flex items-center gap-2">
          <h1 class="text-2xl font-semibold tracking-tight text-slate-900">{{ landlord.name }}</h1>
          <StatusBadge :status="landlord.active ? 'active' : 'suspended'" />
        </div>
        <div class="mt-2 flex flex-wrap gap-4 text-sm text-slate-500">
          <a :href="`mailto:${landlord.email}`" class="flex items-center gap-1.5 hover:text-brand-600"><Mail class="size-4" /> {{ landlord.email }}</a>
          <a v-if="landlord.phone" :href="`tel:${landlord.phone}`" class="flex items-center gap-1.5 hover:text-brand-600"><Phone class="size-4" /> {{ landlord.phone }}</a>
          <span>Registered {{ formatDate(landlord.createdAt) }}</span>
        </div>
      </div>
    </div>

    <div class="mb-6 grid grid-cols-2 gap-4 lg:grid-cols-4">
      <StatCard label="Properties" :value="s.properties" :hint="`${s.occupied} occupied`" :icon="Building2" />
      <StatCard label="Tenants" :value="s.tenants" :hint="`${s.connected} connected`" :icon="Users" />
      <StatCard label="Collected this month" :value="formatUGX(s.collected)" :icon="Wallet" />
      <StatCard label="Outstanding" :value="formatUGX(s.outstanding)" :hint="`${s.overdue} overdue`" :icon="TriangleAlert" :tone="s.overdue ? 'danger' : 'default'" />
    </div>

    <section class="card mb-6 overflow-hidden">
      <div class="border-b border-slate-100 px-5 py-4">
        <h2 class="text-sm font-semibold text-slate-900">Properties & tenants</h2>
      </div>
      <div class="overflow-x-auto">
        <table v-if="properties.length" class="min-w-full divide-y divide-slate-100">
          <thead>
            <tr>
              <th class="table-head">Property</th>
              <th class="table-head">Rent</th>
              <th class="table-head">Tenant</th>
              <th class="table-head">Lease ends</th>
              <th class="table-head">Balance</th>
              <th class="table-head">Rent status</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-100">
            <tr v-for="p in properties" :key="p.id">
              <td class="table-cell">
                <p class="font-medium text-slate-900">{{ p.name }}</p>
                <p class="text-xs text-slate-500">{{ p.location }}</p>
              </td>
              <td class="table-cell">{{ formatUGX(p.rent) }}</td>
              <template v-if="rental.tenantForProperty(p.id)">
                <td class="table-cell">
                  {{ rental.tenantForProperty(p.id).name }}
                  <span class="ml-1 text-xs" :class="rental.tenantForProperty(p.id).userId ? 'text-emerald-700' : 'text-slate-400'">
                    {{ rental.tenantForProperty(p.id).userId ? '· connected' : '· not connected' }}
                  </span>
                </td>
                <td class="table-cell">{{ formatDate(rental.tenantForProperty(p.id).leaseEnd) }}</td>
                <td class="table-cell">{{ formatUGX(balanceFor(rental.tenantForProperty(p.id).id)) }}</td>
                <td class="table-cell"><StatusBadge :status="rentStatus(rental.tenantForProperty(p.id).id)" /></td>
              </template>
              <template v-else>
                <td class="table-cell text-slate-400" colspan="3">Vacant</td>
                <td class="table-cell"><StatusBadge status="vacant" /></td>
              </template>
            </tr>
          </tbody>
        </table>
        <p v-else class="px-5 py-10 text-center text-sm text-slate-500">This landlord hasn't added any properties yet.</p>
      </div>
    </section>

    <section class="card overflow-hidden">
      <div class="border-b border-slate-100 px-5 py-4">
        <h2 class="text-sm font-semibold text-slate-900">Recent payments</h2>
      </div>
      <div class="overflow-x-auto">
        <table v-if="payments.length" class="min-w-full divide-y divide-slate-100">
          <thead>
            <tr>
              <th class="table-head">Tenant</th>
              <th class="table-head">Period</th>
              <th class="table-head">Amount</th>
              <th class="table-head">Due</th>
              <th class="table-head">Paid on</th>
              <th class="table-head">Status</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-100">
            <tr v-for="p in payments" :key="p.id">
              <td class="table-cell font-medium text-slate-900">{{ rental.tenantById(p.tenantId)?.name }}</td>
              <td class="table-cell">{{ formatPeriod(p.period) }}</td>
              <td class="table-cell">{{ formatUGX(p.amount) }}</td>
              <td class="table-cell">{{ formatDate(p.dueDate) }}</td>
              <td class="table-cell">{{ formatDate(p.paidAt) }}</td>
              <td class="table-cell"><StatusBadge :status="p.status" /></td>
            </tr>
          </tbody>
        </table>
        <p v-else class="px-5 py-10 text-center text-sm text-slate-500">No payments yet.</p>
      </div>
    </section>
    <p class="mt-4 text-xs text-slate-400">{{ tenants.length - s.tenants }} former tenant(s) not shown.</p>
  </template>
</template>
