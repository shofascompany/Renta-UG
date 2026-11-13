<script setup>
import { computed } from 'vue'
import { Briefcase, Building2, Users, Wallet, TriangleAlert } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useLandlordStats } from '@/composables/useLandlordStats'
import { formatUGX } from '@/utils/format'
import PageHeader from '@/components/PageHeader.vue'
import StatCard from '@/components/StatCard.vue'
import StatusBadge from '@/components/StatusBadge.vue'

const rental = useRentalStore()
const { rows } = useLandlordStats()
const s = computed(() => rental.stats)
const activeTenants = computed(() => rental.tenants.filter((t) => t.propertyId).length)
</script>

<template>
  <PageHeader title="Platform overview" subtitle="Every landlord, property and tenant on Renta UG.">
    <RouterLink to="/admin2026/landlords" class="btn-primary">Register landlord</RouterLink>
  </PageHeader>

  <div class="mb-6 grid grid-cols-2 gap-4 lg:grid-cols-5">
    <StatCard label="Landlords" :value="rental.landlords.length" :hint="`${rental.landlords.filter((l) => l.active).length} active`" :icon="Briefcase" />
    <StatCard label="Properties" :value="s.properties" :hint="`${s.occupied} occupied · ${s.vacant} vacant`" :icon="Building2" />
    <StatCard label="Tenants" :value="activeTenants" :hint="`${rental.tenants.filter((t) => t.userId && t.propertyId).length} connected`" :icon="Users" />
    <StatCard label="Collected this month" :value="formatUGX(s.collected)" :icon="Wallet" />
    <StatCard label="Outstanding" :value="formatUGX(s.outstanding)" :hint="`${s.overdue} overdue`" :icon="TriangleAlert" :tone="s.overdue ? 'danger' : 'default'" />
  </div>

  <section class="card overflow-hidden">
    <div class="border-b border-slate-100 px-5 py-4">
      <h2 class="text-sm font-semibold text-slate-900">Landlords</h2>
    </div>
    <div class="overflow-x-auto">
      <table v-if="rows.length" class="min-w-full divide-y divide-slate-100">
        <thead>
          <tr>
            <th class="table-head">Landlord</th>
            <th class="table-head">Properties</th>
            <th class="table-head">Tenants</th>
            <th class="table-head">Collected (month)</th>
            <th class="table-head">Outstanding</th>
            <th class="table-head">Status</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100">
          <tr
            v-for="l in rows"
            :key="l.id"
            class="cursor-pointer transition-colors hover:bg-slate-50"
            @click="$router.push(`/admin2026/landlords/${l.id}`)"
          >
            <td class="table-cell">
              <p class="font-medium text-slate-900">{{ l.name }}</p>
              <p class="text-xs text-slate-500">{{ l.email }}</p>
            </td>
            <td class="table-cell">{{ l.occupied }} / {{ l.properties }} occupied</td>
            <td class="table-cell">{{ l.tenants }} <span class="text-xs text-slate-400">({{ l.connected }} connected)</span></td>
            <td class="table-cell">{{ formatUGX(l.collected) }}</td>
            <td class="table-cell" :class="l.overdue && 'font-medium text-red-600'">{{ formatUGX(l.outstanding) }}</td>
            <td class="table-cell"><StatusBadge :status="l.active ? 'active' : 'suspended'" /></td>
          </tr>
        </tbody>
      </table>
      <div v-else class="px-5 py-12 text-center">
        <p class="text-sm font-medium text-slate-900">No landlords yet</p>
        <p class="mt-1 text-sm text-slate-500">Register your first landlord to get started.</p>
        <RouterLink to="/admin2026/landlords" class="btn-primary mt-5">Register landlord</RouterLink>
      </div>
    </div>
  </section>
</template>
