<script setup>
import { computed, ref } from 'vue'
import { Search, Plus, Archive } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { formatUGX, formatDate, daysUntil } from '@/utils/format'
import PageHeader from '@/components/PageHeader.vue'
import StatusBadge from '@/components/StatusBadge.vue'
import TenantFormModal from '@/components/TenantFormModal.vue'
import ConnectCodeModal from '@/components/ConnectCodeModal.vue'

// Current tenants only. Former tenants live on the Records page.
const rental = useRentalStore()
const query = ref('')

const rows = computed(() =>
  rental.currentTenants
    .map((t) => {
      const dues = rental.duesForTenant(t.id)
      return {
        ...t,
        property: rental.propertyById(t.propertyId),
        balance: dues.reduce((s, p) => s + p.balance, 0),
        status: dues.some((p) => p.status === 'overdue') ? 'overdue' : dues.length ? 'pending' : 'paid',
        leaseDays: t.leaseEnd ? daysUntil(t.leaseEnd) : null,
      }
    })
    .filter((t) => {
      const q = query.value.trim().toLowerCase()
      return !q || `${t.name} ${t.email ?? ''} ${t.property?.name ?? ''}`.toLowerCase().includes(q)
    }),
)

const adding = ref(false)
const codeFor = ref(null)

// New tenants (or returning ones without a linked account) get a connection code straight away
function onSaved(t) {
  if (!t.userId) codeFor.value = t.id
}
</script>

<template>
  <PageHeader title="Tenants" :subtitle="`${rental.currentTenants.length} current tenants`">
    <RouterLink to="/landlord/records" class="btn-secondary">
      <Archive class="size-4" /> Records ({{ rental.tenantRecords.length }})
    </RouterLink>
    <button class="btn-primary" @click="adding = true"><Plus class="size-4" /> Add tenant</button>
  </PageHeader>

  <div class="relative mb-5 max-w-sm">
    <Search class="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-slate-400" />
    <input v-model="query" class="input pl-9" placeholder="Search tenants" />
  </div>

  <section class="card overflow-hidden">
    <div class="overflow-x-auto">
      <table v-if="rows.length" class="min-w-full divide-y divide-slate-100">
        <thead>
          <tr>
            <th class="table-head">Tenant</th>
            <th class="table-head">House</th>
            <th class="table-head">Lease ends</th>
            <th class="table-head">Balance</th>
            <th class="table-head">Rent status</th>
            <th class="table-head">Account</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100">
          <tr
            v-for="t in rows"
            :key="t.id"
            class="cursor-pointer transition-colors hover:bg-slate-50"
            @click="$router.push(`/landlord/properties/${t.propertyId}`)"
          >
            <td class="table-cell">
              <p class="font-medium text-slate-900">{{ t.name }}</p>
              <p class="text-xs text-slate-500">{{ t.email ?? '—' }}</p>
            </td>
            <td class="table-cell">{{ t.property?.name }}</td>
            <td class="table-cell">
              {{ formatDate(t.leaseEnd) }}
              <span v-if="t.leaseDays !== null && t.leaseDays <= 60" class="ml-1 text-xs text-amber-600">({{ t.leaseDays }}d)</span>
            </td>
            <td class="table-cell" :class="t.balance && 'font-medium text-slate-900'">{{ formatUGX(t.balance) }}</td>
            <td class="table-cell"><StatusBadge :status="t.status" /></td>
            <td class="table-cell text-xs">
              <span v-if="t.userId" class="text-emerald-700">Connected</span>
              <button v-else class="btn-secondary px-2.5 py-1 text-xs" @click.stop="codeFor = t.id">Get code</button>
            </td>
          </tr>
        </tbody>
      </table>
      <p v-else class="px-5 py-10 text-center text-sm text-slate-500">
        {{ rental.currentTenants.length ? 'No tenants match your search.' : 'No current tenants. Click "Add tenant" to add one.' }}
      </p>
    </div>
  </section>

  <TenantFormModal v-model="adding" @saved="onSaved" />

  <ConnectCodeModal
    v-if="codeFor"
    :tenant-id="codeFor"
    :model-value="true"
    @update:model-value="!$event && (codeFor = null)"
  />
</template>
