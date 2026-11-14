<script setup>
import { computed, ref } from 'vue'
import { Search, UserCog, Plus } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { formatUGX } from '@/utils/format'
import AdminHeader from '@/components/admin/AdminHeader.vue'
import ListRow from '@/components/admin/ListRow.vue'
import TenantFormModal from '@/components/TenantFormModal.vue'

// Tenants without a smartphone, whose accounts the landlord runs. Tap one for their mini account page.
const rental = useRentalStore()
const query = ref('')
const adding = ref(false)

const people = computed(() =>
  rental.currentTenants
    .filter((t) => t.managedByLandlord && !t.userId)
    .map((t) => ({ ...t, owed: rental.duesForTenant(t.id).reduce((s, p) => s + p.balance, 0) }))
    .sort((a, b) => b.owed - a.owed || a.name.localeCompare(b.name)),
)
const rows = computed(() => {
  const q = query.value.trim().toLowerCase()
  return people.value.filter((t) => !q || `${t.name} ${t.phone ?? ''} ${rental.placeName(t.propertyId)}`.toLowerCase().includes(q))
})
const owedTotal = computed(() => people.value.reduce((s, t) => s + t.owed, 0))
const initials = (name) => name.split(' ').map((p) => p[0]).slice(0, 2).join('').toUpperCase()
</script>

<template>
  <div class="mx-auto max-w-3xl">
    <AdminHeader
      eyebrow="No smartphone"
      title="Managed accounts"
      :subtitle="`${people.length} tenant${people.length === 1 ? '' : 's'} you run the account for${owedTotal ? ` · ${formatUGX(owedTotal)} owed` : ''}`"
    >
      <button class="btn-primary h-10" @click="adding = true"><Plus class="size-4" /> Add tenant</button>
    </AdminHeader>

    <div class="relative">
      <Search class="pointer-events-none absolute top-1/2 left-3.5 size-4 -translate-y-1/2 text-slate-400" />
      <input v-model="query" class="input h-11 rounded-xl bg-white pl-10" placeholder="Search name, phone or room" />
    </div>

    <div class="sheet rise mt-4" style="--d: 60ms">
      <ul v-if="rows.length" class="divide-y divide-slate-100">
        <ListRow
          v-for="t in rows"
          :key="t.id"
          :to="`/landlord/managed/${t.id}`"
          :title="t.name"
          :subtitle="`${rental.placeName(t.propertyId)}${t.phone ? ` · ${t.phone}` : ''}`"
          :value="t.owed ? formatUGX(t.owed) : 'Paid up'"
          :value-sub="t.owed ? 'owed' : ''"
          :value-class="t.owed ? 'text-red-600' : 'text-emerald-700'"
        >
          <template #icon><span class="icon-disc disc-solid size-11 rounded-full text-xs font-bold">{{ initials(t.name) }}</span></template>
        </ListRow>
      </ul>
      <div v-else class="flex flex-col items-center px-6 py-14 text-center">
        <span class="icon-disc disc-slate size-12 rounded-full"><UserCog class="size-6" /></span>
        <p class="mt-3 font-semibold text-slate-900">{{ people.length ? 'No matches' : 'No managed accounts' }}</p>
        <p class="mt-1 max-w-xs text-sm text-slate-500">When you add a tenant and choose "No smartphone", you run their account from here.</p>
      </div>
    </div>

    <TenantFormModal v-model="adding" />
  </div>
</template>
