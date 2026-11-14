<script setup>
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { Plus, Search, Building2, House, DoorOpen, HousePlus, Minus, ArrowLeft } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useRentAnalytics } from '@/composables/useRentAnalytics'
import { formatUGX } from '@/utils/format'
import BaseModal from '@/components/BaseModal.vue'
import AdminHeader from '@/components/admin/AdminHeader.vue'
import ListRow from '@/components/admin/ListRow.vue'

// Properties = rentals (a business with several rooms) + standalone houses. Rows open their page.
const rental = useRentalStore()
const router = useRouter()
const a = useRentAnalytics()
const collectedAt = (id) => a.byHouse.value.find((h) => h.id === id)?.value ?? 0
const owedAt = (id) => a.byHouse.value.find((h) => h.id === id)?.owed ?? 0

const query = ref('')
const route = useRoute()
const show = ref(['rentals', 'houses', 'vacant'].includes(route.query.show) ? route.query.show : 'all') // all | rentals | houses | vacant

const rentals = computed(() =>
  rental.rentals.map((r) => {
    const rooms = rental.roomsOf(r.id)
    const occupied = rooms.filter((p) => rental.tenantForProperty(p.id)).length
    const rents = rooms.map((p) => p.rent)
    const min = Math.min(...rents)
    const max = Math.max(...rents)
    return {
      ...r,
      rooms,
      occupied,
      rentText: !rooms.length ? 'No rooms' : min === max ? `${formatUGX(min)} each` : `${formatUGX(min)} – ${formatUGX(max)}`,
      collected: rooms.reduce((s, p) => s + collectedAt(p.id), 0),
    }
  }),
)
const houses = computed(() =>
  rental.properties
    .filter((p) => !p.rentalId || !rental.rentalById(p.rentalId))
    .map((p) => ({ ...p, tenant: rental.tenantForProperty(p.id) })),
)
const vacantUnits = computed(() =>
  rental.properties
    .filter((p) => !rental.tenantForProperty(p.id))
    .sort((x, y) => rental.placeName(x.id).localeCompare(rental.placeName(y.id), undefined, { numeric: true })),
)

const match = (text) => {
  const q = query.value.trim().toLowerCase()
  return !q || text.toLowerCase().includes(q)
}
const shownRentals = computed(() => (['all', 'rentals'].includes(show.value) ? rentals.value.filter((r) => match(`${r.name} ${r.location}`)) : []))
const shownHouses = computed(() => (['all', 'houses'].includes(show.value) ? houses.value.filter((p) => match(`${p.name} ${p.location}`)) : []))
const shownVacant = computed(() => (show.value === 'vacant' ? vacantUnits.value.filter((p) => match(`${rental.placeName(p.id)} ${p.location}`)) : []))
const nothing = computed(() => !shownRentals.value.length && !shownHouses.value.length && !shownVacant.value.length)

const units = computed(() => rental.properties.length)
const occupiedUnits = computed(() => rental.properties.filter((p) => rental.tenantForProperty(p.id)).length)

// ── Add: choose a single house or a rental with rooms ──
const step = ref(null) // null | 'choose' | 'house' | 'rental'
const saving = ref(false)
const error = ref('')

const blankHouse = () => ({ name: '', location: '', type: 'House', bedrooms: 1, bathrooms: 1, rent: null })
const house = reactive(blankHouse())

const blankRental = () => ({ name: '', location: '', type: 'Rooms', count: 4, prefix: 'Room', sameRent: true, rent: null, rooms: [] })
const biz = reactive(blankRental())

// Rebuild the room list when the count / prefix / shared rent changes; keeps names already typed
function syncRooms() {
  const n = Math.max(1, Math.min(200, Number(biz.count) || 1))
  const next = Array.from({ length: n }, (_, i) => {
    const old = biz.rooms[i]
    const auto = `${biz.prefix.trim() || 'Room'} ${i + 1}`
    return {
      name: old && !old.auto ? old.name : auto,
      auto: old ? old.auto : true,
      rent: biz.sameRent ? biz.rent : (old?.rent ?? biz.rent),
    }
  })
  biz.rooms = next
}
watch(() => [biz.count, biz.prefix, biz.sameRent, biz.rent], syncRooms)

