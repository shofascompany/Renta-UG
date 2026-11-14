<script setup>
import { computed, reactive, ref, watch } from 'vue'
import { Trash2, TriangleAlert } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { formatUGX } from '@/utils/format'
import BaseModal from '@/components/BaseModal.vue'

// Main admin: edit any property (name, location, monthly rent) or delete an empty one.
// The landlord gets a note in their inbox; the change goes into the activity log.
const props = defineProps({ propertyId: { type: String, default: null } })
const emit = defineEmits(['close'])
const rental = useRentalStore()

const p = computed(() => (props.propertyId ? rental.propertyById(props.propertyId) : null))
const tenant = computed(() => (p.value ? rental.tenantForProperty(p.value.id) : null))
const hasHistory = computed(
  () => Boolean(p.value) && (rental.tenants.some((t) => t.propertyId === p.value.id || t.lastPropertyId === p.value.id) || rental.payments.some((x) => x.propertyId === p.value.id)),
)
const form = reactive({ name: '', location: '', rent: '' })
const busy = ref(false)
const error = ref('')
const confirmDelete = ref(false)

watch(
  p,
  (v) => {
    if (!v) return
    Object.assign(form, { name: v.name, location: v.location ?? '', rent: String(v.rent ?? '') })
    error.value = ''
    confirmDelete.value = false
  },
  { immediate: true },
)
const rentValue = computed(() => Math.round(Number(String(form.rent).replace(/[^\d]/g, '')) || 0))

async function save() {
  busy.value = true
  error.value = ''
  try {
    await rental.adminUpdateProperty(p.value.id, { name: form.name, location: form.location, rent: rentValue.value })
    emit('close')
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}
async function remove() {
  busy.value = true
  error.value = ''
  try {
    await rental.adminDeleteProperty(p.value.id)
    emit('close')
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <BaseModal :model-value="Boolean(p)" :title="confirmDelete ? 'Delete property?' : 'Edit property'" width="max-w-md" @update:model-value="!$event && emit('close')">
    <div v-if="p">
      <template v-if="!confirmDelete">
        <form class="space-y-4" @submit.prevent="save">
          <p class="rounded-xl bg-slate-50 p-3 text-xs text-slate-600">
            {{ rental.placeName(p.id) }} · {{ rental.landlords.find((l) => l.id === p.landlordId)?.name ?? 'Landlord' }}
            <template v-if="tenant"> · rented by <strong>{{ tenant.name }}</strong></template>
          </p>
          <div>
            <label class="label" for="pe-name">Name</label>
            <input id="pe-name" v-model="form.name" class="input" data-cap="words" required />
          </div>
          <div>
            <label class="label" for="pe-loc">Location</label>
            <input id="pe-loc" v-model="form.location" class="input" data-cap="words" />
          </div>
          <div>
            <label class="label" for="pe-rent">Monthly rent (UGX)</label>
            <input id="pe-rent" v-model="form.rent" class="input" inputmode="numeric" required />
            <p v-if="rentValue !== p.rent" class="mt-1 text-xs text-amber-700">Was {{ formatUGX(p.rent) }}. New months are billed at {{ formatUGX(rentValue) }}.</p>
          </div>
          <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
          <div class="flex items-center justify-between gap-2 pt-1">
            <button v-if="!hasHistory" type="button" class="btn-ghost px-2 text-sm text-red-600" @click="confirmDelete = true"><Trash2 class="size-4" /> Delete</button>
            <span v-else class="text-[11px] text-slate-400">Has history: can't be deleted</span>
            <div class="flex gap-2">
              <button type="button" class="btn-secondary" @click="emit('close')">Cancel</button>
              <button :data-busy="Boolean(busy)" type="submit" class="btn-primary" :disabled="busy">{{ busy ? 'Saving…' : 'Save' }}</button>
            </div>
          </div>
        </form>
      </template>
      <template v-else>
        <div class="flex items-start gap-3.5 rounded-2xl bg-red-50 p-4">
          <span class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-red-100 text-red-700"><TriangleAlert class="size-5" /></span>
          <p class="text-sm text-red-900"><strong>{{ p.name }}</strong> has never had a tenant or payment. It will be removed from the landlord's account.</p>
        </div>
        <p v-if="error" class="mt-3 text-sm text-red-600">{{ error }}</p>
        <div class="mt-5 flex justify-end gap-2">
          <button type="button" class="btn-secondary" @click="confirmDelete = false">Back</button>
          <button type="button" class="btn bg-red-600 text-white hover:bg-red-700" :data-busy="Boolean(busy)" :disabled="busy" @click="remove">{{ busy ? 'Deleting…' : 'Delete property' }}</button>
        </div>
      </template>
    </div>
  </BaseModal>
</template>
