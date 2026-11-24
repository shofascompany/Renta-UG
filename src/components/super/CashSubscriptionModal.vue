<script setup>
import { computed, reactive, ref, watch } from 'vue'
import { Banknote, Check, Home, Building, CircleCheck, TriangleAlert } from '@lucide/vue'
import { useBillingStore } from '@/stores/billing'
import { useRentalStore } from '@/stores/rental'
import { formatUGX, formatDate } from '@/utils/format'
import BaseModal from '@/components/BaseModal.vue'

// Main admin: a landlord paid their subscription in cash. Pick the package they paid for, confirm,
// and their subscription is extended at once (on top of any time left). See database/51.
const props = defineProps({ landlord: Object }) // a row from rental.landlords; null = closed
const emit = defineEmits(['close', 'done'])

const billing = useBillingStore()
const rental = useRentalStore()
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Africa/Kampala' })

const form = reactive({ tier: 'small', plan: 'yearly', paidOn: today(), note: '' })
const busy = ref(false)
const error = ref('')
const done = ref(null) // { amount, until } after saving

const units = computed(() => (props.landlord ? rental.properties.filter((p) => p.landlordId === props.landlord.id).length : 0))
const max = computed(() => billing.settings.smallMaxUnits)
const need = computed(() => Math.max(units.value, props.landlord?.plannedUnits ?? 0))
const smallAllowed = computed(() => units.value <= max.value)
const pendingOf = computed(() => (props.landlord ? billing.payments.find((p) => p.status === 'pending' && p.landlordId === props.landlord.id) : null))

watch(
  () => props.landlord,
  (l) => {
    if (!l) return
    Object.assign(form, {
      tier: l.subscriptionTier && (l.subscriptionTier !== 'small' || smallAllowed.value) ? l.subscriptionTier : need.value > max.value ? 'big' : 'small',
      plan: l.subscriptionPlan || 'yearly',
      paidOn: today(),
      note: '',
    })
    error.value = ''
    done.value = null
  },
  { immediate: true },
)

const price = computed(() => billing.price(form.tier, form.plan))
const addDays = (iso, n) => {
  const d = new Date(`${iso}T00:00:00Z`)
  d.setUTCDate(d.getUTCDate() + n)
  return d.toISOString().slice(0, 10)
}
// Same rule as the database: on top of any time left, otherwise from today
const period = computed(() => {
  const until = props.landlord?.subscriptionUntil
  const start = until && until >= today() ? addDays(until, 1) : today()
  // A subscription month is 30 days; a year is 365 (same as database/53)
  return { start, end: addDays(start, (form.plan === 'yearly' ? 365 : 30) - 1) }
})

const scales = computed(() => [
  { id: 'small', name: 'Small scale', icon: Home, fits: `Up to ${max.value} houses and rooms` },
  { id: 'big', name: 'Big scale', icon: Building, fits: 'Any number' },
])