function startAdd() {
  error.value = ''
  Object.assign(house, blankHouse())
  Object.assign(biz, blankRental())
  syncRooms()
  step.value = 'choose'
}
const stepCount = (d) => (biz.count = Math.max(1, Math.min(200, (Number(biz.count) || 0) + d)))

async function saveHouse() {
  saving.value = true
  error.value = ''
  try {
    await rental.addProperty({ ...house, bedrooms: Number(house.bedrooms), bathrooms: Number(house.bathrooms), rent: Number(house.rent) })
    step.value = null
  } catch (e) {
    error.value = e.message
  } finally {
    saving.value = false
  }
}

async function saveRental() {
  if (biz.rooms.some((r) => !r.name.trim())) return (error.value = 'Give every room a name.')
  if (biz.rooms.some((r) => !(Number(r.rent) >= 0) || r.rent === null || r.rent === '')) return (error.value = 'Enter the rent for every room.')
  saving.value = true
  error.value = ''
  try {
    const r = await rental.addRental({ name: biz.name.trim(), location: biz.location.trim(), type: biz.type, rooms: biz.rooms })
    step.value = null
    router.push(`/landlord/rentals/${r.id}`)
  } catch (e) {
    error.value = e.message
  } finally {
    saving.value = false
  }
}
// Floating button: shows its words for 6 s when the page opens, then folds into the icon
const fabOpen = ref(true)
let fabTimer = setTimeout(() => (fabOpen.value = false), 6000)
onBeforeUnmount(() => clearTimeout(fabTimer))

const title = computed(() => ({ choose: 'Add property', house: 'Add a house', rental: 'Add a rental' })[step.value] ?? '')
</script>

