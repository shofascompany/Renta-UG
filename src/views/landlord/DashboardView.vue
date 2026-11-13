<script setup>
import { computed } from 'vue'
import { Building2, Home, Wallet, TriangleAlert, ArrowRight } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { formatUGX, formatDate, formatPeriod, daysUntil } from '@/utils/format'
import PageHeader from '@/components/PageHeader.vue'
import StatCard from '@/components/StatCard.vue'
import StatusBadge from '@/components/StatusBadge.vue'

const rental = useRentalStore()
const s = computed(() => rental.stats)

const collectionRate = computed(() => (s.value.expected ? Math.round((s.value.collected / s.value.expected) * 100) : 0))

const attention = computed(() =>
  rental.payments
    .filter((p) => p.status !== 'paid')
    .sort((a, b) => (a.status === 'overdue' ? -1 : 1) - (b.status === 'overdue' ? -1 : 1) || a.dueDate.localeCompare(b.dueDate)),
)

const recent = computed(() =>
  rental.payments.filter((p) => p.status === 'paid').sort((a, b) => b.paidAt.localeCompare(a.paidAt)).slice(0, 5),
)

// Current tenants whose lease ends within 30 days (they get daily reminders in the last 7)
const endingSoon = computed(() =>
  rental.currentTenants
    .filter((t) => t.leaseEnd)
    .map((t) => ({ ...t, daysLeft: daysUntil(t.leaseEnd) }))
    .filter((t) => t.daysLeft >= 0 && t.daysLeft <= 30)
    .sort((a, b) => a.daysLeft - b.daysLeft),
)
</script>

