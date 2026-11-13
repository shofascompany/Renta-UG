<script setup>
import { computed } from 'vue'
import { MapPin, BedDouble, Bath, Building2, Phone, Mail } from '@lucide/vue'
import { useTenant } from '@/composables/useTenant'
import { formatUGX, formatDate, daysUntil } from '@/utils/format'
import PageHeader from '@/components/PageHeader.vue'

const { rental, tenant, property } = useTenant()
const owner = computed(() => rental.owner)

const leaseProgress = computed(() => {
  if (!tenant.value) return 0
  const start = new Date(tenant.value.leaseStart).getTime()
  const end = new Date(tenant.value.leaseEnd).getTime()
  return Math.min(100, Math.max(0, ((Date.now() - start) / (end - start)) * 100))
})
</script>

<template>
  <PageHeader title="My home" subtitle="Details about the property you're renting." />

  <div v-if="property && tenant" class="grid gap-6 lg:grid-cols-3">
    <section class="card p-6 lg:col-span-2">
      <p class="text-xs font-medium tracking-wide text-slate-400 uppercase">{{ property.type }}</p>
      <h2 class="mt-1 text-xl font-semibold tracking-tight text-slate-900">{{ property.name }}</h2>
      <p class="mt-1 flex items-center gap-1.5 text-sm text-slate-500"><MapPin class="size-4" /> {{ property.location }}</p>

      <div class="mt-6 grid grid-cols-3 gap-4 border-y border-slate-100 py-5">
        <div class="flex items-center gap-2 text-sm text-slate-700"><BedDouble class="size-4 text-slate-400" /> {{ property.bedrooms }} bedrooms</div>
        <div class="flex items-center gap-2 text-sm text-slate-700"><Bath class="size-4 text-slate-400" /> {{ property.bathrooms }} bathrooms</div>
        <div class="flex items-center gap-2 text-sm text-slate-700"><Building2 class="size-4 text-slate-400" /> {{ property.type }}</div>
      </div>

      <h3 class="mt-6 text-sm font-semibold text-slate-900">Lease</h3>
      <dl class="mt-3 grid gap-4 text-sm sm:grid-cols-3">
        <div><dt class="text-slate-500">Monthly rent</dt><dd class="mt-0.5 font-medium text-slate-900">{{ formatUGX(property.rent) }}</dd></div>
        <div><dt class="text-slate-500">Start date</dt><dd class="mt-0.5 font-medium text-slate-900">{{ formatDate(tenant.leaseStart) }}</dd></div>
        <div><dt class="text-slate-500">End date</dt><dd class="mt-0.5 font-medium text-slate-900">{{ formatDate(tenant.leaseEnd) }}</dd></div>
      </dl>

      <div v-if="tenant.leaseStart && tenant.leaseEnd" class="mt-5">
        <div class="h-1.5 overflow-hidden rounded-full bg-slate-100">
          <div class="h-full rounded-full bg-brand-600" :style="{ width: `${leaseProgress}%` }" />
        </div>
        <p class="mt-2 text-xs text-slate-500">{{ daysUntil(tenant.leaseEnd) }} days remaining on your lease</p>
      </div>
    </section>

    <div class="space-y-6">
      <section v-if="owner" class="card p-5">
        <h2 class="text-sm font-semibold text-slate-900">Landlord contact</h2>
        <p class="mt-3 text-sm font-medium text-slate-900">{{ owner.full_name }}</p>
        <a v-if="owner.phone" :href="`tel:${owner.phone}`" class="mt-2 flex items-center gap-2 text-sm text-slate-600 hover:text-brand-600"><Phone class="size-4" /> {{ owner.phone }}</a>
        <a :href="`mailto:${owner.email}`" class="mt-1 flex items-center gap-2 text-sm text-slate-600 hover:text-brand-600"><Mail class="size-4" /> {{ owner.email }}</a>
      </section>

      <section class="card p-5">
        <h2 class="text-sm font-semibold text-slate-900">Your details</h2>
        <dl class="mt-3 space-y-2 text-sm">
          <div><dt class="text-slate-500">Name</dt><dd class="text-slate-900">{{ tenant.name }}</dd></div>
          <div><dt class="text-slate-500">Email</dt><dd class="text-slate-900">{{ tenant.email }}</dd></div>
          <div><dt class="text-slate-500">Phone</dt><dd class="text-slate-900">{{ tenant.phone }}</dd></div>
        </dl>
      </section>
    </div>
  </div>
</template>