<template>
  <div class="mx-auto max-w-5xl max-lg:pb-20">
    <AdminHeader compact eyebrow="Portfolio" title="My properties" :subtitle="`${rentals.length} rental${rentals.length === 1 ? '' : 's'} · ${houses.length} house${houses.length === 1 ? '' : 's'} · ${occupiedUnits} of ${units} occupied`">
      <button class="btn-primary h-10 max-lg:hidden" @click="startAdd"><Plus class="size-[1.1rem]" stroke-width="2.5" /> Add property</button>
    </AdminHeader>

    <!-- Search + filter -->
    <div class="flex flex-col gap-3 sm:flex-row sm:items-center">
      <div class="relative flex-1">
        <Search class="pointer-events-none absolute top-1/2 left-3.5 size-4 -translate-y-1/2 text-slate-400" />
        <input v-model="query" class="input h-11 rounded-xl bg-white pl-10" placeholder="Search by name or location" />
      </div>
      <div class="grid grid-cols-4 rounded-xl bg-slate-100 p-1 text-sm" role="tablist">
        <button
          v-for="f in [['all', 'All'], ['rentals', 'Rentals'], ['houses', 'Houses'], ['vacant', 'Vacant']]"
          :key="f[0]"
          role="tab"
          :aria-selected="show === f[0]"
          class="h-9 rounded-lg px-3 font-medium transition"
          :class="show === f[0] ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500 hover:text-slate-700'"
          @click="show = f[0]"
        >{{ f[1] }}</button>
      </div>
    </div>

    <!-- Rentals -->
    <section v-if="shownRentals.length" class="rise mt-6" style="--d: 60ms">
      <h2 class="section-title">Rentals</h2>
      <div class="sheet">
        <ul class="divide-y divide-slate-100">
          <ListRow
            v-for="r in shownRentals"
            :key="r.id"
            :to="`/landlord/rentals/${r.id}`"
            :title="r.name"
            :subtitle="`${r.rooms.length} room${r.rooms.length === 1 ? '' : 's'} · ${r.occupied} occupied · ${r.rentText}`"
            :value="formatUGX(r.collected)"
            value-sub="collected"
          >
            <template #icon><span class="icon-tile tile-teal"><Building2 class="size-[1.35rem]" /></span></template>
          </ListRow>
        </ul>
      </div>
    </section>

    <!-- Houses -->
    <section v-if="shownHouses.length" class="rise mt-6" style="--d: 100ms">
      <h2 class="section-title">Houses</h2>
      <div class="sheet">
        <ul class="divide-y divide-slate-100">
          <ListRow
            v-for="p in shownHouses"
            :key="p.id"
            :to="`/landlord/properties/${p.id}`"
            :title="p.name"
            :subtitle="`${p.tenant ? p.tenant.name : 'Vacant'} · ${p.location}`"
            :value="`${formatUGX(p.rent)}`"
            :value-sub="owedAt(p.id) ? `${formatUGX(owedAt(p.id))} owed` : 'a month'"
          >
            <template #icon><span class="icon-tile" :class="p.tenant ? 'tile-sky' : 'tile-slate'"><House class="size-[1.35rem]" /></span></template>
          </ListRow>
        </ul>
      </div>
    </section>

    <!-- Vacant rooms and houses -->
    <section v-if="shownVacant.length" class="rise mt-6" style="--d: 60ms">
      <h2 class="section-title">Ready for a tenant</h2>
      <div class="sheet">
        <ul class="divide-y divide-slate-100">
          <ListRow
            v-for="p in shownVacant"
            :key="p.id"
            :to="`/landlord/properties/${p.id}`"
            :title="rental.placeName(p.id)"
            :subtitle="p.location"
            :value="formatUGX(p.rent)"
            value-sub="a month"
          >
            <template #icon><span class="icon-tile tile-amber"><component :is="p.rentalId ? DoorOpen : House" class="size-[1.35rem]" /></span></template>
          </ListRow>
        </ul>
      </div>
    </section>

    <div v-if="nothing" class="sheet mt-6 flex flex-col items-center px-6 py-14 text-center">
      <span class="icon-tile tile-teal size-14 rounded-2xl"><HousePlus class="size-7" /></span>
      <p class="mt-4 font-semibold text-slate-900">{{ rental.properties.length ? 'Nothing here' : 'No properties yet' }}</p>
      <p class="mt-1 text-sm text-slate-500">{{ rental.properties.length ? 'Try a different search or filter.' : 'Add a single house, or a rental with several rooms.' }}</p>
      <button v-if="!rental.properties.length" class="btn-primary mt-5 h-11" @click="startAdd"><Plus class="size-4" /> Add property</button>
    </div>

    <!-- Add -->
    <BaseModal :model-value="Boolean(step)" :title="title" width="max-w-lg" @update:model-value="!$event && (step = null)">
      <!-- Choose -->
      <div v-if="step === 'choose'" class="space-y-3">
        <button class="flex w-full items-center gap-4 rounded-2xl border border-slate-200 p-4 text-left transition hover:border-brand-300 hover:bg-brand-50/40" @click="step = 'rental'">
          <span class="icon-tile tile-teal size-12"><Building2 class="size-6" /></span>
          <span class="min-w-0 flex-1">
            <span class="block font-semibold text-slate-900">A rental with several rooms</span>
            <span class="block text-sm text-slate-500">One business, as many rooms as you have. Rename them and set each rent.</span>
          </span>
        </button>
        <button class="flex w-full items-center gap-4 rounded-2xl border border-slate-200 p-4 text-left transition hover:border-brand-300 hover:bg-brand-50/40" @click="step = 'house'">
          <span class="icon-tile tile-sky size-12"><House class="size-6" /></span>
          <span class="min-w-0 flex-1">
            <span class="block font-semibold text-slate-900">A single house</span>
            <span class="block text-sm text-slate-500">One house or apartment for one tenant.</span>
          </span>
        </button>
      </div>

      <!-- Single house -->
      <form v-else-if="step === 'house'" class="space-y-4" @submit.prevent="saveHouse">
        <button type="button" class="inline-flex items-center gap-1 text-sm font-medium text-slate-500" @click="step = 'choose'"><ArrowLeft class="size-4" /> Back</button>
        <div>
          <label class="label" for="pname">Name</label>
          <input id="pname" v-model="house.name" class="input" placeholder="e.g. Kira Apartments 3C" required />
        </div>
        <div>
          <label class="label" for="ploc">Location</label>
          <input id="ploc" v-model="house.location" class="input" placeholder="e.g. Kira, Wakiso" required />
        </div>
        <div class="grid grid-cols-2 gap-4">
          <div>
            <label class="label" for="ptype">Type</label>
            <select id="ptype" v-model="house.type" class="input">
              <option v-for="t in ['House', 'Apartment', 'Studio', 'Villa', 'Cottage', 'Commercial']" :key="t">{{ t }}</option>
            </select>
          </div>
          <div>
            <label class="label" for="prent">Monthly rent (UGX)</label>
            <input id="prent" v-model="house.rent" type="number" min="0" step="1000" class="input" required />
          </div>
          <div>
            <label class="label" for="pbed">Bedrooms</label>
            <input id="pbed" v-model="house.bedrooms" type="number" min="0" class="input" />
          </div>
          <div>
            <label class="label" for="pbath">Bathrooms</label>
            <input id="pbath" v-model="house.bathrooms" type="number" min="0" class="input" />
          </div>
        </div>
        <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
        <div class="flex justify-end gap-2 pt-2">
          <button type="button" class="btn-secondary" @click="step = null">Cancel</button>
          <button :data-busy="Boolean(saving)" type="submit" class="btn-primary" :disabled="saving">{{ saving ? 'Saving…' : 'Save house' }}</button>
        </div>
      </form>

      <!-- Rental with rooms -->
      <form v-else-if="step === 'rental'" class="space-y-4" @submit.prevent="saveRental">
        <button type="button" class="inline-flex items-center gap-1 text-sm font-medium text-slate-500" @click="step = 'choose'"><ArrowLeft class="size-4" /> Back</button>
        <div>
          <label class="label" for="rname">Business name</label>
          <input id="rname" v-model="biz.name" class="input" placeholder="e.g. Nakato Rentals" required />
        </div>
        <div class="grid grid-cols-2 gap-4">
          <div class="col-span-2 sm:col-span-1">
            <label class="label" for="rloc">Location</label>
            <input id="rloc" v-model="biz.location" class="input" placeholder="e.g. Ntinda, Kampala" required />
          </div>
          <div class="col-span-2 sm:col-span-1">
            <label class="label" for="rtype">What you rent out</label>
            <select id="rtype" v-model="biz.type" class="input">
              <option v-for="t in ['Rooms', 'Apartments', 'Houses', 'Hostel rooms', 'Shops', 'Offices']" :key="t">{{ t }}</option>
            </select>
          </div>
        </div>

        <div class="grid grid-cols-2 gap-4">
          <div>
            <label class="label" for="rcount">How many?</label>
            <div class="flex h-11 items-center rounded-xl border border-slate-300 bg-white">
              <button type="button" class="flex h-full w-11 items-center justify-center text-slate-500 hover:text-slate-900" aria-label="Fewer" @click="stepCount(-1)"><Minus class="size-4" /></button>
              <input id="rcount" v-model.number="biz.count" type="number" min="1" max="200" class="h-full min-w-0 flex-1 bg-transparent text-center font-semibold text-slate-900 outline-none" />
              <button type="button" class="flex h-full w-11 items-center justify-center text-slate-500 hover:text-slate-900" aria-label="More" @click="stepCount(1)"><Plus class="size-4" /></button>
            </div>
          </div>
          <div>
            <label class="label" for="rprefix">Name them</label>
            <input id="rprefix" v-model="biz.prefix" class="input" placeholder="Room" />
          </div>
        </div>

        <div>
          <p class="label">Rent</p>
          <div class="grid grid-cols-2 rounded-xl bg-slate-100 p-1 text-sm">
            <button type="button" class="h-9 rounded-lg font-medium" :class="biz.sameRent ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500'" @click="biz.sameRent = true">Same for all</button>
            <button type="button" class="h-9 rounded-lg font-medium" :class="!biz.sameRent ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500'" @click="biz.sameRent = false">Different per room</button>
          </div>
          <input v-if="biz.sameRent" v-model="biz.rent" type="number" min="0" step="1000" class="input mt-3" placeholder="Monthly rent for each (UGX)" required />
        </div>

        <!-- Room list: rename any, set each rent -->
        <div>
          <p class="label">{{ biz.rooms.length }} {{ biz.type.toLowerCase() }} · tap a name to rename</p>
          <ul class="max-h-64 divide-y divide-slate-100 overflow-y-auto rounded-xl border border-slate-200">
            <li v-for="(r, i) in biz.rooms" :key="i" class="flex items-center gap-2 px-3 py-2">
              <span class="w-6 shrink-0 text-xs text-slate-400 tabular-nums">{{ i + 1 }}</span>
              <input v-model="r.name" data-cap="words" :aria-label="`Name of room ${i + 1}`" class="h-9 min-w-0 flex-1 rounded-lg border border-transparent bg-transparent px-2 text-sm font-medium text-slate-900 hover:border-slate-200 focus:border-brand-400 focus:outline-none" @input="r.auto = false" />
              <input
                v-if="!biz.sameRent"
                v-model="r.rent"
                type="number"
                min="0"
                step="1000"
                class="h-9 w-32 rounded-lg border border-slate-200 px-2 text-right text-sm tabular-nums focus:border-brand-400 focus:outline-none"
                placeholder="Rent"
              />
              <span v-else class="shrink-0 text-xs text-slate-500 tabular-nums">{{ biz.rent ? formatUGX(biz.rent) : '—' }}</span>
            </li>
          </ul>
        </div>

        <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
        <div class="flex justify-end gap-2 pt-1">
          <button type="button" class="btn-secondary" @click="step = null">Cancel</button>
          <button :data-busy="Boolean(saving)" type="submit" class="btn-primary" :disabled="saving">{{ saving ? 'Creating…' : `Create ${biz.rooms.length} ${biz.type.toLowerCase()}` }}</button>
        </div>
      </form>
    </BaseModal>
    <!-- Phones: floating "Add property" button, just above the tab bar -->
    <Teleport to="body">
      <button
        v-if="!step"
        type="button"
        :class="fabOpen && 'fab-open'"
        class="fab fixed right-4 z-30 flex h-14 items-center rounded-2xl p-2 text-[15px] font-semibold text-white lg:hidden"
        aria-label="Add property"
        @click="startAdd"
      >
        <span class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-white/20 ring-1 ring-white/30 ring-inset"><Plus class="size-5" stroke-width="2.5" /></span>
        <span class="fab-label">Add property</span>
      </button>
    </Teleport>  </div>
