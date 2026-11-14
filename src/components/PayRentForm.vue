<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { Smartphone, CheckCircle2, XCircle, ExternalLink, FlaskConical, ShieldCheck, Lock, Banknote } from '@lucide/vue'
import { api } from '@/lib/api'
import { useTenant } from '@/composables/useTenant'
import { formatUGX, formatPeriod } from '@/utils/format'

// Tenant pays with MTN MoMo or Airtel Money. Nothing is pre-filled: they type the number that will pay,
// the network is worked out from it, a prompt goes to that phone, and the server confirms the payment
// with the provider before any rent is marked paid.
// `payment`: pay one rent charge.  `recharge`: { months, total }: unpaid rent + months ahead (Recharge page).
const props = defineProps({ payment: Object, recharge: Object })
const amount = computed(() => (props.recharge ? props.recharge.total : props.payment?.balance))
const emit = defineEmits(['paid', 'cancel'])

const { tenant } = useTenant()

const NETWORKS = {
  MTN: { label: 'MTN MoMo', dot: '#ffcc00', ring: 'ring-[#ffcc00]/60', bg: 'bg-[#fff8d6]', text: 'text-[#5c4a00]' },
  AIRTEL: { label: 'Airtel Money', dot: '#e40000', ring: 'ring-[#e40000]/40', bg: 'bg-[#fdeaea]', text: 'text-[#8a0f0f]' },
}
const phone = ref('')
const picked = ref(null) // only used if the number's network can't be told from its prefix
const step = ref('form') // form | waiting | success | failed
const busy = ref(false)
const error = ref('')
const attempt = ref(null)
const info = ref(null) // { enabled, testMode }
let timer = null
let polls = 0

onMounted(async () => {
  try {
    info.value = await api('/api/payments/info')
  } catch {
    info.value = { enabled: true } // server unreachable: the pay call will explain
  }
})

const digits = computed(() => {
  const d = phone.value.replace(/\D/g, '')
  return d.startsWith('256') ? d.slice(3) : d.startsWith('0') ? d.slice(1) : d
})
const validNumber = computed(() => /^7\d{8}$/.test(digits.value))
const detected = computed(() => {
  if (/^7[6789]/.test(digits.value)) return 'MTN'
  if (/^7[045]/.test(digits.value)) return 'AIRTEL'
  return null
})
const network = computed(() => detected.value ?? picked.value)
const myNumber = computed(() => {
  const d = String(tenant.value?.phone ?? '').replace(/\D/g, '')
  return d.length >= 9 ? `0${d.slice(-9)}` : null
})

const networkLabel = computed(() => NETWORKS[attempt.value?.network ?? network.value]?.label ?? 'mobile money')
const shownPhone = computed(() => (attempt.value?.phone ?? '').replace(/^256/, '0'))
const canPay = computed(() => validNumber.value && network.value && amount.value > 0 && !busy.value)