<template>
  <PageHeader title="Overview" subtitle="A snapshot of all your properties and tenants.">
    <RouterLink to="/landlord/notifications" class="btn-secondary">Send notification</RouterLink>
    <RouterLink to="/landlord/properties" class="btn-primary">Manage properties</RouterLink>
  </PageHeader>

  <div class="mb-6 grid grid-cols-2 gap-4 lg:grid-cols-4">
    <StatCard label="Properties" :value="s.properties" :hint="`${s.occupied} occupied · ${s.vacant} vacant`" :icon="Building2" />
    <StatCard label="Occupancy" :value="`${s.properties ? Math.round((s.occupied / s.properties) * 100) : 0}%`" :hint="`${s.occupied} of ${s.properties} units`" :icon="Home" />
    <StatCard label="Collected this month" :value="formatUGX(s.collected)" :hint="`${collectionRate}% of ${formatUGX(s.expected)}`" :icon="Wallet" />
    <StatCard label="Outstanding" :value="formatUGX(s.outstanding)" :hint="`${s.overdue} overdue`" :icon="TriangleAlert" :tone="s.overdue ? 'danger' : 'default'" />
  </div>

  <div class="grid gap-6 lg:grid-cols-3">
    <div class="space-y-6 lg:col-span-2">
      <!-- Properties -->
      <section class="card overflow-hidden">
        <div class="flex items-center justify-between border-b border-slate-100 px-5 py-4">
          <h2 class="text-sm font-semibold text-slate-900">Properties</h2>
          <RouterLink to="/landlord/properties" class="inline-flex items-center gap-1 text-sm font-medium text-brand-600 hover:text-brand-700">
            View all <ArrowRight class="size-3.5" />
          </RouterLink>
        </div>
        <div v-if="!rental.properties.length" class="px-5 py-10 text-center">
          <p class="text-sm font-medium text-slate-900">Get started in three steps</p>
          <ol class="mx-auto mt-3 max-w-xs space-y-1 text-left text-sm text-slate-500">
            <li>1. Add your properties</li>
            <li>2. Add tenants and assign them a property</li>
            <li>3. Create rent charges each month under Payments</li>
          </ol>
          <RouterLink to="/landlord/properties" class="btn-primary mt-5">Add a property</RouterLink>
        </div>
        <div v-else class="overflow-x-auto">
          <table class="min-w-full divide-y divide-slate-100">
            <thead>
              <tr><th class="table-head">Property</th><th class="table-head">Tenant</th><th class="table-head">Rent</th><th class="table-head">Status</th></tr>
            </thead>
            <tbody class="divide-y divide-slate-100">
              <tr
                v-for="p in rental.properties"
                :key="p.id"
                class="cursor-pointer transition-colors hover:bg-slate-50"
                @click="$router.push(`/landlord/properties/${p.id}`)"
              >
                <td class="table-cell">
                  <p class="font-medium text-slate-900">{{ p.name }}</p>
                  <p class="text-xs text-slate-500">{{ p.location }}</p>
                </td>
                <td class="table-cell">{{ rental.tenantForProperty(p.id)?.name ?? '—' }}</td>
                <td class="table-cell">{{ formatUGX(p.rent) }}</td>
                <td class="table-cell"><StatusBadge :status="rental.tenantForProperty(p.id) ? 'occupied' : 'vacant'" /></td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <!-- Leases ending soon -->
      <section class="card">
        <div class="border-b border-slate-100 px-5 py-4">
          <h2 class="text-sm font-semibold text-slate-900">Leases ending soon</h2>
          <p class="mt-0.5 text-xs text-slate-500">Tenants get an automatic reminder every day during their last 7 days.</p>
        </div>
        <ul v-if="endingSoon.length" class="divide-y divide-slate-100">
          <li v-for="t in endingSoon" :key="t.id" class="flex items-center justify-between gap-3 px-5 py-3">
            <div class="min-w-0">
              <p class="truncate text-sm font-medium text-slate-900">{{ t.name }}</p>
              <p class="truncate text-xs text-slate-500">{{ rental.propertyById(t.propertyId)?.name }} · ends {{ formatDate(t.leaseEnd) }}</p>
            </div>
            <span class="shrink-0 text-xs font-medium" :class="t.daysLeft <= 7 ? 'text-amber-700' : 'text-slate-500'">
              {{ t.daysLeft === 0 ? 'Today' : `${t.daysLeft} day${t.daysLeft === 1 ? '' : 's'}` }}
            </span>
          </li>
        </ul>
        <p v-else class="px-5 py-8 text-center text-sm text-slate-500">No leases end in the next 30 days.</p>
      </section>
    </div>

    <div class="space-y-6">
      <!-- Needs attention -->
      <section class="card">
        <div class="border-b border-slate-100 px-5 py-4">
          <h2 class="text-sm font-semibold text-slate-900">Unpaid rent</h2>
        </div>
        <ul v-if="attention.length" class="divide-y divide-slate-100">
          <li v-for="p in attention" :key="p.id" class="flex items-center justify-between gap-3 px-5 py-3">
            <div class="min-w-0">
              <p class="truncate text-sm font-medium text-slate-900">{{ rental.tenantById(p.tenantId)?.name }}</p>
              <p class="text-xs text-slate-500">{{ formatUGX(p.amount) }} · due {{ formatDate(p.dueDate) }}</p>
            </div>
            <StatusBadge :status="p.status" />
          </li>
        </ul>
        <p v-else class="px-5 py-8 text-center text-sm text-slate-500">No unpaid rent.</p>
      </section>

      <!-- Recent payments -->
      <section class="card">
        <div class="flex items-center justify-between border-b border-slate-100 px-5 py-4">
          <h2 class="text-sm font-semibold text-slate-900">Recent payments</h2>
          <RouterLink to="/landlord/payments" class="text-sm font-medium text-brand-600 hover:text-brand-700">All</RouterLink>
        </div>
        <p v-if="!recent.length" class="px-5 py-8 text-center text-sm text-slate-500">No payments yet.</p>
        <ul class="divide-y divide-slate-100">
          <li v-for="p in recent" :key="p.id" class="flex items-center justify-between gap-3 px-5 py-3">
            <div class="min-w-0">
              <p class="truncate text-sm font-medium text-slate-900">{{ rental.tenantById(p.tenantId)?.name }}</p>
              <p class="text-xs text-slate-500">{{ formatPeriod(p.period) }} · {{ formatDate(p.paidAt) }}</p>
            </div>
            <p class="text-sm font-medium text-emerald-700">+{{ formatUGX(p.amount) }}</p>
          </li>
        </ul>
      </section>
    </div>
  </div>
</template>
