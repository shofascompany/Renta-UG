<script setup>
import { computed, ref, watch } from 'vue'
import { UserPlus, DoorOpen, AtSign, User, Phone, Info, Contact } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { formatUGX } from '@/utils/format'
import BaseModal from './BaseModal.vue'
import BaseSelect from './BaseSelect.vue'

// Landlord adds a tenant with just TWO things: their EMAIL or PHONE NUMBER (one box) and the house / room.
// Everything else (their own name and details) comes from the tenant when they connect with the code.
// `managed`: a tenant WITHOUT a smartphone (they never fill anything in), so their phone number is asked
// for here: it is how they get their SMS and, later, their app access.
const props = defineProps({
  prefillId: { type: String, default: null }, // a former stay: their name / email is copied in
  propertyId: { type: String, default: null }, // house / room picked already
  managed: { type: Boolean, default: false },
})
const open = defineModel({ type: Boolean, default: false })
const emit = defineEmits(['saved'])

const rental = useRentalStore()
const who = ref('') // email or phone number (managed: their name)
const phone = ref('')
const propertyId = ref('')
const saving = ref(false)
const error = ref('')

const vacant = computed(() =>
  rental.properties
    .filter((p) => !rental.tenantForProperty(p.id))
    .sort((a, b) => rental.placeName(a.id).localeCompare(rental.placeName(b.id), undefined, { numeric: true })),
)

// Vacant places as dropdown options, grouped under their rental business
const placeOptions = computed(() =>
  vacant.value.map((p) => ({
    value: p.id,
    label: p.name,
    group: (p.rentalId && rental.rentals.find((r) => r.id === p.rentalId)?.name) || undefined,
    sub: p.rent ? `${formatUGX(p.rent)} / month` : 'Rent not set',
    hint: p.rent ? formatUGX(p.rent) : '',
  })),
)
watch(
  open,
  (v) => {
    if (!v) return
    error.value = ''
    phone.value = ''
    const pre = props.prefillId && rental.tenantById(props.prefillId)
    who.value = !pre ? '' : props.managed ? pre.name ?? '' : pre.email && !pre.email.endsWith('@phone-signin.example.com') ? pre.email : pre.phone ?? ''
    if (pre && props.managed) phone.value = pre.phone ?? ''
    propertyId.value = props.propertyId && vacant.value.some((p) => p.id === props.propertyId) ? props.propertyId : ''
  },
  { immediate: true },
)

const isEmail = computed(() => /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(who.value.trim()))
const isPhone = (v) => /^(?:\+?256|0)?7\d{8}$/.test(String(v).replace(/[\s\-().]/g, ''))
const looksLikeEmail = computed(() => who.value.includes('@'))
// "john.mukasa@gmail.com" → "John Mukasa" until the tenant connects and their own name replaces it
const nameFromEmail = (e) => e.split('@')[0].replace(/[._\-+\d]+/g, ' ').trim() || 'New tenant'

// A person can only live in ONE place at a time (same email, or same phone for managed tenants)
const last9 = (v) => (v ?? '').replace(/\D/g, '').slice(-9)
const alreadyRenting = computed(() => {
  const email = isEmail.value ? who.value.trim().toLowerCase() : ''
  const p = last9(props.managed ? phone.value : isPhone(who.value) ? who.value : '')
  return rental.currentTenants.find((t) => (email && t.email?.toLowerCase() === email) || (p.length === 9 && last9(t.phone) === p))
})

async function save() {
  error.value = ''
  const value = who.value.trim()
  if (props.managed && value.length < 2) return (error.value = "Enter the tenant's name.")
  if (!props.managed && !isEmail.value && !isPhone(value)) {
    return (error.value = looksLikeEmail.value ? 'That email address does not look right.' : 'Enter their email or phone number, e.g. 0772 123456.')
  }
  if (props.managed && !/^(?:\+?256|0)?7\d{8}$/.test(phone.value.replace(/[\s\-().]/g, ''))) {
    return (error.value = 'Enter their phone number, e.g. 0772 123456. Their SMS goes to it.')
  }
  if (!propertyId.value) return (error.value = 'Choose the house or room.')
  if (alreadyRenting.value) return (error.value = `${alreadyRenting.value.name} already rents ${rental.placeName(alreadyRenting.value.propertyId)}. End that tenancy first.`)
  saving.value = true
  try {
    const tenant = await rental.addTenant({
      // Until they connect: a stand-in name (their own name replaces it)
      name: props.managed ? value : isEmail.value ? nameFromEmail(value) : 'New tenant',
      email: !props.managed && isEmail.value ? value.toLowerCase() : null,
      phone: props.managed ? phone.value.trim() : isEmail.value ? null : value,
      propertyId: propertyId.value,
      managedByLandlord: props.managed,
    })
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
  <BaseModal v-model="open" center width="max-w-md" :title="managed ? 'Add tenant without a smartphone' : 'Add tenant'">
    <form class="space-y-4" @submit.prevent="save">
      <div>
        <label class="label" for="tf-who">{{ managed ? 'Full name' : 'Email or phone number' }}</label>
        <div class="relative">
          <component :is="managed ? User : looksLikeEmail ? AtSign : /^[\d+\s]/.test(who) ? Phone : Contact" class="pointer-events-none absolute top-1/2 left-3.5 size-4.5 -translate-y-1/2 text-slate-400" />
          <input
            id="tf-who"
            v-model="who"
            class="input h-12 pl-10 text-base"
            :placeholder="managed ? 'e.g. Sarah Nakato' : 'e.g. john@gmail.com or 0772 123456'"
            :data-cap="managed ? 'words' : 'off'"
            autocomplete="off"
            autofocus
            required
          />
        </div>
      </div>

      <div v-if="managed">
        <label class="label" for="tf-phone">Phone number</label>
        <div class="relative">
          <Phone class="pointer-events-none absolute top-1/2 left-3.5 size-4.5 -translate-y-1/2 text-slate-400" />
          <input id="tf-phone" v-model="phone" type="tel" class="input h-12 pl-10 text-base" placeholder="0772 123456" data-cap="off" required />
        </div>
      </div>

      <div>
        <label class="label" for="tf-prop">House or room</label>
        <BaseSelect id="tf-prop" v-model="propertyId" :options="placeOptions" :icon="DoorOpen" placeholder="Choose a vacant house or room" empty-text="No vacant houses or rooms" required />
      </div>

      <p class="flex items-start gap-2.5 rounded-2xl bg-slate-50 p-3 text-xs leading-relaxed text-slate-600">
        <Info class="mt-0.5 size-4 shrink-0 text-brand-600" />
        <span v-if="managed">You'll manage this tenant: you record their payments and they get an SMS for each one. Give them app access later if they get a smartphone.</span>
        <span v-else>Next you get a <strong>connection code</strong>. It only works for the tenant with this email or phone number. They sign up, enter the code and add their own name and details.</span>
      </p>

      <p v-if="error" class="rounded-xl bg-red-50 p-3 text-sm text-red-700">{{ error }}</p>

      <div class="grid grid-cols-2 gap-2 pt-1">
        <button type="button" class="btn-secondary h-11" @click="open = false">Cancel</button>
        <button :data-busy="Boolean(saving)" type="submit" class="btn-primary h-11" :disabled="saving">
          <UserPlus class="size-4" /> {{ saving ? 'Adding…' : 'Add tenant' }}
        </button>
      </div>
    </form>
  </BaseModal>
</template>

