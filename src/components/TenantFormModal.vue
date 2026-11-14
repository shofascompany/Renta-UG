<script setup>
import { computed, reactive, ref, watch } from 'vue'
import { UserPlus, Smartphone, PhoneOff } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import BaseModal from './BaseModal.vue'

// Landlord: register a tenant. Always a FRESH tenant — nothing from any earlier stay is brought back,
// even if this person rented before (their old stays stay untouched in Records).
const props = defineProps({
  prefillId: { type: String, default: null }, // a former stay: only their name / phone / email are copied in
  propertyId: { type: String, default: null }, // house / room picked already (e.g. from a rental's room list)
})
const open = defineModel({ type: Boolean, default: false })
const emit = defineEmits(['saved'])

const rental = useRentalStore()

const blank = () => ({ email: '', name: '', phone: '', propertyId: '', leaseStart: '', leaseEnd: '', managedByLandlord: false })
const form = reactive(blank())
const saving = ref(false)
const error = ref('')

const vacant = computed(() =>
  rental.properties
    .filter((p) => !rental.tenantForProperty(p.id))
    .sort((a, b) => rental.placeName(a.id).localeCompare(rental.placeName(b.id), undefined, { numeric: true })),
)
const propertyName = (id) => (rental.propertyById(id) ? rental.placeName(id) : 'a removed property')

// Reset each time the form opens
watch(
  open,
  (v) => {
    if (!v) return
    Object.assign(form, blank())
    error.value = ''
    const pre = props.prefillId && rental.tenantById(props.prefillId)
    if (pre) {
      Object.assign(form, {
        name: pre.name ?? '',
        phone: pre.phone ?? '',
        email: pre.email && !pre.email.endsWith('@phone-signin.example.com') ? pre.email : '',
      })
    }
    if (props.propertyId && vacant.value.some((p) => p.id === props.propertyId)) form.propertyId = props.propertyId
  },
  { immediate: true },
)

// A person can only live in ONE house / room at a time: same email or same phone = already renting
const last9 = (v) => (v ?? '').replace(/\D/g, '').slice(-9)
const alreadyRenting = computed(() => {
  const email = form.managedByLandlord ? '' : form.email.trim().toLowerCase()
  const phone = last9(form.phone)
  return rental.currentTenants.find(
    (t) => (email && t.email && t.email.toLowerCase() === email) || (phone.length === 9 && last9(t.phone) === phone),
  )
})

async function save() {
  error.value = ''
  if (form.managedByLandlord) {
    if (!/^(?:\+?256|0)?[1-9]\d{8}$/.test(form.phone.replace(/[\s\-().]/g, ''))) {
      error.value = 'Enter a valid phone number, e.g. 0772 123456. The tenant will sign in with it later.'
      return
    }
    form.email = '' // not needed for a tenant without a smartphone
  }
  if (!form.managedByLandlord && !form.email.trim() && !form.phone.trim()) {
    error.value = 'Enter their phone number or email. Their connection code only works for an account with the same phone number or email.'
    return
  }
  if (alreadyRenting.value) {
    error.value = `This person already rents ${propertyName(alreadyRenting.value.propertyId)}. A tenant can only be in one house or room at a time. End that tenancy first.`
    return
  }
  saving.value = true
  try {
    const tenant = await rental.addTenant({ ...form })
    open.value = false
    emit('saved', tenant)
  } catch (e) {
    error.value = e.code === '23505' ? 'A current tenant already uses this email.' : e.message
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <BaseModal v-model="open" title="Add tenant">
    <form class="space-y-4" @submit.prevent="save">
      <!-- Does the tenant have a smartphone? -->
      <div class="grid grid-cols-2 gap-2 rounded-xl bg-slate-100 p-1" role="radiogroup" aria-label="Does the tenant have a smartphone?">
        <button
          v-for="opt in [[false, 'Has a smartphone', Smartphone], [true, 'No smartphone', PhoneOff]]"
          :key="String(opt[0])"
          type="button"
          role="radio"
          :aria-checked="form.managedByLandlord === opt[0]"
          class="flex h-10 items-center justify-center gap-2 rounded-lg text-sm font-medium transition"
          :class="form.managedByLandlord === opt[0] ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500 hover:text-slate-700'"
          @click="form.managedByLandlord = opt[0]"
        >
          <component :is="opt[2]" class="size-4" /> {{ opt[1] }}
        </button>
      </div>
      <p v-if="form.managedByLandlord" class="-mt-1 rounded-lg border border-slate-200 p-3 text-xs leading-relaxed text-slate-600">
        <strong class="text-slate-900">You'll manage this tenant.</strong> No email or password is needed: just their phone number.
        You record their cash payments and keep their rent and notices. When they get a smartphone, give them app access and they sign in with this number.
        Only you and Renta UG see this.
      </p>

      <div v-if="!form.managedByLandlord">
        <label class="label" for="tf-email">Email</label>
        <input id="tf-email" v-model="form.email" type="email" class="input" placeholder="tenant@example.com" autocomplete="off" />
      </div>

      <div class="grid grid-cols-2 gap-4">
        <div>
          <label class="label" for="tf-name">Full name</label>
          <input id="tf-name" v-model="form.name" class="input" data-cap="words" autocomplete="name" required />
        </div>
        <div>
          <label class="label" for="tf-phone">Phone<span v-if="form.managedByLandlord" class="text-red-500"> *</span></label>
          <input id="tf-phone" v-model="form.phone" type="tel" class="input" placeholder="0772 123456" :required="form.managedByLandlord" />
        </div>
      </div>

      <div>
        <label class="label" for="tf-prop">House or room</label>
        <select id="tf-prop" v-model="form.propertyId" class="input" required>
          <option value="" disabled>{{ vacant.length ? 'Select a vacant house or room' : 'No vacant houses' }}</option>
          <option v-for="p in vacant" :key="p.id" :value="p.id">{{ rental.placeName(p.id) }}</option>
        </select>
      </div>

      <p v-if="alreadyRenting" class="-mt-1 rounded-lg border border-red-200 bg-red-50 p-3 text-xs text-red-700">
        {{ alreadyRenting.name }} already rents {{ propertyName(alreadyRenting.propertyId) }}. A tenant can only be in one place at a time.
      </p>

      <p v-if="!form.managedByLandlord" class="rounded-lg bg-slate-50 p-3 text-xs text-slate-600">
        After saving you'll get a <strong>connection code</strong> (valid 20 minutes). It only works for an account with the <strong>same phone number or email</strong> you enter here. Their rental time starts when they first pay.
      </p>

      <p v-if="error" class="text-sm text-red-600">{{ error }}</p>

      <div class="flex justify-end gap-2 pt-2">
        <button type="button" class="btn-secondary" @click="open = false">Cancel</button>
        <button :data-busy="Boolean(saving)" type="submit" class="btn-primary" :disabled="saving || Boolean(alreadyRenting)">
          <UserPlus class="size-4" /> {{ saving ? 'Saving…' : 'Add tenant' }}
        </button>
      </div>
    </form>
  </BaseModal>
</template>
