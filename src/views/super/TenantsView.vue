<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { Search, Trash2 } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useLandlordStats } from '@/composables/useLandlordStats'
import { formatUGX, formatDate } from '@/utils/format'
import PageHeader from '@/components/PageHeader.vue'
import StatusBadge from '@/components/StatusBadge.vue'

// Main admin: every current tenant across all landlords.
const rental = useRentalStore()
const { landlordName } = useLandlordStats()
const query = ref('')
const landlordFilter = ref('')

// ── Inactive tenant accounts (signed up, but not renting anything now) ──
const inactive = ref([])
const inactiveLoading = ref(true)
const inactiveError = ref('')

async function loadInactive() {
  inactiveError.value = ''
  try {
    inactive.value = await rental.loadInactiveTenantAccounts()
  } catch (e) {
    inactiveError.value = e.message
  } finally {
    inactiveLoading.value = false
  }
}
onMounted(loadInactive)
watch(() => rental.tenants, loadInactive)

async function removeAccount(a) {
  if (!confirm(`Permanently delete the account ${a.email}? They will no longer be able to sign in. This cannot be undone.`)) return
  try {
    await rental.deleteUser(a.id)
    await loadInactive()
  } catch (e) {
    alert(e.message)
  }
}

const rows = computed(() =>
  rental.tenants
    .filter((t) => t.propertyId)
    .map((t) => {
      const dues = rental.duesForTenant(t.id)
      return {
        ...t,
        landlord: landlordName(t.landlordId),
        property: rental.propertyById(t.propertyId),
        balance: dues.reduce((s, p) => s + p.balance, 0),
        status: dues.some((p) => p.status === 'overdue') ? 'overdue' : dues.length ? 'pending' : 'paid',
      }
    })
    .filter((t) => {
      if (landlordFilter.value && t.landlordId !== landlordFilter.value) return false
      const q = query.value.trim().toLowerCase()
      return !q || `${t.name} ${t.email ?? ''} ${t.landlord} ${t.property?.name ?? ''}`.toLowerCase().includes(q)
    }),
)
</script>

<template>
  <PageHeader title="All tenants" :subtitle="`${rows.length} current tenants`" />

  <div class="mb-5 flex flex-col gap-3 sm:flex-row">
    <div class="relative flex-1 sm:max-w-sm">
      <Search class="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-slate-400" />
      <input v-model="query" class="input pl-9" placeholder="Search tenants, landlords, properties" />
    </div>
    <select v-model="landlordFilter" class="input sm:w-56">
      <option value="">All landlords</option>
      <option v-for="l in rental.landlords" :key="l.id" :value="l.id">{{ l.name }}</option>
    </select>
  </div>

  <section class="card overflow-hidden">
    <div class="overflow-x-auto">
      <table v-if="rows.length" class="min-w-full divide-y divide-slate-100">
        <thead>
          <tr>
            <th class="table-head">Tenant</th>
            <th class="table-head">Landlord</th>
            <th class="table-head">Property</th>
            <th class="table-head">Lease ends</th>
            <th class="table-head">Balance</th>
            <th class="table-head">Rent status</th>
            <th class="table-head">Account</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100">
          <tr v-for="t in rows" :key="t.id">
            <td class="table-cell">
              <p class="font-medium text-slate-900">{{ t.name }}</p>
              <p class="text-xs text-slate-500">{{ t.email ?? '—' }}</p>
            </td>
            <td class="table-cell">
              <RouterLink :to="`/admin2026/landlords/${t.landlordId}`" class="hover:text-brand-600">{{ t.landlord }}</RouterLink>
            </td>
            <td class="table-cell">{{ t.property?.name }}</td>
            <td class="table-cell">{{ formatDate(t.leaseEnd) }}</td>
            <td class="table-cell">{{ formatUGX(t.balance) }}</td>
            <td class="table-cell"><StatusBadge :status="t.status" /></td>
            <td class="table-cell text-xs" :class="t.userId ? 'text-emerald-700' : 'text-slate-400'">{{ t.userId ? 'Connected' : 'Not connected' }}</td>
          </tr>
        </tbody>
      </table>
      <p v-else class="px-5 py-10 text-center text-sm text-slate-500">No tenants found.</p>
    </div>
  </section>

  <section class="card mt-6 overflow-hidden">
    <div class="border-b border-slate-100 px-5 py-4">
      <h2 class="text-sm font-semibold text-slate-900">Inactive tenant accounts</h2>
      <p class="mt-0.5 text-xs text-slate-500">Accounts not renting anything right now: never connected to a landlord, or their tenancy ended.</p>
    </div>
    <div v-if="inactiveLoading" class="divide-y divide-slate-100">
      <div v-for="i in 3" :key="i" class="flex items-center gap-4 px-5 py-4">
        <div class="skeleton h-4 w-40" />
        <div class="skeleton h-3 w-24" />
      </div>
    </div>
    <p v-else-if="inactiveError" class="px-5 py-6 text-sm text-red-600">{{ inactiveError }}</p>
    <ul v-else-if="inactive.length" class="divide-y divide-slate-100">
      <li v-for="a in inactive" :key="a.id" class="flex items-center justify-between gap-4 px-5 py-3">
        <div class="min-w-0">
          <p class="truncate text-sm font-medium text-slate-900">{{ a.name || a.email }}</p>
          <p class="truncate text-xs text-slate-500">
            {{ a.email }} · joined {{ formatDate(a.createdAt) }} · {{ a.formerTenant ? 'former tenant' : 'never connected' }}
          </p>
        </div>
        <button class="btn-ghost px-2 py-1 text-xs text-red-600" @click="removeAccount(a)">
          <Trash2 class="size-3.5" /> Delete
        </button>
      </li>
    </ul>
    <p v-else class="px-5 py-8 text-center text-sm text-slate-500">No inactive tenant accounts.</p>
  </section>
</template>