async function save() {
  error.value = ''
  if (form.tier === 'small' && !smallAllowed.value) return (error.value = `This landlord has ${units.value} houses and rooms: choose Big scale.`)
  busy.value = true
  try {
    const res = await billing.recordCash(props.landlord.id, { ...form })
    await rental.loadLandlords()
    done.value = { amount: res?.amount ?? price.value, until: res?.until ?? period.value.end }
    emit('done', done.value)
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <BaseModal :model-value="Boolean(landlord)" center width="max-w-lg" :title="done ? 'Cash payment recorded' : 'Record a cash payment'" @update:model-value="!$event && emit('close')">
    <template v-if="landlord">
      <!-- Saved -->
      <div v-if="done" class="text-center">
        <div class="mx-auto flex size-16 items-center justify-center rounded-full bg-emerald-50 text-emerald-600"><CircleCheck class="size-8" /></div>
        <p class="mt-4 text-[15px] text-slate-700">
          <strong class="text-slate-900">{{ formatUGX(done.amount) }}</strong> in cash from <strong class="text-slate-900">{{ landlord.name || landlord.email }}</strong> is recorded.
        </p>
        <p class="mt-1 text-sm text-slate-500">Their subscription now runs until <strong class="text-slate-900">{{ formatDate(done.until) }}</strong>. They have been told in their inbox.</p>
        <button type="button" class="btn-primary mt-6 h-11 w-full rounded-xl" @click="emit('close')">Done</button>
      </div>

      <form v-else class="space-y-5" @submit.prevent="save">
        <div class="flex items-center gap-3 rounded-2xl bg-slate-50 p-3.5">
          <span class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-amber-100 text-amber-700"><Banknote class="size-5" /></span>
          <div class="min-w-0 text-sm">
            <p class="truncate font-semibold text-slate-900">{{ landlord.name || landlord.email }}</p>
            <p class="text-xs text-slate-500">
              {{ units }} house{{ units === 1 ? '' : 's' }}/rooms now<template v-if="landlord.plannedUnits"> · plans {{ landlord.plannedUnits }}</template>
              · {{ landlord.subscriptionUntil ? `covered until ${formatDate(landlord.subscriptionUntil)}` : 'not paid yet' }}
            </p>
          </div>
        </div>

        <p v-if="pendingOf" class="flex items-start gap-2 rounded-xl bg-amber-50 p-3 text-xs text-amber-900">
          <TriangleAlert class="mt-px size-4 shrink-0 text-amber-600" />
          This landlord also has a mobile money payment of {{ formatUGX(pendingOf.amount) }} waiting. If that is the same money, confirm it on the Subscriptions page instead.
        </p>

        <div>
          <p class="label">Package paid for</p>
          <div class="grid grid-cols-2 gap-2.5">
            <button
              v-for="sc in scales" :key="sc.id" type="button"
              class="pkg relative rounded-2xl p-3.5 text-left"
              :class="[form.tier === sc.id && 'pkg-on', sc.id === 'small' && !smallAllowed && 'cursor-not-allowed opacity-50']"
              :disabled="sc.id === 'small' && !smallAllowed" :aria-pressed="form.tier === sc.id"
              @click="form.tier = sc.id"
            >
              <span class="flex items-center justify-between">
                <span class="flex items-center gap-1.5 text-sm font-semibold text-slate-900"><component :is="sc.icon" class="size-4 text-brand-600" /> {{ sc.name }}</span>
                <span class="radio" :class="form.tier === sc.id && 'radio-on'"><Check v-if="form.tier === sc.id" class="size-3" /></span>
              </span>
              <span class="mt-1 block text-xs text-slate-500">{{ sc.fits }}</span>
            </button>
          </div>
        </div>

        <div>
          <p class="label">Paid for</p>
          <div class="grid grid-cols-2 gap-1 rounded-2xl bg-slate-100 p-1">
            <button v-for="pl in ['monthly', 'yearly']" :key="pl" type="button" class="rounded-xl px-3 py-2.5 text-left transition" :class="form.plan === pl ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-600'" @click="form.plan = pl">
              <span class="block text-sm font-semibold">{{ pl === 'yearly' ? '1 year · 365 days' : '1 month · 30 days' }}</span>
              <span class="block text-xs tabular-nums opacity-80">{{ formatUGX(billing.price(form.tier, pl)) }}</span>
            </button>
          </div>
        </div>

        <div class="grid gap-4 sm:grid-cols-2">
          <div>
            <label class="label" for="cs-date">Date paid</label>
            <input id="cs-date" v-model="form.paidOn" type="date" class="input" :max="today()" required />
          </div>
          <div>
            <label class="label" for="cs-note">Note (optional)</label>
            <input id="cs-note" v-model="form.note" class="input" maxlength="200" placeholder="e.g. Paid at the office" />
          </div>
        </div>

        <dl class="divide-y divide-slate-100 rounded-2xl border border-slate-200 px-4 text-sm">
          <div class="flex justify-between gap-3 py-2.5"><dt class="text-slate-500">Cash received</dt><dd class="font-bold text-slate-900 tabular-nums">{{ formatUGX(price) }}</dd></div>
          <div class="flex justify-between gap-3 py-2.5"><dt class="text-slate-500">Covers</dt><dd class="text-right font-medium text-slate-900">{{ formatDate(period.start) }} – {{ formatDate(period.end) }}</dd></div>
        </dl>

        <p v-if="error" class="rounded-xl bg-red-50 p-3 text-sm text-red-700">{{ error }}</p>
        <div class="grid grid-cols-2 gap-2">
          <button type="button" class="btn-secondary h-11" @click="emit('close')">Cancel</button>
          <button type="submit" class="btn-primary h-11" :data-busy="busy" :disabled="busy">{{ busy ? 'Saving…' : 'Confirm payment' }}</button>
        </div>
        <p class="text-center text-xs text-slate-400">Only confirm once you have the cash in hand. The account opens straight away.</p>
      </form>
    </template>
  </BaseModal>
</template>

<style scoped>
.pkg { background: var(--color-white); box-shadow: inset 0 0 0 1px var(--color-slate-200); transition: box-shadow 0.15s ease, background-color 0.15s ease; }
.pkg:not(:disabled):hover { box-shadow: inset 0 0 0 1px var(--color-slate-300); }
.pkg-on, .pkg-on:not(:disabled):hover { background: var(--color-brand-50); box-shadow: inset 0 0 0 2px var(--color-brand-500); }
.radio { display: flex; width: 1.15rem; height: 1.15rem; flex-shrink: 0; align-items: center; justify-content: center; border-radius: 9999px; box-shadow: inset 0 0 0 1.5px var(--color-slate-300); }
.radio-on { color: #fff; background: #0f766e; box-shadow: none; }
</style>
