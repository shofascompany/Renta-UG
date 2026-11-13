<script setup>
import { computed, onBeforeUnmount, ref } from 'vue'
import { Smartphone, CheckCircle2, XCircle, ExternalLink, FlaskConical } from '@lucide/vue'
import { api } from '@/lib/api'
import { useTenant } from '@/composables/useTenant'
import { formatUGX, formatPeriod } from '@/utils/format'

// Tenant pays a rent charge with MTN Mobile Money or Airtel Money.
// The server sends the payment prompt, verifies it with the provider, marks the rent paid and
// sends a "payment received" notification (which also pops up on the phone).
const props = defineProps({ payment: { type: Object, required: true } })
const emit = defineEmits(['paid', 'cancel'])

const { tenant } = useTenant()

const networks = [
  { id: 'MTN', label: 'MTN MoMo', dot: 'bg-[#ffcc00]' },
  { id: 'AIRTEL', label: 'Airtel Money', dot: 'bg-[#e40000]' },
]
const network = ref(guessNetwork(tenant.value?.phone) ?? 'MTN')
const phone = ref(tenant.value?.phone ?? '')
const step = ref('form') // form | waiting | success | failed
const busy = ref(false)
const error = ref('')
const attempt = ref(null)
let timer = null
let polls = 0

function guessNetwork(p) {
  const d = String(p ?? '').replace(/\D/g, '')
  const local = d.startsWith('256') ? d.slice(3) : d.startsWith('0') ? d.slice(1) : d
  if (/^7[678]/.test(local)) return 'MTN'
  if (/^7[045]/.test(local)) return 'AIRTEL'
  return null
}

const networkLabel = computed(() => networks.find((n) => n.id === (attempt.value?.network ?? network.value))?.label)
const shownPhone = computed(() => (attempt.value?.phone ?? '').replace(/^256/, '0'))

async function pay() {
  error.value = ''
  busy.value = true
  try {
    const a = await api('/api/momo/pay', { paymentId: props.payment.id, network: network.value, phone: phone.value })
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
  setTimeout(() => emit('paid'), 1800)
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
    <div class="mb-5 rounded-lg bg-slate-50 p-4">
      <p class="text-sm text-slate-500">Rent for {{ formatPeriod(payment.period) }}</p>
      <p class="mt-1 text-2xl font-semibold tracking-tight text-slate-900">{{ formatUGX(payment.balance) }}</p>
      <p v-if="payment.amountPaid" class="mt-0.5 text-xs text-slate-500">{{ formatUGX(payment.amountPaid) }} of {{ formatUGX(payment.amount) }} already paid</p>
    </div>

    <!-- 1. Choose network + number -->
    <form v-if="step === 'form'" class="space-y-4" @submit.prevent="pay">
      <div>
        <p class="label">Pay with</p>
        <div class="grid grid-cols-2 gap-3">
          <button
            v-for="n in networks"
            :key="n.id"
            type="button"
            class="flex items-center gap-2.5 rounded-xl border px-4 py-3 text-left text-sm font-medium transition-colors"
            :class="network === n.id ? 'border-brand-500 bg-brand-50/50 text-slate-900 ring-2 ring-brand-100' : 'border-slate-200 text-slate-700 hover:bg-slate-50'"
            :aria-pressed="network === n.id"
            @click="network = n.id"
          >
            <span class="size-3 shrink-0 rounded-full" :class="n.dot" />
            {{ n.label }}
          </button>
        </div>
      </div>

      <div>
        <label class="label" for="momo-phone">{{ network === 'MTN' ? 'MTN' : 'Airtel' }} number</label>
        <input
          id="momo-phone"
          v-model="phone"
          type="tel"
          inputmode="tel"
          class="input"
          placeholder="07XX XXX XXX"
          autocomplete="tel"
          required
        />
        <p class="mt-1 text-xs text-slate-500">You'll get a prompt on this phone to approve the payment with your PIN.</p>
      </div>

      <p v-if="error" class="rounded-lg bg-red-50 p-3 text-sm text-red-700">{{ error }}</p>

      <div class="flex gap-2 pt-1">
        <button type="button" class="btn-secondary flex-1" :disabled="busy" @click="emit('cancel')">Cancel</button>
        <button type="submit" class="btn-primary flex-1" :disabled="busy">
          <Smartphone class="size-4" /> {{ busy ? 'Sending prompt…' : `Pay ${formatUGX(payment.balance)}` }}
        </button>
      </div>
    </form>

    <!-- 2. Waiting for approval on the phone -->
    <div v-else-if="step === 'waiting'" class="py-2 text-center">
      <div class="mx-auto mb-4 flex size-12 items-center justify-center rounded-full bg-brand-50">
        <Smartphone class="size-6 text-brand-600" />
      </div>
      <p class="font-medium text-slate-900">Check your phone</p>
      <p class="mt-1 text-sm text-slate-600">
        Approve the {{ networkLabel }} prompt on <strong>{{ shownPhone }}</strong> and enter your PIN.
        We'll confirm automatically. You can close this window if you like.
      </p>
      <a
        v-if="attempt?.redirectUrl"
        :href="attempt.redirectUrl"
        target="_blank"
        rel="noopener"
        class="btn-secondary mt-4"
      >
        <ExternalLink class="size-4" /> No prompt? Open the approval page
      </a>
      <div class="mx-auto mt-5 h-1 w-40 overflow-hidden rounded-full bg-slate-100">
        <div class="skeleton h-full w-full rounded-full bg-brand-200" />
      </div>
      <p v-if="attempt?.testMode" class="mt-4 inline-flex items-center gap-1.5 rounded-full bg-amber-50 px-3 py-1 text-xs text-amber-800">
        <FlaskConical class="size-3.5" /> Test mode: no real money. This will approve itself in a few seconds.
      </p>
      <div class="mt-5">
        <button class="btn-ghost text-sm" @click="emit('cancel')">Close</button>
      </div>
    </div>

    <!-- 3. Done -->
    <div v-else-if="step === 'success'" class="py-4 text-center">
      <CheckCircle2 class="mx-auto size-12 text-emerald-600" />
      <p class="mt-3 font-medium text-slate-900">Payment received</p>
      <p class="mt-1 text-sm text-slate-600">Thank you! A confirmation has been sent to your notifications.</p>
    </div>

    <!-- 4. Failed -->
    <div v-else class="py-4 text-center">
      <XCircle class="mx-auto size-12 text-red-500" />
      <p class="mt-3 font-medium text-slate-900">Payment not completed</p>
      <p class="mt-1 text-sm text-slate-600">{{ attempt?.reason || 'The payment was declined or timed out.' }} No money was taken.</p>
      <div class="mt-5 flex justify-center gap-2">
        <button class="btn-secondary" @click="emit('cancel')">Close</button>
        <button class="btn-primary" @click="retry">Try again</button>
      </div>
    </div>
  </div>
</template>