async function pay() {
  error.value = ''
  busy.value = true
  try {
    const body = { network: network.value, phone: phone.value }
    const a = props.recharge
      ? await api('/api/momo/recharge', { months: props.recharge.months, ...body })
      : await api('/api/momo/pay', { paymentId: props.payment.id, ...body })
    handle(a)
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}

function handle(a) {
  attempt.value = a
  if (a.status === 'successful') return succeed()
  if (a.status === 'failed') {
    step.value = 'failed'
    return stop()
  }
  step.value = 'waiting'
  if (!timer) timer = setInterval(poll, 4000)
}

async function poll() {
  if (!attempt.value) return
  polls++
  try {
    handle(await api('/api/momo/status', { attemptId: attempt.value.attemptId }))
  } catch {
    /* keep waiting; the server also confirms in the background */
  }
  if (polls > 240) stop() // ~16 min
}

function succeed() {
  step.value = 'success'
  stop()
  setTimeout(() => emit('paid'), 2200)
}
function stop() {
  clearInterval(timer)
  timer = null
}
function retry() {
  stop()
  polls = 0
  attempt.value = null
  step.value = 'form'
}
onBeforeUnmount(stop)
</script>

<template>
  <div>
    <div v-if="payment && step === 'form'" class="mb-5 rounded-2xl bg-slate-50 p-4">
      <p class="text-sm text-slate-500">Rent for {{ formatPeriod(payment.period) }}</p>
      <p class="mt-1 text-2xl font-bold tracking-tight text-slate-900 tabular-nums">{{ formatUGX(payment.balance) }}</p>
      <p v-if="payment.amountPaid" class="mt-0.5 text-xs text-slate-500">{{ formatUGX(payment.amountPaid) }} of {{ formatUGX(payment.amount) }} already paid</p>
    </div>

    <!-- Online payments not switched on -->
    <div v-if="info && !info.enabled" class="rounded-2xl border border-amber-200 bg-amber-50 p-5 text-center">
      <span class="mx-auto flex size-12 items-center justify-center rounded-2xl bg-amber-100 text-amber-700"><Banknote class="size-6" /></span>
      <p class="mt-3 font-semibold text-amber-900">Mobile money payments aren't available yet</p>
      <p class="mt-1 text-sm text-amber-800">Please pay your landlord in cash for now. They record it and your rent updates straight away.</p>
      <button type="button" class="btn-secondary mt-4" @click="emit('cancel')">Close</button>
    </div>

    <!-- 1. Number that pays -->
    <form v-else-if="step === 'form'" class="space-y-4" @submit.prevent="pay">
      <div>
        <label class="label" for="momo-phone">Mobile money number</label>
        <div class="relative">
          <span class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3.5 text-slate-400"><Smartphone class="size-4.5" /></span>
          <input
            id="momo-phone"
            v-model="phone"
            type="tel"
            inputmode="tel"
            class="input h-13 pr-32 pl-10 text-base tracking-wide"
            placeholder="07XX XXX XXX"
            autocomplete="off"
            data-cap="off"
            required
          />
          <Transition enter-active-class="transition duration-200" enter-from-class="opacity-0 scale-90" leave-active-class="transition duration-150" leave-to-class="opacity-0 scale-90">
            <span
              v-if="detected"
              class="absolute inset-y-0 right-2.5 my-auto flex h-8 items-center gap-1.5 rounded-full px-3 text-xs font-semibold ring-1"
              :class="[NETWORKS[detected].bg, NETWORKS[detected].text, NETWORKS[detected].ring]"
            >
              <span class="size-2.5 rounded-full" :style="{ background: NETWORKS[detected].dot }" /> {{ NETWORKS[detected].label }}
            </span>
          </Transition>
        </div>
        <button
          v-if="myNumber && !phone"
          type="button"
          class="mt-2 inline-flex h-8 items-center gap-1.5 rounded-full bg-brand-50 px-3 text-xs font-semibold text-brand-700 transition hover:bg-brand-100"
          @click="phone = myNumber"
        >
          Use my number {{ myNumber }}
        </button>
        <p v-else class="mt-1.5 text-xs text-slate-500">MTN or Airtel. A prompt comes to this phone: approve it with your PIN.</p>
      </div>

      <!-- Network only asked when the number doesn't tell us -->
      <div v-if="validNumber && !detected">
        <p class="label">Which network is this number on?</p>
        <div class="grid grid-cols-2 gap-2.5">
          <button
            v-for="(n, id) in NETWORKS"
            :key="id"
            type="button"
            class="flex h-12 items-center justify-center gap-2 rounded-xl border text-sm font-semibold transition"
            :class="picked === id ? 'border-brand-500 bg-brand-50 text-slate-900 ring-2 ring-brand-100' : 'border-slate-200 text-slate-700'"
            @click="picked = id"
          >
            <span class="size-2.5 rounded-full" :style="{ background: n.dot }" /> {{ n.label }}
          </button>
        </div>
      </div>

      <p v-if="error" class="rounded-xl bg-red-50 p-3 text-sm text-red-700">{{ error }}</p>

      <div class="flex gap-2.5 pt-1">
        <button type="button" class="btn-secondary h-12 flex-1 rounded-2xl" :disabled="busy" @click="emit('cancel')">Cancel</button>
        <button :data-busy="Boolean(busy)" type="submit" class="btn-primary h-12 flex-[2] rounded-2xl text-[0.95rem]" :disabled="!canPay">
          <Lock class="size-4" /> {{ busy ? 'Sending prompt…' : amount ? `Pay ${formatUGX(amount)}` : 'Pay' }}
        </button>
      </div>
      <p class="flex items-center justify-center gap-1.5 text-[11px] text-slate-400">
        <ShieldCheck class="size-3.5" /> Confirmed with the network before your rent updates
      </p>
    </form>

    <!-- 2. Waiting for approval on the phone -->
    <div v-else-if="step === 'waiting'" class="py-3 text-center">
      <div class="phone-pulse mx-auto flex size-16 items-center justify-center rounded-2xl bg-brand-50 text-brand-600">
        <Smartphone class="size-8" />
      </div>
      <p class="mt-4 text-lg font-semibold text-slate-900">Check your phone</p>
      <p class="mx-auto mt-1 max-w-xs text-sm text-slate-600">
        Approve the {{ networkLabel }} prompt on <strong>{{ shownPhone }}</strong> with your PIN. We confirm it automatically.
      </p>
      <a v-if="attempt?.redirectUrl" :href="attempt.redirectUrl" target="_blank" rel="noopener" class="btn-secondary mt-4">
        <ExternalLink class="size-4" /> No prompt? Open the approval page
      </a>
      <div class="mx-auto mt-5 h-1 w-40 overflow-hidden rounded-full bg-slate-100">
        <div class="skeleton h-full w-full rounded-full bg-brand-200" />
      </div>
      <p v-if="attempt?.testMode" class="mt-4 inline-flex items-center gap-1.5 rounded-full bg-amber-50 px-3 py-1 text-xs text-amber-800">
        <FlaskConical class="size-3.5" /> Test mode: no real money moves.
      </p>
      <p class="mt-4 text-xs text-slate-400">You can close this. We'll notify you once it's confirmed.</p>
      <button class="btn-ghost mt-2 text-sm" @click="emit('cancel')">Close</button>
    </div>

    <!-- 3. Done -->
    <div v-else-if="step === 'success'" class="py-5 text-center">
      <CheckCircle2 class="pop mx-auto size-14 text-emerald-600" />
      <p class="mt-3 text-lg font-semibold text-slate-900">Payment confirmed</p>
      <p class="mt-1 text-sm text-slate-600">Your rent has been updated. Thank you!</p>
    </div>

    <!-- 4. Failed -->
    <div v-else class="py-5 text-center">
      <XCircle class="mx-auto size-14 text-red-500" />
      <p class="mt-3 text-lg font-semibold text-slate-900">Payment not completed</p>
      <p class="mt-1 text-sm text-slate-600">{{ attempt?.reason || 'The payment was declined or timed out.' }} No money was taken.</p>
      <div class="mt-5 flex justify-center gap-2">
        <button class="btn-secondary" @click="emit('cancel')">Close</button>
        <button class="btn-primary" @click="retry">Try again</button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.phone-pulse { animation: ring 1.8s ease-out infinite; }
.pop { animation: pop 0.45s cubic-bezier(0.34, 1.56, 0.64, 1); }
@keyframes ring {
  0% { box-shadow: 0 0 0 0 rgb(20 184 166 / 0.35); }
  100% { box-shadow: 0 0 0 16px rgb(20 184 166 / 0); }
}
@keyframes pop { from { transform: scale(0.6); opacity: 0; } }
@media (prefers-reduced-motion: reduce) {
  .phone-pulse, .pop { animation: none; }
}
</style>
