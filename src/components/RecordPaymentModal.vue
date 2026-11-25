<script setup>
import { computed, ref, watch } from 'vue'
import { Banknote, Smartphone, CheckCircle2, ArrowLeft, CalendarDays, MessageSquareText, ChevronRight, Info } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { formatUGX, formatDate, formatPeriod } from '@/utils/format'
import { isoDay } from '@/utils/rentCycle'
import { NETWORKS, NETWORK_IDS } from '@/lib/networks'
import BaseModal from './BaseModal.vue'
import TenantPicker from './TenantPicker.vue'
import PaymentCoverage from './PaymentCoverage.vue'

// Landlord records a payment they received. A card in the middle of the screen:
//   1. Which payment?  Cash (any tenant) or Mobile money (tenants without a smartphone only;
//      tenants with the app send it themselves and the landlord confirms it).
//   2. Tenant, amount, the DATE it was paid (a new tenant's first month starts that day), network.
// It counts straight away (you received it): unpaid rent first, then months ahead. The tenant is told
// with a notification. The money is always recorded as received by you, the landlord.
// tenantId: preselect a tenant. presetAmount: fill in the amount (e.g. "Complete payment": what is left)
const props = defineProps({ tenantId: { type: String, default: null }, presetAmount: { type: Number, default: 0 } })
const open = defineModel({ type: Boolean, default: false })
const emit = defineEmits(['saved'])

const rental = useRentalStore()
const today = () => isoDay(new Date())

const step = ref('choose') // choose | form | done
const method = ref('cash') // cash | mobile_money
const tenantId = ref('')
const network = ref('mtn')
const amount = ref('')
const paidOn = ref(today())
const note = ref('')
const busy = ref(false)
const error = ref('')
const result = ref(null)

watch(
  open,
  (v) => {
    if (!v) return
    step.value = 'choose'
    method.value = 'cash'
    tenantId.value = props.tenantId ?? ''
    network.value = rental.payAccountsOf()[0]?.network ?? 'mtn'
    amount.value = props.presetAmount ? String(props.presetAmount) : ''
    paidOn.value = today()
    note.value = ''
    error.value = ''
    result.value = null
  },
  { immediate: true },
)

const noPhone = (t) => t.managedByLandlord
const allTenants = computed(() => [...rental.currentTenants].sort((a, b) => a.name.localeCompare(b.name)))
const tenants = computed(() => (method.value === 'mobile_money' ? allTenants.value.filter(noPhone) : allTenants.value))
const preset = computed(() => (props.tenantId ? rental.tenantById(props.tenantId) : null))
const mobileAllowed = computed(() => (preset.value ? noPhone(preset.value) : allTenants.value.some(noPhone)))

function choose(m) {
  method.value = m
  if (tenantId.value && !tenants.value.some((t) => t.id === tenantId.value)) tenantId.value = ''
  step.value = 'form'
}

const tenant = computed(() => rental.tenantById(tenantId.value) ?? null)
const dues = computed(() => (tenantId.value ? rental.duesForTenant(tenantId.value) : []))
const charged = computed(() => dues.value.reduce((s, p) => s + p.balance, 0))
// Everything in debt: the months charged and the months begun since their paid time ended
const pay = computed(() => (tenant.value ? rental.payStateFor(tenant.value.id) : null))
const total = computed(() => (dues.value.length || pay.value?.ended ? Math.max(charged.value, pay.value?.owed ?? 0) : 0))
const value = computed(() => Math.round(Number(String(amount.value).replace(/[^\d]/g, '')) || 0))
const rent = computed(() => (tenant.value ? rental.propertyById(tenant.value.propertyId)?.rent ?? 0 : 0))

// Same rule as the database: unpaid rent first (oldest first), then months ahead
const plan = computed(() => {
  let left = value.value
  return dues.value.map((p) => {
    const take = Math.min(left, p.balance)
    left -= take
    return { ...p, take, after: p.balance - take }
  })
})
const extra = computed(() => Math.max(0, value.value - charged.value))
const extraMonths = computed(() => (rent.value ? Math.floor(extra.value / rent.value) : 0))
const debtMonths = computed(() => (total.value > charged.value ? Math.min(extraMonths.value, Math.round((total.value - charged.value) / rent.value)) : 0))
const aheadMonths = computed(() => extraMonths.value - debtMonths.value)
const balanceAfter = computed(() => Math.max(0, total.value - value.value))
const tooMuch = computed(() => rent.value > 0 && extra.value > rent.value * 24)
const noRent = computed(() => extra.value > 0 && !rent.value)

// Rent cycle: first payment starts the month on the chosen date; late payments lose their debt days
const firstPayment = computed(() => Boolean(tenant.value) && !tenant.value.leaseEnd)

