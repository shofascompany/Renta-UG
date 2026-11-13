<script setup>
import { computed, reactive, ref, watch } from 'vue'
import { History, UserPlus, X } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { formatUGX, formatDate } from '@/utils/format'
import BaseModal from './BaseModal.vue'

// Landlord: add a new tenant, or bring a former tenant back as a NEW stay (fresh history;
// their old stays stay in Records). As the email is typed, matching people are suggested.
const props = defineProps({ prefillId: { type: String, default: null } }) // a former stay to add back
const open = defineModel({ type: Boolean, default: false })
const emit = defineEmits(['saved'])

const rental = useRentalStore()

const blank = () => ({ email: '', name: '', phone: '', propertyId: '', leaseStart: '', leaseEnd: '' })
const form = reactive(blank())
const returning = ref(null) // former tenant being added back
const saving = ref(false)
const error = ref('')

const vacant = computed(() => rental.properties.filter((p) => !rental.tenantForProperty(p.id)))
const propertyName = (id) => rental.propertyById(id)?.name ?? 'a removed property'

function selectFormer(t) {
  returning.value = t
  Object.assign(form, {
    email: t.email ?? form.email,
    name: t.name,
    phone: t.phone ?? '',
    // Back to their former house if it's free
    propertyId: vacant.value.some((p) => p.id === t.lastPropertyId) ? t.lastPropertyId : '',
    leaseStart: new Date().toLocaleDateString('en-CA'),
    leaseEnd: '',
  })
  error.value = ''
}

function clearFormer() {
  returning.value = null
  Object.assign(form, { ...blank(), email: form.email })
}

// Reset each time the form opens
watch(
  open,
  (v) => {
    if (!v) return
    Object.assign(form, blank())
    returning.value = null
    error.value = ''
    const pre = props.prefillId && rental.tenantById(props.prefillId)
    if (pre) selectFormer(pre)
  },
  { immediate: true },
)

// One entry per person (a person can have several stays): their current stay and latest ended one
const people = computed(() => {
  const byPerson = new Map()
  for (const t of rental.tenants) {
    const p = byPerson.get(t.personId) ?? { personId: t.personId, current: null, lastEnded: null }
    if (t.propertyId) p.current = t
    else if (!p.lastEnded || (t.endedAt ?? '') > (p.lastEnded.endedAt ?? '')) p.lastEnded = t
    byPerson.set(t.personId, p)
  }
  return [...byPerson.values()].map((p) => ({ ...p, shown: p.current ?? p.lastEnded }))
})

// Suggestions while typing the email (also matches names); former tenants first
const query = computed(() => form.email.trim().toLowerCase())
const suggestions = computed(() => {
  if (returning.value || query.value.length < 2) return []
  return people.value
    .filter((p) => `${p.shown.email ?? ''} ${p.shown.name}`.toLowerCase().includes(query.value))
    .sort((a, b) => Number(Boolean(a.current)) - Number(Boolean(b.current)))
    .slice(0, 4)
})
const sameEmail = (t) => t?.email && t.email.toLowerCase() === query.value
const exactFormer = computed(() => people.value.find((p) => !p.current && sameEmail(p.lastEnded))?.lastEnded)
const exactCurrent = computed(() => people.value.find((p) => sameEmail(p.current))?.current)

