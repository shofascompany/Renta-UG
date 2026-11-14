<script setup>
import { computed, ref } from 'vue'
import { useRoute } from 'vue-router'
import { Search, Building2, House, DoorOpen, Wallet } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { usePlatformStats } from '@/composables/usePlatformStats'
import { formatUGX } from '@/utils/format'
import SuperHero from '@/components/super/SuperHero.vue'
import StatTile from '@/components/super/StatTile.vue'
import ListRow from '@/components/admin/ListRow.vue'
import PropertyEditModal from '@/components/super/PropertyEditModal.vue'

// Main admin: every house and room on the platform. Tap one to edit its name, location or rent.
const rental = useRentalStore()
const route = useRoute()
const p = usePlatformStats()
const query = ref('')
const show = ref(route.query.show === 'vacant' ? 'vacant' : 'all') // all | occupied | vacant
const landlordFilter = ref('')
const editing = ref(null)

const list = computed(() => {
  const q = query.value.trim().toLowerCase()
  return rental.properties
    .map((x) => ({ ...x, tenant: rental.tenantForProperty(x.id), place: rental.placeName(x.id), landlord: p.landlordName(x.landlordId) }))
    .filter((x) => (show.value === 'all' ? true : show.value === 'vacant' ? !x.tenant : Boolean(x.tenant)))
    .filter((x) => !landlordFilter.value || x.landlordId === landlordFilter.value)
    .filter((x) => !q || `${x.place} ${x.location ?? ''} ${x.landlord} ${x.tenant?.name ?? ''}`.toLowerCase().includes(q))
    .sort((a, b) => a.landlord.localeCompare(b.landlord) || a.place.localeCompare(b.place, undefined, { numeric: true }))
})
const rentRoll = computed(() => rental.properties.filter((x) => rental.tenantForProperty(x.id)).reduce((s, x) => s + x.rent, 0))
</script>

<template>
  <div>
    <SuperHero eyebrow="Places" title="Properties" :subtitle="`${rental.properties.length} houses and rooms · ${rental.rentals.length} rental businesses`" tone="sky">
      <template #stats>
        <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <StatTile glass label="Occupied" :value="p.occupancy.value.used" :hint="`${p.occupancy.value.rate}% of all`" :icon="House" />
          <StatTile glass label="Vacant" :value="p.occupancy.value.vacant" hint="Ready for a tenant" :icon="DoorOpen" tile="tile-slate" />
          <StatTile glass label="Rental businesses" :value="rental.rentals.length" hint="With several rooms" :icon="Building2" tile="tile-violet" />
          <StatTile glass label="Monthly rent roll" :value="formatUGX(rentRoll)" hint="Occupied places" :icon="Wallet" tile="tile-amber" />
        </div>
      </template>
    </SuperHero>

    <div class="mb-4 flex flex-col gap-3 lg:flex-row lg:items-center">
      <div class="relative flex-1 lg:max-w-sm">
        <Search class="pointer-events-none absolute top-1/2 left-3.5 size-4 -translate-y-1/2 text-slate-400" />
        <input v-model="query" class="input pl-10" placeholder="Search place, location, landlord or tenant" />
      </div>
      <div class="grid grid-cols-3 rounded-2xl bg-slate-100 p-1 text-sm lg:w-80">
        <button v-for="f in [['all', 'All'], ['occupied', 'Occupied'], ['vacant', 'Vacant']]" :key="f[0]" type="button" class="h-9 rounded-xl font-medium transition" :class="show === f[0] ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500'" @click="show = f[0]">{{ f[1] }}</button>
      </div>
      <select v-model="landlordFilter" class="input lg:w-56">
        <option value="">All landlords</option>
        <option v-for="l in rental.landlords" :key="l.id" :value="l.id">{{ l.name }}</option>
      </select>
    </div>

    <div class="sheet">
      <ul v-if="list.length" class="divide-y divide-slate-100">
        <ListRow
          v-for="x in list"
          :key="x.id"
          :title="x.place"
          :subtitle="`${x.landlord}${x.location ? ` · ${x.location}` : ''} · ${x.tenant ? x.tenant.name : 'Vacant'}`"
          :value="formatUGX(x.rent)"
          value-sub="per month"
          @click="editing = x.id"
        >
          <template #icon>
            <span class="icon-tile" :class="x.tenant ? (x.rentalId ? 'tile-teal' : 'tile-sky') : 'tile-slate'">
              <Building2 v-if="x.rentalId" class="size-[1.3rem]" /><House v-else class="size-[1.3rem]" />
            </span>
          </template>
        </ListRow>
      </ul>
      <p v-else class="px-5 py-12 text-center text-sm text-slate-500">No properties match.</p>
    </div>

    <PropertyEditModal :property-id="editing" @close="editing = null" />
  </div>
</template>
