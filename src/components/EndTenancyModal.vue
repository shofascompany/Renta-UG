<script setup>
import { nextTick, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { Archive, DoorOpen, LogOut } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import BaseModal from './BaseModal.vue'
import EndTenancySummary from './EndTenancySummary.vue'

// End a tenancy: shows how the stay stands, asks, then confirms it is done.
//   by="landlord"  the tenant's landlord        by="admin"  the main admin (can give a reason, both are told)
// Keep it mounted outside any v-if on the current tenant: once ended, the room has no tenant any more.
const props = defineProps({ tenant: { type: Object, default: null }, by: { type: String, default: 'landlord' } })
const open = defineModel({ type: Boolean, default: false })
// ended: the tenancy was ended and the person closed this card. record: record a payment first (amount owed)
const emit = defineEmits(['ended', 'record'])

const rental = useRentalStore()
const router = useRouter()
const step = ref('ask') // ask | done
const reason = ref('')
const busy = ref(false)
const error = ref('')
const done = ref({ name: '', place: '' })
let silent = false // closed by going to Records: the page doesn't need to move on by itself

watch(open, (v) => {
  if (v) {
    step.value = 'ask'
    reason.value = ''
    error.value = ''
    silent = false
  } else if (step.value === 'done' && !silent) {
    emit('ended')
  }
})

async function end() {
  if (busy.value) return
  busy.value = true
  error.value = ''
  const { id, name, propertyId } = props.tenant
  const place = rental.placeName(propertyId)
  try {
    if (props.by === 'admin') await rental.adminEndTenancy(id, reason.value)
    else await rental.endTenancy(id)
    done.value = { name, place }
    step.value = 'done'
    if (!open.value) emit('ended') // the card was closed while it was working
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}

async function record(amount) {
  open.value = false
  await nextTick() // this card lets go of the page before the next one opens
  emit('record', amount)
}

function records() {
  silent = true
  open.value = false
  router.push('/landlord/records')
}
</script>

<template>
  <BaseModal v-model="open" center width="max-w-md" :title="step === 'done' ? 'Tenancy ended' : 'End tenancy?'">
    <div v-if="step === 'done'" class="py-2 text-center">
      <span class="done-ring mx-auto flex size-16 items-center justify-center rounded-full bg-emerald-50 text-emerald-600"><DoorOpen class="size-8" /></span>
      <p class="mt-4 text-lg font-semibold text-slate-900">{{ done.place }} is vacant</p>
      <p class="mx-auto mt-1 max-w-xs text-sm leading-relaxed text-slate-600">
        {{ done.name }} has moved out. <template v-if="by === 'admin'">The history is kept in the landlord's Records and both have been told.</template><template v-else>The full history is kept in Records.</template>
      </p>
      <div class="mt-6 grid gap-2" :class="by === 'landlord' ? 'grid-cols-2' : ''">
        <button v-if="by === 'landlord'" type="button" class="btn-secondary h-11" @click="records"><Archive class="size-4" /> Open Records</button>
        <button type="button" class="btn-primary h-11" @click="open = false">Done</button>
      </div>
    </div>

    <div v-else-if="tenant">
      <EndTenancySummary :tenant="tenant" :by="by" @record="record" @leave="open = false" />

      <div v-if="by === 'admin'" class="mt-4">
        <label class="label" for="et-reason">Reason <span class="font-normal text-slate-400">(optional, sent to both)</span></label>
        <input id="et-reason" v-model="reason" class="input" maxlength="200" placeholder="e.g. Moved out on 10 Nov" />
      </div>

      <!-- Always in reach, even when the card scrolls on a small phone -->
      <div class="end-foot">
        <p v-if="error" class="form-error mb-3" role="alert">{{ error }}</p>
        <div class="grid grid-cols-2 gap-2">
          <button type="button" class="btn-secondary h-12 rounded-2xl" @click="open = false">Keep tenant</button>
          <button type="button" class="btn h-12 rounded-2xl bg-red-600 font-semibold text-white hover:bg-red-700" :data-busy="busy" :disabled="busy" @click="end">
            <LogOut class="size-4" /> {{ busy ? 'Ending…' : 'End tenancy' }}
          </button>
        </div>
      </div>
    </div>
  </BaseModal>
</template>

<style scoped>
.end-foot {
  position: sticky;
  z-index: 1;
  bottom: calc(-1 * max(1.25rem, env(safe-area-inset-bottom)));
  margin: 1rem -1.25rem calc(-1 * max(1.25rem, env(safe-area-inset-bottom)));
  border-top: 1px solid var(--color-slate-100);
  padding: 0.9rem 1.25rem max(1.25rem, env(safe-area-inset-bottom));
  background: var(--color-white);
}
html.dark .end-foot { background: #000000; }
.done-ring { animation: pop 0.45s cubic-bezier(0.34, 1.56, 0.64, 1); }
@keyframes pop { from { transform: scale(0.6); opacity: 0; } }
@media (prefers-reduced-motion: reduce) { .done-ring { animation: none; } }
</style>
