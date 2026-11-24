<script setup>
import { computed, ref, watch } from 'vue'
import { UserPlus, DoorOpen, AtSign, User, Phone, Info, Contact, CalendarDays, Wallet } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { formatUGX, formatDate } from '@/utils/format'
import { isoDay } from '@/utils/rentCycle'
import BaseModal from './BaseModal.vue'
import BaseSelect from './BaseSelect.vue'

// Landlord adds a tenant with just TWO things: their EMAIL or PHONE NUMBER (one box) and the house / room.
// Everything else (their own name and details) comes from the tenant when they connect with the code.
// `managed`: a tenant WITHOUT a smartphone (they never fill anything in), so their phone number is asked
// for here: it is how they get their notifications and, later, their app access.
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

// Payment when they move in: "Not paid yet" keeps the account as normal (nothing recorded).
// "Paid" asks for the amount received and the date; it is recorded like a cash payment the landlord received,
// so the same calculations run (first month starts on that date, extra goes to months ahead).
const today = () => isoDay(new Date())
const payStatus = ref('unpaid') // unpaid | paid
const payAmount = ref('')
const paidOn = ref(today())
const created = ref(null) // tenant already added (if only the payment failed, a retry does not add them twice)
const payValue = computed(() => Math.round(Number(String(payAmount.value).replace(/[^\d]/g, '')) || 0))
const placeRent = computed(() => rental.propertyById(propertyId.value)?.rent ?? 0)
const aheadMonths = computed(() => (placeRent.value ? Math.floor(payValue.value / placeRent.value) : 0))

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
    payStatus.value = 'unpaid'
    payAmount.value = ''
    paidOn.value = today()
    created.value = null
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
  if (created.value) return finish(created.value) // tenant added already: only the payment is left
  const value = who.value.trim()
  if (props.managed && value.length < 2) return (error.value = "Enter the tenant's name.")
  if (!props.managed && !isEmail.value && !isPhone(value)) {
    return (error.value = looksLikeEmail.value ? 'That email address does not look right.' : 'Enter their email or phone number, e.g. 0772 123456.')
  }
  if (props.managed && !/^(?:\+?256|0)?7\d{8}$/.test(phone.value.replace(/[\s\-().]/g, ''))) {
    return (error.value = 'Enter their phone number, e.g. 0772 123456. Their notifications go to it.')
  }
  if (!propertyId.value) return (error.value = 'Choose the house or room.')
  if (alreadyRenting.value) return (error.value = `${alreadyRenting.value.name} already rents ${rental.placeName(alreadyRenting.value.propertyId)}. End that tenancy first.`)
  if (payStatus.value === 'paid' && !checkPayment()) return
  saving.value = true
  try {
    created.value = await rental.addTenant({
      // Until they connect: a stand-in name (their own name replaces it)
      name: props.managed ? value : isEmail.value ? nameFromEmail(value) : 'New tenant',
      email: !props.managed && isEmail.value ? value.toLowerCase() : null,
      phone: props.managed ? phone.value.trim() : isEmail.value ? null : value,
      propertyId: propertyId.value,
      managedByLandlord: props.managed,
    })
  } catch (e) {
    error.value = e.code === '23505' ? 'A current tenant already uses this email.' : e.message
    saving.value = false
    return
  }
  saving.value = false
  await finish(created.value)
}

function checkPayment() {
  if (!payValue.value) return !(error.value = 'Enter the amount received.')
  if (!paidOn.value) return !(error.value = 'Choose the date it was paid.')
  if (paidOn.value > today()) return !(error.value = 'The payment date cannot be in the future.')
  if (!placeRent.value) return !(error.value = 'This house or room has no monthly rent set. Set the rent first, or choose "Not paid yet".')
  if (payValue.value > placeRent.value * 24) return !(error.value = 'That covers more than 2 years. Enter a smaller amount.')
  return true
}

// Records the move-in payment (if any), then closes
async function finish(tenant) {
  if (payStatus.value === 'paid') {
    if (!checkPayment()) return
    saving.value = true
    try {
      await rental.submitPayment({ tenantId: tenant.id, amount: payValue.value, paidOn: paidOn.value, method: 'cash', note: 'Paid when moving in' })
    } catch (e) {
      error.value = `The tenant was added, but the payment was not saved: ${e.message}`
      return
    } finally {
      saving.value = false
    }
  }
  open.value = false
  emit('saved', rental.tenantById(tenant.id) ?? tenant)
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
        <BaseSelect id="tf-prop" v-model="propertyId" :options="placeOptions" :icon="DoorOpen" placeholder="Choose a vacant house or room" empty-text="No vacant houses or rooms" :disabled="Boolean(created)" required />
      </div>

      <div>
        <label class="label" for="tf-pay">Payment</label>
        <BaseSelect
          id="tf-pay"
          v-model="payStatus"
          :icon="Wallet"
          :options="[
            { value: 'unpaid', label: 'Not paid yet', sub: 'Their account stays as normal' },
            { value: 'paid', label: 'Paid', sub: 'Enter the amount and the date it was paid' },
          ]"
        />
      </div>

      <template v-if="payStatus === 'paid'">
        <div class="grid grid-cols-2 gap-3">
          <div>
            <label class="label" for="tf-amount">Amount received (UGX)</label>
            <input id="tf-amount" v-model="payAmount" type="text" inputmode="numeric" class="input" placeholder="e.g. 500000" data-cap="off" required />
            <button v-if="placeRent" type="button" class="mt-1 text-xs font-medium text-brand-600" @click="payAmount = String(placeRent)">One month · {{ formatUGX(placeRent) }}</button>
          </div>
          <div>
            <label class="label" for="tf-date">Date paid</label>
            <div class="relative">
              <CalendarDays class="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-slate-400" />
              <input id="tf-date" v-model="paidOn" type="date" class="input pl-9" :max="today()" required />
            </div>
          </div>
        </div>
        <p v-if="payValue && paidOn && placeRent" class="flex items-start gap-2.5 rounded-2xl bg-sky-50 p-3 text-xs leading-relaxed text-sky-900">
          <Info class="mt-0.5 size-4 shrink-0" />
          <span>
            Their first month starts on <strong>{{ formatDate(paidOn) }}</strong>.
            <template v-if="aheadMonths >= 1"> {{ formatUGX(payValue) }} covers <strong>{{ aheadMonths }} month{{ aheadMonths === 1 ? '' : 's' }}</strong><template v-if="payValue % placeRent"> plus {{ formatUGX(payValue % placeRent) }} part payment</template>.</template>
            <template v-else> {{ formatUGX(payValue) }} is a part payment; they'll still owe {{ formatUGX(placeRent - payValue) }} for the first month.</template>
          </span>
        </p>
      </template>

      <p class="flex items-start gap-2.5 rounded-2xl bg-slate-50 p-3 text-xs leading-relaxed text-slate-600">
        <Info class="mt-0.5 size-4 shrink-0 text-brand-600" />
        <span v-if="managed">You'll manage this tenant: you record their payments and they get a notification for each one. Give them app access later if they get a smartphone.</span>
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