async function save() {
  error.value = ''
  if (!returning.value && exactCurrent.value) {
    error.value = `${exactCurrent.value.name} already rents ${propertyName(exactCurrent.value.propertyId)}.`
    return
  }
  if (!returning.value && exactFormer.value) {
    // Same email as a former tenant → add that person back rather than creating a stranger
    selectFormer(exactFormer.value)
    error.value = 'This is a former tenant. Check the details below and save to add them back.'
    return
  }
  saving.value = true
  try {
    const tenant = returning.value
      ? await rental.readdTenant(returning.value.id, { ...form })
      : await rental.addTenant({ ...form })
    open.value = false
    emit('saved', tenant)
  } catch (e) {
    error.value = e.code === '23505' ? 'A tenant with this email already exists.' : e.message
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <BaseModal v-model="open" :title="returning ? 'Add tenant back' : 'Add tenant'">
    <form class="space-y-4" @submit.prevent="save">
      <!-- Email first: drives the former-tenant lookup -->
      <div class="relative">
        <label class="label" for="tf-email">Email</label>
        <input
          id="tf-email"
          v-model="form.email"
          type="email"
          class="input"
          placeholder="Type an email to find former tenants"
          autocomplete="off"
          :disabled="Boolean(returning?.email)"
        />
        <ul
          v-if="suggestions.length"
          class="absolute z-10 mt-1 w-full overflow-hidden rounded-lg border border-slate-200 bg-white shadow-lg"
        >
          <li v-for="p in suggestions" :key="p.personId" class="flex items-center justify-between gap-3 px-3 py-2.5">
            <div class="min-w-0">
              <p class="truncate text-sm font-medium text-slate-900">{{ p.shown.name }}</p>
              <p class="truncate text-xs text-slate-500">
                {{ p.shown.email ?? 'no email' }} ·
                <template v-if="p.current">renting {{ propertyName(p.current.propertyId) }}</template>
                <template v-else>former tenant, {{ propertyName(p.lastEnded.lastPropertyId) }}</template>
              </p>
            </div>
            <button v-if="!p.current" type="button" class="btn-secondary shrink-0 px-2.5 py-1 text-xs" @click="selectFormer(p.lastEnded)">
              <History class="size-3.5" /> Add back
            </button>
            <span v-else class="shrink-0 text-xs text-slate-400">Current</span>
          </li>
        </ul>
      </div>

      <!-- Returning tenant banner -->
      <div v-if="returning" class="flex items-start gap-3 rounded-lg border border-brand-200 bg-brand-50 p-3">
        <History class="mt-0.5 size-4 shrink-0 text-brand-600" />
        <div class="flex-1 text-sm">
          <p class="font-medium text-slate-900">Adding back {{ returning.name }}</p>
          <p class="mt-0.5 text-xs text-slate-600">
            Previously at {{ propertyName(returning.lastPropertyId) }}<template v-if="returning.endedAt">, left {{ formatDate(returning.endedAt) }}</template>.
            This starts a <strong>new stay with a fresh history</strong>; their past stays stay in Records.
            <template v-if="returning.userId"> They'll be reconnected to their app account automatically.</template>
          </p>
        </div>
        <button type="button" class="btn-ghost -m-1 px-1.5" aria-label="Add someone else instead" @click="clearFormer">
          <X class="size-4" />
        </button>
      </div>

      <div class="grid grid-cols-2 gap-4">
        <div>
          <label class="label" for="tf-name">Full name</label>
          <input id="tf-name" v-model="form.name" class="input" required />
        </div>
        <div>
          <label class="label" for="tf-phone">Phone</label>
          <input id="tf-phone" v-model="form.phone" type="tel" class="input" placeholder="+256…" />
        </div>
      </div>

      <div>
        <label class="label" for="tf-prop">House</label>
        <select id="tf-prop" v-model="form.propertyId" class="input" required>
          <option value="" disabled>{{ vacant.length ? 'Select a vacant house' : 'No vacant houses' }}</option>
          <option v-for="p in vacant" :key="p.id" :value="p.id">
            {{ p.name }} · {{ formatUGX(p.rent) }}{{ returning && p.id === returning.lastPropertyId ? ' (their former house)' : '' }}
          </option>
        </select>
        <p v-if="returning && returning.lastPropertyId && !vacant.some((p) => p.id === returning.lastPropertyId)" class="mt-1 text-xs text-amber-700">
          Their former house is occupied right now. Pick another.
        </p>
      </div>

      <div class="grid grid-cols-2 gap-4">
        <div>
          <label class="label" for="tf-start">Lease start</label>
          <input id="tf-start" v-model="form.leaseStart" type="date" class="input" required />
        </div>
        <div>
          <label class="label" for="tf-end">Lease end</label>
          <input id="tf-end" v-model="form.leaseEnd" type="date" class="input" :min="form.leaseStart" required />
        </div>
      </div>

      <p v-if="!returning" class="rounded-lg bg-slate-50 p-3 text-xs text-slate-600">
        After saving you'll get a <strong>connection code</strong> (valid 20 minutes) for the tenant to connect their account.
      </p>

      <p v-if="error" class="text-sm" :class="error.startsWith('This is a former') ? 'text-brand-700' : 'text-red-600'">{{ error }}</p>

      <div class="flex justify-end gap-2 pt-2">
        <button type="button" class="btn-secondary" @click="open = false">Cancel</button>
        <button type="submit" class="btn-primary" :disabled="saving">
          <component :is="returning ? History : UserPlus" class="size-4" />
          {{ saving ? 'Saving…' : returning ? 'Add back' : 'Add tenant' }}
        </button>
      </div>
    </form>
  </BaseModal>
</template>
