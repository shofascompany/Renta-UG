<script setup>
import { computed, reactive, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  ArrowLeft, ArrowRight, Copy, Check, Phone, Send, Clock, ChevronRight, ShieldCheck, Info, BadgeCheck, CircleAlert,
  Smartphone, User, Wallet, TriangleAlert,
} from '@lucide/vue'
import { useTenant } from '@/composables/useTenant'
import { formatUGX, formatDate } from '@/utils/format'
import { nextCycle } from '@/utils/rentCycle'
import { NETWORKS, NETWORK_IDS, prettyPhone, dialCodeOf, dialHref, sendSteps, validUgPhone } from '@/lib/networks'
import { copyText } from '@/lib/clipboard'

// Tenant pays rent with mobile money, straight to the landlord's number. One card at a time:
//   1. /tenant/pay                     → choose the SIM to pay to (MTN or Airtel)
//   2. /tenant/pay?sim=mtn&step=from   → the number you are paying FROM, its registered names, the amount
//   3. /tenant/pay?sim=mtn&step=review → all the details: landlord's number + your payment word (copy),
//                                         the steps, a dial button, then "Submit payment"
//   4. Waiting for approval: the landlord checks the money and approves it
const route = useRoute()
const router = useRouter()
const { rental, tenant, property } = useTenant()

const suggested = computed(() => Math.max(0, Math.round(Number(route.query.amount) || 0)) || property.value?.rent || 0)
const label = computed(() => String(route.query.label || 'Rent'))
const sim = computed(() => (NETWORK_IDS.includes(route.query.sim) ? route.query.sim : null))
const step = computed(() => (!sim.value ? 'sim' : route.query.step === 'review' && fromOk.value ? 'review' : 'from'))
const stepNo = computed(() => ({ sim: 1, from: 2, review: 3 })[step.value])

const accounts = computed(() => (tenant.value ? rental.payAccountsOf(tenant.value.landlordId) : []))
const accountFor = (id) => accounts.value.find((a) => a.network === id)
const account = computed(() => (sim.value ? accountFor(sim.value) : null))
const net = computed(() => (sim.value ? NETWORKS[sim.value] : null))
const code = computed(() => tenant.value?.payCode || '—')
const landlordName = computed(() => rental.owner?.full_name || 'your landlord')

// ── Card 2: who is paying, and how much ──
const from = reactive({ phone: '', name: '' })
watch(
  tenant,
  (t) => {
    if (!t) return
    if (!from.phone && t.phone) from.phone = prettyPhone(t.phone)
    if (!from.name && t.name && t.name !== 'New tenant') from.name = t.name
  },
  { immediate: true },
)
const typed = ref('')
watch(suggested, (v) => (typed.value = typed.value || String(v || '')), { immediate: true })
const amount = computed(() => Math.round(Number(String(typed.value).replace(/[^\d]/g, '')) || 0))

// Which network a Ugandan number belongs to (to warn if it doesn't match the chosen SIM)
const networkOf = (v) => {
  const d = String(v ?? '').replace(/\D/g, '').slice(-9)
  if (/^7[6789]|^3[19]/.test(d)) return 'mtn'
  if (/^7[045]|^20/.test(d)) return 'airtel'
  return null
}
const phoneError = computed(() => (from.phone && !validUgPhone(from.phone) ? 'Enter a valid number, e.g. 0772 123456.' : ''))
const otherNetwork = computed(() => {
  const n = networkOf(from.phone)
  return validUgPhone(from.phone) && n && n !== sim.value ? NETWORKS[n] : null
})
const amountError = computed(() => (typed.value && amount.value < 500 ? 'Enter at least UGX 500.' : ''))
const fromOk = computed(() => validUgPhone(from.phone) && from.name.trim().length >= 3 && amount.value >= 500)

// Late? The unpaid days come out of the next month.
const cycle = computed(() => (tenant.value ? nextCycle(tenant.value) : null))

const steps = computed(() => (account.value ? sendSteps(account.value, { amount: amount.value, code: code.value }) : []))
const dial = computed(() => dialCodeOf(account.value))

// ── Copy buttons ──
const copied = ref('')
async function copy(what, text) {
  if (await copyText(text)) {
    copied.value = what
    setTimeout(() => copied.value === what && (copied.value = ''), 1800)
  }
}
const localNumber = (p) => {
  const d = String(p ?? '').replace(/\D/g, '')
  return d.length >= 9 ? `0${d.slice(-9)}` : d
}

