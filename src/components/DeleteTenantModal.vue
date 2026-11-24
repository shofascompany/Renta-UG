<script setup>
import { computed, ref, watch } from 'vue'
import { Trash2, TriangleAlert, Archive } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { formatUGX } from '@/utils/format'
import BaseModal from './BaseModal.vue'

// Landlord: delete a tenant for good. Asks first, says exactly what goes, and offers "End tenancy"
// (keeps the history in Records) as the gentler choice.
const props = defineProps({ tenant: { type: Object, default: null } })
const open = defineModel({ type: Boolean, default: false })
const emit = defineEmits(['deleted', 'end-instead'])

const rental = useRentalStore()
const sure = ref(false)
const busy = ref(false)
const error = ref('')
watch(open, (v) => v && ((sure.value = false), (error.value = '')))

const counts = computed(() => {
  const id = props.tenant?.id
  if (!id) return { months: 0, paid: 0, owed: 0 }
  const months = rental.paymentsForTenant(id)
  return {
    months: months.length,
    paid: months.reduce((s, p) => s + p.amountPaid, 0),
    owed: months.reduce((s, p) => s + p.balance, 0),
  }
})

async function remove() {
  error.value = ''
  if (!sure.value) return (error.value = 'Tick the box to confirm.')
  busy.value = true
  try {
    const name = props.tenant.name
    await rental.deleteTenant(props.tenant.id)
    open.value = false
    emit('deleted', name)
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <BaseModal v-model="open" center title="Delete tenant?" width="max-w-md">
    <div v-if="tenant" class="space-y-4">
      <div class="flex items-start gap-3.5 rounded-2xl bg-red-50 p-4">
        <span class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-red-100 text-red-600"><TriangleAlert class="size-5" /></span>
        <div class="text-sm leading-relaxed text-red-900">
          <p><strong>{{ tenant.name }}</strong> will be removed from {{ tenant.propertyId ? rental.placeName(tenant.propertyId) : 'your records' }} for good, with everything recorded for them:</p>
          <ul class="mt-1.5 list-disc space-y-0.5 pl-5 text-red-800">
            <li>{{ counts.months }} rent month{{ counts.months === 1 ? '' : 's' }}<template v-if="counts.paid">, {{ formatUGX(counts.paid) }} in payments and receipts</template></li>
            <li v-if="counts.owed">{{ formatUGX(counts.owed) }} still owed</li>
            <li>Notices and requests to leave</li>
          </ul>
          <p class="mt-1.5">The room becomes empty. This cannot be undone.</p>
        </div>
      </div>

      <button v-if="tenant.propertyId" type="button" class="flex w-full items-center gap-3 rounded-2xl border border-slate-200 p-3.5 text-left text-sm transition hover:bg-slate-50" @click="open = false; emit('end-instead')">
        <span class="icon-disc disc-sky size-9"><Archive class="size-4" /></span>
        <span class="min-w-0 flex-1"><span class="block font-medium text-slate-900">Keep their history instead?</span><span class="block text-xs text-slate-500">End the tenancy: the room is freed and their payments stay in Records.</span></span>
      </button>

      <label class="flex items-start gap-3 rounded-2xl border border-red-200 p-3 text-sm text-slate-700">
        <input v-model="sure" type="checkbox" class="size-5 accent-red-600" />
        <span>I understand that {{ tenant.name.split(' ')[0] }} and all their payment records will be deleted.</span>
      </label>
      <p v-if="error" class="form-error" role="alert">{{ error }}</p>
      <div class="grid grid-cols-2 gap-2">
        <button type="button" class="btn-secondary h-11" @click="open = false">Cancel</button>
        <button type="button" class="btn h-11 bg-red-600 text-white hover:bg-red-700" :data-busy="busy" :disabled="busy || !sure" @click="remove">
          <Trash2 class="size-4" /> {{ busy ? 'Deleting…' : 'Delete tenant' }}
        </button>
      </div>
    </div>
  </BaseModal>
</template>
