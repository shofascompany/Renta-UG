<script setup>
import { computed, reactive, ref } from 'vue'
import { Plus, MapPin, BedDouble, Bath, Search } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { formatUGX } from '@/utils/format'
import PageHeader from '@/components/PageHeader.vue'
import StatusBadge from '@/components/StatusBadge.vue'
import BaseModal from '@/components/BaseModal.vue'

const rental = useRentalStore()
const query = ref('')
const status = ref('all')

const list = computed(() =>
  rental.properties.filter((p) => {
    const occupied = Boolean(rental.tenantForProperty(p.id))
    if (status.value === 'occupied' && !occupied) return false
    if (status.value === 'vacant' && occupied) return false
    const q = query.value.trim().toLowerCase()
    return !q || `${p.name} ${p.location}`.toLowerCase().includes(q)
  }),
)

const adding = ref(false)
const blank = () => ({ name: '', location: '', type: 'Apartment', bedrooms: 1, bathrooms: 1, rent: null })
const form = reactive(blank())

const saving = ref(false)
const error = ref('')

async function save() {
  saving.value = true
  error.value = ''
  try {
    await rental.addProperty({ ...form, bedrooms: Number(form.bedrooms), bathrooms: Number(form.bathrooms), rent: Number(form.rent) })
    Object.assign(form, blank())
    adding.value = false
  } catch (e) {
    error.value = e.message
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <PageHeader title="Properties" :subtitle="`${rental.properties.length} registered properties`">
    <button class="btn-primary" @click="adding = true"><Plus class="size-4" /> Add property</button>
  </PageHeader>

  <div class="mb-5 flex flex-col gap-3 sm:flex-row">
    <div class="relative flex-1">
      <Search class="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-slate-400" />
      <input v-model="query" class="input pl-9" placeholder="Search by name or location" />
    </div>
    <select v-model="status" class="input sm:w-44">
      <option value="all">All statuses</option>
      <option value="occupied">Occupied</option>
      <option value="vacant">Vacant</option>
    </select>
  </div>

  <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
    <RouterLink
      v-for="p in list"
      :key="p.id"
      :to="`/landlord/properties/${p.id}`"
      class="card block p-5 transition-colors hover:border-slate-300"
    >
      <div class="flex items-start justify-between gap-3">
        <p class="text-xs font-medium tracking-wide text-slate-400 uppercase">{{ p.type }}</p>
        <StatusBadge :status="rental.tenantForProperty(p.id) ? 'occupied' : 'vacant'" />
      </div>
      <h3 class="mt-1 font-semibold text-slate-900">{{ p.name }}</h3>
      <p class="mt-1 flex items-center gap-1.5 text-sm text-slate-500"><MapPin class="size-3.5" /> {{ p.location }}</p>
      <div class="mt-4 flex items-center gap-4 text-sm text-slate-600">
        <span class="flex items-center gap-1.5"><BedDouble class="size-4 text-slate-400" /> {{ p.bedrooms }}</span>
        <span class="flex items-center gap-1.5"><Bath class="size-4 text-slate-400" /> {{ p.bathrooms }}</span>
      </div>
      <div class="mt-4 flex items-end justify-between border-t border-slate-100 pt-4">
        <div>
          <p class="text-xs text-slate-500">Tenant</p>
          <p class="text-sm font-medium text-slate-900">{{ rental.tenantForProperty(p.id)?.name ?? '—' }}</p>
        </div>
        <p class="text-sm font-semibold text-slate-900">{{ formatUGX(p.rent) }}<span class="font-normal text-slate-500">/mo</span></p>
      </div>
    </RouterLink>
  </div>
  <p v-if="!list.length" class="py-12 text-center text-sm text-slate-500">
    {{ rental.properties.length ? 'No properties match your filters.' : 'No properties yet. Click "Add property" to register your first one.' }}
  </p>

  <BaseModal v-model="adding" title="Add property">
    <form class="space-y-4" @submit.prevent="save">
      <div>
        <label class="label" for="pname">Name</label>
        <input id="pname" v-model="form.name" class="input" placeholder="e.g. Kira Apartments 3C" required />
      </div>
      <div>
        <label class="label" for="ploc">Location</label>
        <input id="ploc" v-model="form.location" class="input" placeholder="e.g. Kira, Wakiso" required />
      </div>
      <div class="grid grid-cols-2 gap-4">
        <div>
          <label class="label" for="ptype">Type</label>
          <select id="ptype" v-model="form.type" class="input">
            <option v-for="t in ['Apartment', 'House', 'Studio', 'Villa', 'Cottage', 'Commercial']" :key="t">{{ t }}</option>
          </select>
        </div>
        <div>
          <label class="label" for="prent">Monthly rent (UGX)</label>
          <input id="prent" v-model="form.rent" type="number" min="0" step="1000" class="input" required />
        </div>
        <div>
          <label class="label" for="pbed">Bedrooms</label>
          <input id="pbed" v-model="form.bedrooms" type="number" min="0" class="input" />
        </div>
        <div>
          <label class="label" for="pbath">Bathrooms</label>
          <input id="pbath" v-model="form.bathrooms" type="number" min="0" class="input" />
        </div>
      </div>
      <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
      <div class="flex justify-end gap-2 pt-2">
        <button type="button" class="btn-secondary" @click="adding = false">Cancel</button>
        <button type="submit" class="btn-primary" :disabled="saving">{{ saving ? 'Saving…' : 'Save property' }}</button>
      </div>
    </form>
  </BaseModal>
</template>