// ── Moving between the cards ──
const go = (q) => router.push({ query: { ...route.query, ...q } })
function pickSim(id) {
  if (accountFor(id)) go({ sim: id, step: 'from' })
}
const touched = ref(false)
function next() {
  touched.value = true
  if (fromOk.value) go({ step: 'review' })
}
function back() {
  if (step.value === 'review') return go({ step: 'from' })
  if (step.value === 'from') return go({ sim: undefined, step: undefined })
  return window.history.state?.back ? router.back() : router.push('/tenant/payments')
}

// ── Submit payment → waiting for approval ──
const busy = ref(false)
const error = ref('')
const sent = ref(false)
async function submit() {
  busy.value = true
  error.value = ''
  try {
    await rental.submitPayment({
      amount: amount.value,
      method: 'mobile_money',
      network: sim.value,
      note: `From ${localNumber(from.phone)} (${from.name.trim().toUpperCase()}) · Reason ${code.value}`,
    })
    sent.value = true
    window.scrollTo({ top: 0, behavior: 'smooth' })
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <div class="mx-auto max-w-lg pb-40">
    <!-- Back + progress -->
    <div class="sticky top-0 z-20 -mx-4 mb-4 bg-[var(--color-slate-50)]/85 px-4 py-2 backdrop-blur-lg sm:static sm:mx-0 sm:bg-transparent sm:px-0 sm:backdrop-blur-none">
      <div class="flex items-center gap-2">
        <button v-if="!sent" type="button" class="flex h-11 items-center gap-1.5 rounded-2xl bg-white pr-4 pl-3 text-sm font-semibold text-slate-700 shadow-sm ring-1 ring-slate-200 active:scale-95" @click="back">
          <ArrowLeft class="size-[1.1rem]" /> Back
        </button>
        <p class="ml-auto text-xs font-semibold tracking-[0.12em] text-slate-400 uppercase">{{ sent ? 'Submitted' : `Step ${stepNo} of 3` }}</p>
      </div>
      <div v-if="!sent" class="mt-3 grid grid-cols-3 gap-1.5" aria-hidden="true">
        <span v-for="n in 3" :key="n" class="h-1.5 rounded-full transition-colors duration-500" :class="n <= stepNo ? 'bg-brand-600' : 'bg-slate-200'" />
      </div>
    </div>

    <!-- ── 4. Waiting for approval ── -->
    <section v-if="sent" class="card-in text-center">
      <div class="review-ring mx-auto flex size-20 items-center justify-center rounded-full bg-amber-50 text-amber-600">
        <Clock class="size-9" />
      </div>
      <h1 class="mt-5 text-2xl font-bold tracking-tight text-slate-900">Waiting for approval</h1>
      <p class="mx-auto mt-2 max-w-sm text-[15px] leading-relaxed text-slate-600">
        Your payment of <strong class="text-slate-900">{{ formatUGX(amount) }}</strong> on {{ net?.short }} was submitted.
        It will be approved as soon as {{ landlordName }} confirms the money arrived.
      </p>
      <div class="sheet mx-auto mt-6 max-w-sm p-4 text-left text-sm">
        <p class="flex items-center gap-2 font-medium text-slate-900"><BadgeCheck class="size-4.5 text-brand-600" /> What happens next</p>
        <ul class="mt-2 space-y-1.5 text-slate-600">
          <li>• Your payment is checked and approved.</li>
          <li>• You get a notification and an SMS once it is approved.</li>
          <li>• Your rent and balance update everywhere.</li>
        </ul>
      </div>
      <div class="mx-auto mt-6 grid max-w-sm gap-2.5">
        <RouterLink to="/tenant/payments" class="btn-primary h-12 rounded-2xl">See my payments</RouterLink>
        <RouterLink to="/tenant" class="btn-secondary h-12 rounded-2xl">Home</RouterLink>
      </div>
    </section>

    <template v-else>
      <!-- Amount -->
      <header class="amount-card card-in relative overflow-hidden rounded-3xl p-5 text-white" :style="net ? { background: net.gradient, color: net.ink } : null">
        <p class="text-xs font-semibold tracking-[0.14em] uppercase opacity-75">{{ label }}</p>
        <p class="mt-1 text-[2rem] leading-tight font-bold tracking-tight tabular-nums">{{ formatUGX(amount) }}</p>
        <p class="mt-0.5 text-sm opacity-80">{{ property?.name }}</p>
      </header>

      <!-- Debt days come out of the next month -->
      <div v-if="cycle?.debtDays && step === 'sim'" class="card-in mt-3 flex items-start gap-3 rounded-2xl border border-amber-200 bg-amber-50 p-3.5 text-sm text-amber-900">
        <CircleAlert class="mt-0.5 size-4.5 shrink-0 text-amber-600" />
        <p>
          Your last month ended on <strong>{{ formatDate(tenant.leaseEnd) }}</strong>, so you have <strong>{{ cycle.debtDays }} debt day{{ cycle.debtDays === 1 ? '' : 's' }}</strong>.
          They are taken from this month: paying today covers you up to <strong>{{ formatDate(cycle.end) }}</strong> ({{ cycle.days }} days).
        </p>
      </div>

      <Transition name="card" mode="out-in">
        <!-- ── 1. Choose the SIM to pay to ── -->
        <section v-if="step === 'sim'" key="sim" class="mt-6">
          <h1 class="text-xl font-bold tracking-tight text-slate-900">Select the SIM you want to pay to</h1>
          <p class="mt-1 text-sm text-slate-500">You send the money from your phone, straight to {{ landlordName }}.</p>

          <div class="mt-4 grid gap-3">
            <button
              v-for="id in NETWORK_IDS"
              :key="id"
              type="button"
              class="sim-card group flex items-center gap-4 rounded-2xl bg-white p-4 text-left ring-1 ring-slate-200 transition"
              :class="accountFor(id) ? 'hover:-translate-y-0.5 hover:shadow-lg active:scale-[0.98]' : 'cursor-not-allowed opacity-55'"
              :disabled="!accountFor(id)"
              @click="pickSim(id)"
            >
              <span class="sim-chip flex size-14 shrink-0 items-center justify-center rounded-2xl text-sm font-extrabold" :style="{ background: NETWORKS[id].gradient, color: NETWORKS[id].ink }">
                {{ NETWORKS[id].short.toUpperCase() }}
              </span>
              <span class="min-w-0 flex-1">
                <span class="block font-semibold text-slate-900">{{ NETWORKS[id].label }}</span>
                <span class="block truncate text-xs text-slate-500">
                  {{ accountFor(id) ? `Pay to ${accountFor(id).accountName}` : 'Your landlord has not added this network' }}
                </span>
              </span>
              <ChevronRight v-if="accountFor(id)" class="size-5 shrink-0 text-slate-300 transition group-hover:translate-x-0.5 group-hover:text-slate-500" />
            </button>
          </div>

          <div v-if="!accounts.length" class="mt-4 rounded-2xl border border-slate-200 bg-white p-4 text-sm text-slate-600">
            <p class="font-medium text-slate-900">Mobile money isn't set up yet</p>
            <p class="mt-1">Your landlord hasn't added the number they receive money on. Pay them in cash for now, or ask them to add it in Renta.</p>
          </div>
          <p class="mt-5 flex items-center justify-center gap-1.5 text-xs text-slate-400"><ShieldCheck class="size-3.5" /> Renta never asks for your PIN</p>
        </section>

        <!-- ── 2. The number you pay with ── -->
        <section v-else-if="step === 'from' && account" key="from" class="mt-6">
          <h1 class="text-xl font-bold tracking-tight text-slate-900">Your payment details</h1>
          <p class="mt-1 text-sm text-slate-500">The number you are paying with and the names it is registered in.</p>

          <form class="sheet mt-4 space-y-4 p-4" @submit.prevent="next">
            <div>
              <label class="label" for="from-phone">Number you are paying with</label>
              <div class="relative">
                <Smartphone class="pointer-events-none absolute top-1/2 left-3.5 size-4.5 -translate-y-1/2 text-slate-400" />
                <input id="from-phone" v-model="from.phone" type="tel" inputmode="tel" class="input h-12 pl-10 text-base tracking-wide" placeholder="0772 123 456" autocomplete="tel" data-cap="off" />
              </div>
              <p v-if="phoneError && (touched || from.phone.length > 9)" class="mt-1.5 text-xs text-red-600">{{ phoneError }}</p>
              <p v-else-if="otherNetwork" class="mt-1.5 flex items-start gap-1.5 text-xs text-amber-700">
                <TriangleAlert class="mt-px size-3.5 shrink-0" /> This looks like an {{ otherNetwork.short }} number, but you chose {{ net.short }}. Sending across networks can cost more.
              </p>
            </div>
            <div>
              <label class="label" for="from-name">Names registered on this number</label>
              <div class="relative">
                <User class="pointer-events-none absolute top-1/2 left-3.5 size-4.5 -translate-y-1/2 text-slate-400" />
                <input id="from-name" v-model="from.name" class="input h-12 pl-10 text-base" placeholder="e.g. John Mukasa" autocomplete="name" data-cap="words" />
              </div>
              <p v-if="touched && from.name.trim().length < 3" class="mt-1.5 text-xs text-red-600">Enter the names the number is registered in.</p>
              <p v-else class="mt-1.5 text-xs text-slate-500">Your landlord sees this name on the payment they receive.</p>
            </div>
            <div>
              <label class="label" for="pay-amount">Amount (UGX)</label>
              <div class="relative">
                <Wallet class="pointer-events-none absolute top-1/2 left-3.5 size-4.5 -translate-y-1/2 text-slate-400" />
                <input id="pay-amount" v-model="typed" class="input h-12 pl-10 text-lg font-semibold tabular-nums" inputmode="numeric" autocomplete="off" data-cap="off" />
              </div>
              <button v-if="suggested && amount !== suggested" type="button" class="amt-chip mt-2" @click="typed = String(suggested)">Full amount · {{ formatUGX(suggested) }}</button>
              <p v-if="amountError" class="mt-1.5 text-xs text-red-600">{{ amountError }}</p>
              <p v-else-if="property?.rent && amount && amount < Math.ceil(property.rent * 0.6)" class="mt-1.5 text-xs text-amber-700">
                Less than 60% of a month's rent ({{ formatUGX(Math.ceil(property.rent * 0.6)) }}) does not start a new month. It is kept as part payment.
              </p>
            </div>
            <button type="submit" class="hidden" aria-hidden="true" tabindex="-1" />
          </form>
        </section>

        <!-- ── 3. Review: everything in one place ── -->
        <section v-else-if="step === 'review' && account" key="review" class="mt-6 space-y-4">
          <div>
            <h1 class="text-xl font-bold tracking-tight text-slate-900">Check and pay</h1>
            <p class="mt-1 text-sm text-slate-500">Send the money, then tap Submit payment.</p>
          </div>

          <div class="sheet divide-y divide-slate-100">
            <div class="flex items-center gap-3 p-4">
              <div class="min-w-0 flex-1">
                <p class="text-xs font-medium text-slate-500">Send to ({{ net.label }})</p>
                <p class="mt-0.5 text-2xl font-bold tracking-wide text-slate-900 tabular-nums">{{ prettyPhone(account.phone) }}</p>
                <p class="mt-0.5 truncate text-sm text-slate-600">Name shown: <strong class="text-slate-900">{{ account.accountName.toUpperCase() }}</strong></p>
              </div>
              <button type="button" class="copy-btn" :class="copied === 'phone' && 'copy-done'" @click="copy('phone', localNumber(account.phone))">
                <Check v-if="copied === 'phone'" class="size-4" /><Copy v-else class="size-4" />
                {{ copied === 'phone' ? 'Copied' : 'Copy' }}
              </button>
            </div>
            <div class="flex items-center gap-3 p-4">
              <div class="min-w-0 flex-1">
                <p class="text-xs font-medium text-slate-500">Reason (type this exactly)</p>
                <p class="mt-0.5 font-mono text-2xl font-bold tracking-[0.12em] text-brand-700">{{ code }}</p>
              </div>
              <button type="button" class="copy-btn" :class="copied === 'code' && 'copy-done'" @click="copy('code', code)">
                <Check v-if="copied === 'code'" class="size-4" /><Copy v-else class="size-4" />
                {{ copied === 'code' ? 'Copied' : 'Copy' }}
              </button>
            </div>
            <div class="p-4">
              <p class="text-sm font-semibold text-slate-900">How to send</p>
              <ol class="mt-3 space-y-3">
                <li v-for="(s, i) in steps.slice(0, -1)" :key="i" class="flex gap-3 text-sm leading-relaxed text-slate-700">
                  <span class="step-no" :style="{ background: net.soft, color: sim === 'mtn' ? '#5c4a00' : net.bg }">{{ i + 1 }}</span>
                  <span class="pt-0.5">{{ s }}</span>
                </li>
                <li class="flex gap-3 text-sm leading-relaxed text-slate-700">
                  <span class="step-no" :style="{ background: net.soft, color: sim === 'mtn' ? '#5c4a00' : net.bg }">{{ steps.length }}</span>
                  <span class="pt-0.5">Come back here and tap <strong>Submit payment</strong>.</span>
                </li>
              </ol>
            </div>
          </div>          <p v-if="error" class="rounded-xl bg-red-50 p-3 text-sm text-red-700">{{ error }}</p>
        </section>

        <p v-else key="none" class="mt-6 rounded-2xl bg-white p-5 text-center text-sm text-slate-600 ring-1 ring-slate-200">
          Your landlord has not added a {{ NETWORKS[sim]?.short }} number. <button class="font-semibold text-brand-700" @click="go({ sim: undefined, step: undefined })">Choose another SIM</button>
        </p>
      </Transition>

      <!-- Bottom actions -->
      <div v-if="account && step !== 'sim'" class="action-bar fixed inset-x-0 bottom-0 z-30 border-t border-slate-200 bg-white/95 px-4 pt-3 pb-[max(0.85rem,env(safe-area-inset-bottom))] backdrop-blur-lg">
        <div class="mx-auto grid max-w-lg gap-2.5">
          <button v-if="step === 'from'" type="button" class="btn-primary h-12 rounded-2xl text-[15px]" @click="next">
            Next <ArrowRight class="size-4.5" />
          </button>
          <template v-else>
            <a v-if="dial" :href="dialHref(dial)" class="dial-btn" :style="{ background: net.gradient, color: net.ink }">
              <Phone class="size-5" /> Dial {{ dial }}
            </a>
            <button type="button" class="btn-primary h-12 rounded-2xl text-[15px]" :data-busy="busy" :disabled="busy" @click="submit">
              <Send class="size-4.5" /> {{ busy ? 'Submitting…' : 'Submit payment' }}
            </button>
          </template>
        </div>
      </div>
    </template>
  </div>
</template>

<style scoped>
.amount-card {
  --color-white: #fff;
  background: linear-gradient(135deg, #14918a 0%, #0f766e 45%, #0a3b38 100%);
  box-shadow: 0 20px 45px -24px rgb(10 59 56 / 0.6);
  transition: background 0.3s ease;
}
.sim-chip { box-shadow: 0 8px 18px -10px rgb(0 0 0 / 0.45); letter-spacing: 0.02em; }
.copy-btn {
  display: inline-flex;
  height: 2.5rem;
  flex-shrink: 0;
  align-items: center;
  gap: 0.4rem;
  border-radius: 0.8rem;
  padding: 0 0.85rem;
  font-size: 0.8rem;
  font-weight: 600;
  color: var(--color-brand-700);
  background: var(--color-brand-50);
  transition: background-color 0.15s ease, transform 0.1s ease;
}
.copy-btn:active { transform: scale(0.96); }
.copy-done { color: #047857; background: #d1fae5; }
.step-no {
  display: flex;
  width: 1.6rem;
  height: 1.6rem;
  flex-shrink: 0;
  align-items: center;
  justify-content: center;
  border-radius: 9999px;
  font-size: 0.75rem;
  font-weight: 700;
}
.dial-btn {
  display: inline-flex;
  height: 3rem;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  border-radius: 1rem;
  font-size: 1rem;
  font-weight: 700;
  letter-spacing: 0.02em;
  box-shadow: 0 10px 22px -14px rgb(0 0 0 / 0.6);
  transition: transform 0.12s ease;
}
.dial-btn:active { transform: scale(0.98); }
.action-bar { box-shadow: 0 -10px 30px -20px rgb(15 23 42 / 0.35); }
.amt-chip {
  height: 2rem;
  border-radius: 9999px;
  padding: 0 0.85rem;
  font-size: 0.75rem;
  font-weight: 600;
  color: var(--color-brand-700);
  background: var(--color-brand-50);
}
.review-ring { animation: ring 2s ease-out infinite; }
@keyframes ring {
  0% { box-shadow: 0 0 0 0 rgb(245 158 11 / 0.35); }
  100% { box-shadow: 0 0 0 18px rgb(245 158 11 / 0); }
}
/* Cards slide in from the right, out to the left */
.card-in { animation: card-in 0.45s cubic-bezier(0.16, 1, 0.3, 1) backwards; }
@keyframes card-in { from { opacity: 0; transform: translateY(10px); } }
.card-enter-active, .card-leave-active { transition: opacity 0.3s ease, transform 0.35s cubic-bezier(0.16, 1, 0.3, 1); }
.card-enter-from { opacity: 0; transform: translateX(24px); }
.card-leave-to { opacity: 0; transform: translateX(-24px); }
@media (prefers-reduced-motion: reduce) {
  .card-in, .review-ring { animation: none; }
  .card-enter-active, .card-leave-active { transition: none; }
}
</style>