async function save() {
  error.value = ''
  if (!value.value) return (error.value = 'Enter the amount received.')
  if (!paidOn.value) return (error.value = 'Choose the date it was paid.')
  if (paidOn.value > today()) return (error.value = 'The date cannot be in the future.')
  if (tooMuch.value) return (error.value = 'That covers more than 2 years ahead. Enter a smaller amount.')
  if (noRent.value) return (error.value = "This tenant's house has no monthly rent set, so the extra can't go to months ahead.")
  busy.value = true
  try {
    await rental.submitPayment({
      tenantId: tenantId.value,
      amount: value.value,
      paidOn: paidOn.value,
      note: note.value,
      method: method.value,
      network: method.value === 'mobile_money' ? network.value : null,
    })
    const t = rental.tenantById(tenantId.value)
    result.value = { amount: value.value, name: t?.name, phone: t?.phone, paidTo: t?.leaseEnd }
    step.value = 'done'
    emit('saved', result.value)
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <BaseModal v-model="open" center width="max-w-md" :title="step === 'done' ? 'Payment recorded' : step === 'form' ? (method === 'cash' ? 'Record cash' : 'Record mobile money') : 'Record a payment'">
    <!-- 1. Which payment -->
    <div v-if="step === 'choose'" class="space-y-3">
      <p class="text-sm text-slate-500">Which payment are you recording?</p>
      <button type="button" class="kind-card kind-cash" @click="choose('cash')">
        <span class="kind-ico"><Banknote class="size-6" /></span>
        <span class="min-w-0 flex-1 text-left">
          <span class="block text-base font-semibold">Cash</span>
          <span class="block text-xs opacity-80">Money handed to you by any tenant</span>
        </span>
        <ChevronRight class="size-5 opacity-70" />
      </button>
      <button type="button" class="kind-card kind-momo" :disabled="!mobileAllowed" @click="choose('mobile_money')">
        <span class="kind-ico"><Smartphone class="size-6" /></span>
        <span class="min-w-0 flex-1 text-left">
          <span class="block text-base font-semibold">Mobile money</span>
          <span class="block text-xs opacity-80">{{ mobileAllowed ? 'MTN or Airtel from a tenant without a smartphone' : 'Only for tenants without a smartphone. Others send it in the app.' }}</span>
        </span>
        <ChevronRight class="size-5 opacity-70" />
      </button>
    </div>

    <!-- 2. Details -->
    <form v-else-if="step === 'form'" class="space-y-4" @submit.prevent="save">
      <button type="button" class="-mt-1 inline-flex items-center gap-1 text-sm font-medium text-slate-500 hover:text-slate-800" @click="step = 'choose'">
        <ArrowLeft class="size-4" /> Change payment type
      </button>

      <div>
        <p class="label">Tenant</p>
        <TenantPicker
          v-model="tenantId"
          :tenants="tenants"
          :empty="method === 'mobile_money' ? 'No tenants without a smartphone.' : 'No tenants yet.'"
        />
        <p v-if="method === 'mobile_money'" class="mt-1.5 text-xs text-slate-500">Only tenants without a smartphone. Tenants with the app send mobile money themselves and you confirm it.</p>
      </div>

      <div v-if="method === 'mobile_money'">
        <p class="label">Network it came on</p>
        <div class="grid grid-cols-2 gap-2">
          <button
            v-for="id in NETWORK_IDS"
            :key="id"
            type="button"
            class="flex h-11 items-center justify-center gap-1.5 rounded-xl text-sm font-semibold ring-1 transition"
            :class="network === id ? `net-${id} ring-2` : 'bg-white text-slate-600 ring-slate-200'"
            :style="network === id ? { '--tw-ring-color': NETWORKS[id].bg } : null"
            @click="network = id"
          >
            <span class="size-2.5 rounded-full" :style="{ background: NETWORKS[id].bg }" /> {{ NETWORKS[id].short }}
          </button>
        </div>
      </div>

      <template v-if="tenant">
        <div class="grid grid-cols-2 gap-3">
          <div>
            <label class="label" for="rp-amount">Amount (UGX)</label>
            <input id="rp-amount" v-model="amount" type="text" inputmode="numeric" class="input" placeholder="e.g. 500000" data-cap="off" required />
            <button v-if="total" type="button" class="mt-1 text-xs font-medium text-brand-600" @click="amount = String(total)">All owed · {{ formatUGX(total) }}</button>
            <button v-else-if="rent" type="button" class="mt-1 text-xs font-medium text-brand-600" @click="amount = String(rent)">One month · {{ formatUGX(rent) }}</button>
          </div>
          <div>
            <label class="label" for="rp-date">Date paid</label>
            <div class="relative">
              <CalendarDays class="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-slate-400" />
              <input id="rp-date" v-model="paidOn" type="date" class="input pl-9" :max="today()" required />
            </div>
          </div>
        </div>

        <!-- How long it lasts (part payments buy days) -->
        <p v-if="firstPayment && paidOn" class="flex items-start gap-2.5 rounded-2xl bg-sky-50 p-3 text-sm text-sky-900">
          <Info class="mt-0.5 size-4 shrink-0" /> First payment: their rental time starts on <strong>{{ formatDate(paidOn) }}</strong>.
        </p>
        <PaymentCoverage v-if="value && paidOn" :tenant="tenant" :dues="dues" :rent="rent" :amount="value" :pay-day="paidOn" :you="false" />

        <!-- Where the money goes -->
        <div v-if="value && (plan.length || extraMonths)" class="overflow-hidden rounded-2xl ring-1 ring-slate-200">
          <ul class="divide-y divide-slate-100 text-sm">
            <li v-for="p in plan.filter((x) => x.take)" :key="p.id" class="flex items-center justify-between gap-3 px-3 py-2">
              <span class="text-slate-700">{{ formatPeriod(p.period) }}</span>
              <span class="text-xs font-medium" :class="p.after ? 'text-amber-700' : 'text-emerald-700'">+{{ formatUGX(p.take) }} · {{ p.after ? `${formatUGX(p.after)} left` : 'paid' }}</span>
            </li>
            <li v-if="debtMonths" class="flex items-center justify-between gap-3 px-3 py-2">
              <span class="text-slate-700">Unpaid months paid</span>
              <span class="text-xs font-medium text-emerald-700">{{ debtMonths }} month{{ debtMonths === 1 ? '' : 's' }}</span>
            </li>
            <li v-if="aheadMonths" class="flex items-center justify-between gap-3 bg-sky-50/60 px-3 py-2">
              <span class="text-slate-700">Extra months paid</span>
              <span class="text-xs font-medium text-sky-700">{{ aheadMonths }} month{{ aheadMonths === 1 ? '' : 's' }}</span>
            </li>
          </ul>
          <p v-if="balanceAfter" class="bg-slate-50 px-3 py-2 text-xs text-slate-600">They'll still owe <strong class="text-slate-900">{{ formatUGX(balanceAfter) }}</strong>.</p>
        </div>

        <div>
          <label class="label" for="rp-note">Note <span class="font-normal text-slate-400">(optional)</span></label>
          <input id="rp-note" v-model="note" class="input" maxlength="200" :placeholder="method === 'cash' ? 'e.g. Paid at the gate' : 'e.g. Transaction ID'" />
        </div>
        <p class="flex items-center gap-2 text-xs text-slate-500">
          <MessageSquareText class="size-4 shrink-0 text-brand-600" /> {{ tenant.name.split(' ')[0] }} gets a notification that it was received.
        </p>
      </template>

      <p v-if="error" class="form-error" role="alert">{{ error }}</p>

      <div class="grid grid-cols-2 gap-2 pt-1">
        <button type="button" class="btn-secondary h-11" @click="open = false">Cancel</button>
        <button :data-busy="Boolean(busy)" type="submit" class="btn-primary h-11" :disabled="busy || !tenantId || !value || tooMuch || noRent">
          {{ busy ? 'Saving…' : `Record ${value ? formatUGX(value) : ''}` }}
        </button>
      </div>
    </form>

    <!-- 3. Done -->
    <div v-else class="py-2 text-center">
      <span class="done-ring mx-auto flex size-16 items-center justify-center rounded-full bg-emerald-50 text-emerald-600"><CheckCircle2 class="size-9" /></span>
      <p class="mt-4 text-lg font-semibold text-slate-900">{{ formatUGX(result.amount) }} recorded</p>
      <p class="mt-1 text-sm text-slate-600">
        Added to {{ result.name }}'s rent as {{ method === 'cash' ? 'cash' : 'mobile money' }}<template v-if="result.paidTo">. Their time now runs to {{ formatDate(result.paidTo) }}</template>.
        <template v-if="result.phone"> A notification is on its way to {{ result.name }}.</template>
      </p>
      <button class="btn-primary mt-6 h-11 w-full" @click="open = false">Done</button>
    </div>
  </BaseModal>
</template>

<style scoped>
.kind-card {
  display: flex;
  width: 100%;
  align-items: center;
  gap: 0.9rem;
  border-radius: 1.25rem;
  padding: 1rem;
  color: #fff;
  transition: transform 0.15s ease, box-shadow 0.15s ease, opacity 0.15s ease;
}
.kind-card:not(:disabled):hover { transform: translateY(-2px); }
.kind-card:not(:disabled):active { transform: scale(0.98); }
.kind-card:disabled { opacity: 0.5; cursor: not-allowed; }
.kind-cash { background: linear-gradient(135deg, #14b8a6 0%, #0f766e 55%, #0a3b38 100%); box-shadow: 0 14px 28px -16px rgb(15 118 110 / 0.9); }
.kind-momo { background: linear-gradient(135deg, #f59e0b 0%, #d97706 45%, #9a3412 100%); box-shadow: 0 14px 28px -16px rgb(180 83 9 / 0.9); }
.kind-ico {
  display: flex;
  width: 3rem;
  height: 3rem;
  flex-shrink: 0;
  align-items: center;
  justify-content: center;
  border-radius: 0.95rem;
  background: rgb(var(--glass) / 0.18);
  box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.25);
}
.done-ring { animation: pop 0.45s cubic-bezier(0.34, 1.56, 0.64, 1); }
@keyframes pop { from { transform: scale(0.6); opacity: 0; } }
</style>