</template>

<style scoped>
.fab {
  --color-white: #fff;
  bottom: calc(6.25rem + env(safe-area-inset-bottom));
  background: linear-gradient(135deg, #2dd4bf 0%, #0f766e 50%, #0a3b38 100%);
  box-shadow: 0 14px 30px -10px rgb(15 118 110 / 0.75), inset 0 1px 0 rgb(255 255 255 / 0.25);
  transition: transform 0.15s ease;
  animation: fab-in 0.45s cubic-bezier(0.22, 1, 0.36, 1) 0.2s backwards;
}
/* Icon only; the words slide out on hover / keyboard focus / while pressed */
.fab-label {
  max-width: 0;
  overflow: hidden;
  white-space: nowrap;
  opacity: 0;
  transition: max-width 0.3s cubic-bezier(0.22, 1, 0.36, 1), opacity 0.2s ease, margin 0.3s ease;
}
.fab:hover .fab-label,
.fab:focus-visible .fab-label,
.fab:active .fab-label,
.fab-open .fab-label {
  max-width: 9rem;
  margin: 0 0.6rem 0 0.65rem;
  opacity: 1;
}
@keyframes fab-in {
  from { opacity: 0; transform: translateY(16px) scale(0.9); }
}
@media (prefers-reduced-motion: reduce) {
  .fab { animation: none; }
}
</style>
