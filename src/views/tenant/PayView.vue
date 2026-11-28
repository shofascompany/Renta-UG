<script setup>
import { computed, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ArrowLeft, Phone, Send, Clock, ShieldCheck, BadgeCheck, X } from '@lucide/vue'
import { useTenant } from '@/composables/useTenant'
import { formatUGX, formatDate } from '@/utils/format'
import { coverage, debtSplit } from '@/utils/rentCycle'
import { NETWORKS, NETWORK_IDS, prettyPhone, validUgPhone, payCodeOf, canOpenUssd, dialHref, sendSteps } from '@/lib/networks'
import BaseModal from '@/components/BaseModal.vue'
import PaymentCoverage from '@/components/PaymentCoverage.vue'

// Tenant pays rent with mobile money, straight to the landlord's own number. Renta UG has no payment provider, so it
// cannot see the money: the tenant pays from their phone and submits it, and the landlord checks it against their own
// MTN / Airtel messages before approving (nothing is credited until then).
//   1. /tenant/pay             number, name registered to it, network, amount + where the money goes → "Pay USh … with MTN",
//                              which dials the whole payment (landlord's number and amount filled in) up to the PIN
//   2. ?step=send              "Entered your PIN and confirmed?" → SUBMIT (asks first) or CANCEL PAYMENT (asks first)
//   3. Submitted: waiting for the landlord to check their messages and approve
// The PIN is typed only in the network's own menu. Renta UG cannot see the PIN or whether the money left.
// The number and name are typed by the tenant and are never checked by Renta UG (database/62).
const route = useRoute()
const router = useRouter()
const { rental, tenant, property, dues, balance } = useTenant()

const rent = computed(() => Number(property.value?.rent ?? 0))
// Rent owed from before (months in debt, utils/payState.js). A new tenant's first month is not a debt.
const pay = computed(() => (tenant.value ? rental.payStateFor(tenant.value.id) : null))
const debt = computed(() => (pay.value && pay.value.owed > 0 && (pay.value.ended || dues.value.length) ? pay.value : null))
const label = computed(() => String(route.query.label || 'Rent'))
const landlordName = computed(() => rental.owner?.full_name || 'Your landlord')
const accounts = computed(() => (tenant.value ? rental.payAccountsOf(tenant.value.landlordId) : []))
const accountFor = (id) => accounts.value.find((a) => a.network === id) ?? null
// Money already sent and waiting for the landlord: it is counted first
const waiting = computed(() =>
  tenant.value ? rental.cashForTenant(tenant.value.id).filter((c) => c.status === 'pending').reduce((s, c) => s + c.amount, 0) : 0,
)

// ── The details (kept while moving between the steps) ──
const lastMine = computed(() => (tenant.value ? rental.cashForTenant(tenant.value.id).find((c) => c.payerPhone) : null))
const phone = ref('')
const payerName = ref('')
const network = ref(null)
const typed = ref('')
watch(
  [tenant, lastMine],
  () => {
    if (!phone.value) phone.value = lastMine.value?.payerPhone ? prettyPhone(lastMine.value.payerPhone) : tenant.value?.phone ? prettyPhone(tenant.value.phone) : ''
    if (!payerName.value && lastMine.value?.payerName) payerName.value = lastMine.value.payerName
  },
  { immediate: true },
)
const suggested = computed(() => Math.max(0, Math.round(Number(route.query.amount) || 0)) || balance.value || rent.value || 0)
watch(suggested, (v) => (typed.value = typed.value || (v ? String(v) : '')), { immediate: true })
const amount = computed(() => Math.round(Number(String(typed.value).replace(/[^\d]/g, '')) || 0))

// The network from the number, when it is plain which one it is (the tenant can still change it)
const PREFIX = { mtn: ['76', '77', '78'], airtel: ['70', '74', '75'] }
watch(
  [phone, accounts],
  ([v]) => {
    const d = String(v).replace(/\D/g, '').replace(/^256/, '').replace(/^0/, '')
    const guess = NETWORK_IDS.find((id) => PREFIX[id].includes(d.slice(0, 2)))
    if (guess && accountFor(guess) && d.length >= 2) network.value = guess
  },
  { immediate: true }, // the number filled in for them picks the network too
)
const account = computed(() => (network.value ? accountFor(network.value) : null))
const net = computed(() => (network.value ? NETWORKS[network.value] : null))
// The pay button says exactly what it does: "Pay USh 300,000 with MTN"
const payLabel = computed(() => (net.value && amount.value >= 500 ? `Pay ${formatUGX(amount.value)} with ${net.value.short}` : 'Pay now'))

const cleanName = computed(() => payerName.value.trim().replace(/\s+/g, ' ').toUpperCase())
const errors = computed(() => ({
  phone: validUgPhone(phone.value) ? '' : 'Enter the Ugandan number you will pay from, for example 0772 123 456.',
  name: cleanName.value.split(' ').filter((w) => w.length >= 2).length >= 2 ? '' : 'Enter the name registered to this number (at least two names).',
  network: account.value ? '' : 'Choose the line to pay to.',
  amount: amount.value >= 500 ? '' : 'Enter at least UGX 500.',
}))
const valid = computed(() => Object.values(errors.value).every((e) => !e))
const touched = ref(false)
const cover = computed(() => coverage({ tenant: tenant.value, dues: dues.value, rent: rent.value, amount: amount.value, before: waiting.value }))
// Debt days are paid first; only the rest is added to the rental time (the payment stays one payment)
const split = computed(() => debtSplit(sentCover.value ?? cover.value, tenant.value))
const dayWord = (n) => `${n} day${n === 1 ? '' : 's'}`

// ── Steps ──
const sent = ref(false)
const step = computed(() => (sent.value ? 'sent' : valid.value && route.query.step === 'send' ? 'send' : 'form'))
const go = (s) => router.push({ query: { ...route.query, step: s } })
const dial = computed(() => payCodeOf(account.value, amount.value))
const ussd = canOpenUssd()
// What to do in the menu. Android: it opened with the payment filled in. iPhone (a page cannot dial there): the steps
// to send it by hand.
const steps = computed(() => {
  if (!account.value) return []
  const n = net.value
  const name = account.value.accountName.toUpperCase()
  return ussd
    ? [
        `Your ${n.label} menu opens with ${prettyPhone(account.value.phone)} and ${formatUGX(amount.value)} filled in.`,
        `Check that the name shown is ${name}.`,
        'Enter your mobile money PIN there and confirm.',
        'Wait for the network\'s message that the money was sent.',
        'Come back here and tap SUBMIT TO LANDLORD.',
      ]
    : [...sendSteps(account.value, { amount: amount.value }).slice(0, -1), 'Come back here and tap SUBMIT TO LANDLORD.']
})
// The pay button: the details are checked, the whole payment is dialled on the phone (up to the PIN), and the page
// moves on to submitting it
const dialNow = () => dial.value && ussd && (window.location.href = dialHref(dial.value))
function confirmAndPay() {
  touched.value = true
  if (!valid.value) return
  go('send')
  dialNow()
}
function back() {
  if (step.value === 'form') return window.history.state?.back ? router.back() : router.push('/tenant/payments')
  router.back()
}

// ── Cancel ──
const askCancel = ref(false)
const leave = () => router.replace('/tenant/payments')

// ── SUBMIT TO LANDLORD ──
const asking = ref(false)
const busy = ref(false)
const error = ref('')
const sentCover = ref(null)
async function submit() {
  error.value = ''
  busy.value = true
  sentCover.value = { ...cover.value } // what it buys, before it joins the waiting list
  try {
    await rental.submitMobilePayment({ amount: amount.value, network: network.value, payerPhone: phone.value, payerName: cleanName.value })
    asking.value = false
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
  <div class="mx-auto max-w-lg pb-16">
    <div v-if="step !== 'sent'" class="mb-4 flex items-center gap-2">
      <button type="button" class="flex h-11 items-center gap-1.5 rounded-2xl bg-white pr-4 pl-3 text-sm font-semibold text-slate-700 shadow-sm ring-1 ring-slate-200 active:scale-95" @click="back">
        <ArrowLeft class="size-[1.1rem]" /> Back
      </button>
      <p class="ml-auto text-xs font-semibold tracking-[0.12em] text-slate-400 uppercase">{{ label }}</p>
    </div>

    <!-- ── 4. Submitted ── -->
    <section v-if="step === 'sent'" class="card-in pt-4 text-center">
      <div class="review-ring mx-auto flex size-20 items-center justify-center rounded-full bg-amber-50 text-amber-600"><Clock class="size-9" /></div>
      <h1 class="mt-5 text-2xl font-bold tracking-tight text-slate-900">Sent to {{ landlordName }}</h1>
      <p class="mx-auto mt-2 max-w-sm text-[15px] leading-relaxed text-slate-600">
        Your payment of <strong class="text-slate-900">{{ formatUGX(amount) }}</strong> is waiting for approval. {{ landlordName }} checks it against their {{ net?.short }} messages first.
      </p>
      <dl class="sheet mx-auto mt-6 max-w-sm divide-y divide-slate-100 px-4 text-left text-sm">
        <div class="flex justify-between gap-3 py-3"><dt class="text-slate-500">Paid to</dt><dd class="text-right font-medium text-slate-900">{{ net?.short }} {{ prettyPhone(account?.phone) }}</dd></div>
        <div v-if="split.debtPaid" class="flex justify-between gap-3 py-3"><dt class="text-slate-500">Debt days paid first</dt><dd class="text-right font-semibold text-slate-900">{{ dayWord(split.debtPaid) }}</dd></div>
        <div class="flex justify-between gap-3 py-3"><dt class="text-slate-500">{{ split.debtPaid ? 'Days added once approved' : 'Once approved' }}</dt><dd class="text-right font-semibold text-slate-900">+{{ dayWord(split.added) }} · to {{ formatDate((sentCover ?? cover).end) }}</dd></div>
      </dl>
      <p class="mx-auto mt-4 flex max-w-sm items-start gap-2 text-left text-sm text-slate-600"><BadgeCheck class="mt-0.5 size-4.5 shrink-0 text-brand-600" /> You get a notification when it is approved, and your rent updates everywhere.</p>
      <div class="mx-auto mt-6 grid max-w-sm gap-2.5">
        <RouterLink to="/tenant/payments" class="btn-primary h-12 rounded-2xl">See my payments</RouterLink>
        <RouterLink to="/tenant" class="btn-secondary h-12 rounded-2xl">Home</RouterLink>
      </div>
    </section>

    <!-- ── 1. The details ── -->
    <section v-else-if="step === 'form'" key="form" class="card-in">
      <h1 class="text-2xl font-bold tracking-tight text-slate-900">Pay rent</h1>
      <p class="mt-1 text-sm text-slate-500">Enter your payment details</p>

      <!-- The rent, and what is owed only when something is -->
      <div class="rent-card mt-5 rounded-3xl p-5" :style="net ? { background: net.gradient, color: net.ink } : null">
        <p class="text-xs font-semibold tracking-[0.14em] uppercase opacity-75">Rent</p>
        <p class="mt-1 text-[2rem] leading-tight font-bold tracking-tight tabular-nums">{{ formatUGX(rent) }} <span class="text-sm font-medium opacity-75">a month</span></p>
        <p class="mt-0.5 truncate text-sm opacity-80">{{ property?.name }}</p>
      </div>
      <div v-if="debt" class="debt-card mt-3 flex items-start gap-3 rounded-2xl p-4" role="status">
        <span class="debt-dot mt-1.5 size-2.5 shrink-0 rounded-full" aria-hidden="true" />
        <div class="min-w-0 flex-1">
          <p class="flex flex-wrap items-baseline justify-between gap-x-3 text-sm font-semibold text-red-800"><span>Unpaid rent</span><span class="text-lg font-bold tabular-nums">{{ formatUGX(debt.owed) }}</span></p>
          <p class="mt-0.5 text-xs text-red-700">{{ debt.how }}<template v-if="debt.months[0]?.from"> · since {{ formatDate(debt.months[0].from) }}</template></p>
        </div>
      </div>

      <div v-if="!accounts.length" class="mt-5 rounded-2xl border border-slate-200 bg-white p-4 text-sm text-slate-600">
        <p class="font-medium text-slate-900">Mobile money isn't set up yet</p>
        <p class="mt-1">{{ landlordName }} hasn't added the number they receive money on. Pay them in cash for now, or ask them to add it.</p>
      </div>

      <form v-else class="mt-5 space-y-5" novalidate @submit.prevent="confirmAndPay">
        <div>
          <label class="label" for="pay-phone">Mobile Money Number</label>
          <input id="pay-phone" v-model="phone" type="tel" class="input h-12 text-base" placeholder="+256 7XX XXX XXX" autocomplete="tel" inputmode="tel" />
          <p v-if="touched && errors.phone" class="field-error mt-1.5">{{ errors.phone }}</p>
        </div>
        <div>
          <label class="label" for="pay-name">Name Registered to This Number</label>
          <input id="pay-name" v-model="payerName" class="input h-12 text-base uppercase" placeholder="Enter the registered account name" autocomplete="name" data-cap="characters" />
          <p v-if="touched && errors.name" class="field-error mt-1.5">{{ errors.name }}</p>
        </div>
        <div>
          <p class="label">Select Line to Pay To</p>
          <div class="grid grid-cols-2 gap-3" role="radiogroup" aria-label="Line to pay to">
            <button
              v-for="id in NETWORK_IDS" :key="id" type="button" role="radio"
              class="net-card flex h-20 flex-col items-center justify-center rounded-2xl text-center transition"
              :class="[`pick-${id}`, network === id && 'net-on']"
              :aria-checked="network === id" :disabled="!accountFor(id)"
              @click="network = id"
            >
              <span class="text-lg font-extrabold">{{ NETWORKS[id].short }}</span>
              <span class="mt-0.5 text-xs">{{ accountFor(id) ? NETWORKS[id].label : 'Not available' }}</span>
            </button>
          </div>
          <p v-if="touched && errors.network" class="field-error mt-1.5">{{ errors.network }}</p>
        </div>
        <div>
          <label class="label" for="pay-amount">Amount (UGX)</label>
          <input id="pay-amount" v-model="typed" class="input h-14 text-xl font-bold tabular-nums" inputmode="numeric" autocomplete="off" data-cap="off" />
          <div v-if="(rent && amount !== rent) || (debt && amount !== balance)" class="mt-2 flex flex-wrap gap-2">
            <button v-if="rent && amount !== rent" type="button" class="amt-chip" @click="typed = String(rent)">One month · {{ formatUGX(rent) }}</button>
            <button v-if="debt && balance !== rent && amount !== balance" type="button" class="amt-chip" @click="typed = String(balance)">Everything owed · {{ formatUGX(balance) }}</button>
          </div>
          <p v-if="touched && errors.amount" class="field-error mt-1.5">{{ errors.amount }}</p>
          <!-- What this money pays for: months, days and their dates -->
          <PaymentCoverage v-if="amount >= 500 && tenant" class="mt-3" :tenant="tenant" :dues="dues" :rent="rent" :amount="amount" :before="waiting" />
        </div>

        <div class="sheet p-4">
          <p class="text-sm font-semibold text-slate-900">Payment destination</p>
          <dl class="mt-2 divide-y divide-slate-100 text-sm">
            <div class="flex justify-between gap-3 py-2.5"><dt class="text-slate-500">Landlord</dt><dd class="text-right font-semibold text-slate-900">{{ landlordName }}</dd></div>
            <div class="flex justify-between gap-3 py-2.5"><dt class="text-slate-500">Receiving number</dt><dd class="text-right font-semibold text-slate-900 tabular-nums">{{ account ? `${net.short} ${prettyPhone(account.phone)}` : 'Choose a network' }}</dd></div>
            <div class="flex justify-between gap-3 py-2.5"><dt class="text-slate-500">Property / room</dt><dd class="text-right font-medium text-slate-900">{{ property?.name ?? '—' }}</dd></div>
            <div class="flex justify-between gap-3 py-2.5"><dt class="text-slate-500">Amount to pay</dt><dd class="text-right font-bold text-slate-900 tabular-nums">{{ formatUGX(amount) }}</dd></div>
          </dl>
        </div>

        <button type="submit" class="pay-btn h-13 w-full rounded-2xl text-[15px] font-bold" :style="net ? { background: net.gradient, color: net.ink } : null"><Phone class="size-4.5" /> {{ payLabel }}</button>
        <p class="flex items-center justify-center gap-1.5 text-xs text-slate-400"><ShieldCheck class="size-3.5" /> You enter your PIN only in the {{ net?.short ?? 'network' }} menu. Renta UG never asks for it.</p>
      </form>
    </section>

    <!-- ── 2. Entered the PIN? Submit it to the landlord, or cancel ── -->
    <section v-else-if="step === 'send'" key="send" class="card-in pt-2 text-center">
      <div class="pin-ring mx-auto flex size-20 items-center justify-center rounded-full" :style="{ background: net.gradient, color: net.ink }"><Phone class="size-9" /></div>
      <h1 class="mt-5 text-2xl font-bold tracking-tight text-slate-900">Entered your PIN?</h1>
      <p class="mx-auto mt-2 max-w-sm text-[15px] leading-relaxed text-slate-600">
        If you have entered your PIN and confirmed the payment of <strong class="text-slate-900 tabular-nums">{{ formatUGX(amount) }}</strong>, submit it to {{ landlordName }} for confirmation.
      </p>
      <p v-if="split.debtPaid" class="debt-paid mx-auto mt-3 max-w-sm rounded-2xl px-4 py-2.5 text-left text-sm">
        Your {{ dayWord(split.debtPaid) }} of debt {{ split.debtPaid === 1 ? 'is' : 'are' }} paid first, so <strong>{{ dayWord(split.added) }}</strong> {{ split.added === 1 ? 'is' : 'are' }} added to your rental time.
      </p>
      <!-- How to finish -->
      <ol class="sheet mx-auto mt-5 max-w-sm space-y-3 p-4 text-left">
        <li v-for="(s, i) in steps" :key="i" class="flex gap-3 text-sm leading-relaxed text-slate-700"><span class="step-no" :class="`step-${network}`">{{ i + 1 }}</span><span class="pt-0.5">{{ s }}</span></li>
      </ol>
      <a v-if="ussd" :href="dialHref(dial)" class="mx-auto mt-3 inline-flex items-center gap-1.5 text-sm font-semibold text-brand-700"><Phone class="size-4" /> The menu did not open? Open it again</a>
      <div class="mx-auto mt-6 grid max-w-sm gap-2.5">
        <button type="button" class="btn-primary h-13 rounded-2xl text-[15px] font-bold tracking-wide" @click="(asking = true), (error = '')"><Send class="size-4.5" /> SUBMIT TO LANDLORD</button>
        <button type="button" class="btn-danger-soft h-12 rounded-2xl" @click="askCancel = true"><X class="size-4.5" /> CANCEL PAYMENT</button>
      </div>
    </section>

    <!-- SUBMIT TO LANDLORD: last check -->
    <BaseModal v-model="asking" title="Submit this payment?" center>
      <dl v-if="account" class="divide-y divide-slate-100 rounded-2xl bg-slate-50 px-4 text-sm">
        <div class="flex justify-between gap-3 py-2.5"><dt class="text-slate-500">Amount</dt><dd class="font-bold text-slate-900 tabular-nums">{{ formatUGX(amount) }}</dd></div>
        <div class="flex justify-between gap-3 py-2.5"><dt class="text-slate-500">Paid from</dt><dd class="text-right font-medium text-slate-900">{{ prettyPhone(phone) }}</dd></div>
        <div class="flex justify-between gap-3 py-2.5"><dt class="text-slate-500">Registered name</dt><dd class="text-right font-medium text-slate-900">{{ cleanName }}</dd></div>
        <div class="flex justify-between gap-3 py-2.5"><dt class="text-slate-500">Network</dt><dd class="text-right font-medium text-slate-900">{{ net.label }}</dd></div>
        <div class="flex justify-between gap-3 py-2.5"><dt class="text-slate-500">Landlord's number</dt><dd class="text-right font-medium text-slate-900">{{ prettyPhone(account.phone) }}</dd></div>
        <div v-if="split.debtPaid" class="flex justify-between gap-3 py-2.5"><dt class="text-slate-500">Debt days paid first</dt><dd class="text-right font-medium text-slate-900">{{ dayWord(split.debtPaid) }}</dd></div>
        <div v-if="split.debtPaid" class="flex justify-between gap-3 py-2.5"><dt class="text-slate-500">Days added</dt><dd class="text-right font-bold text-slate-900">{{ dayWord(split.added) }}</dd></div>
      </dl>
      <p class="mt-3 text-sm text-slate-600">Submit only after the money has left your phone. {{ landlordName }} checks it before your rent is updated.</p>
      <p v-if="error" class="form-error mt-3" role="alert">{{ error }}</p>
      <div class="mt-5 grid gap-2.5 sm:grid-cols-2">
        <button type="button" class="btn-secondary h-12 rounded-2xl" :disabled="busy" @click="asking = false">Not yet</button>
        <button type="button" class="btn-primary h-12 rounded-2xl" :data-busy="busy" :disabled="busy" @click="submit">{{ busy ? 'Submitting…' : 'Yes, submit' }}</button>
      </div>
    </BaseModal>

    <!-- CANCEL PAYMENT: asks first -->
    <BaseModal v-model="askCancel" title="Cancel this payment?" center>
      <p class="text-sm leading-relaxed text-slate-600">
        Nothing is sent to {{ landlordName }}. If you <strong class="text-slate-900">already entered your PIN</strong> and {{ formatUGX(amount) }} left your phone, submit it instead: cancelling here does not return money you have sent.
      </p>
      <div class="mt-5 grid gap-2.5 sm:grid-cols-2">
        <button type="button" class="btn-secondary h-12 rounded-2xl" @click="askCancel = false">Go back</button>
        <button type="button" class="btn-danger-soft h-12 rounded-2xl" @click="leave">Yes, cancel payment</button>
      </div>
    </BaseModal>
  </div>
</template>

<style scoped>
.rent-card { --color-white: #fff; color: #fff; background: linear-gradient(140deg, #14918a, #0f766e 50%, #0a3b38); box-shadow: 0 18px 40px -26px rgb(10 59 56 / 0.7); }
.debt-card { background: #fef2f2; box-shadow: inset 0 0 0 1px #fecaca; }
.debt-dot { background: #dc2626; box-shadow: 0 0 0 4px rgb(220 38 38 / 0.15); }
html.dark .debt-card { background: #000000; box-shadow: inset 0 0 0 1px rgb(248 113 113 / 0.35); }
.btn-danger-soft { display: inline-flex; align-items: center; justify-content: center; font-weight: 600; color: #b91c1c; background: #fef2f2; box-shadow: inset 0 0 0 1px #fecaca; }
html.dark .btn-danger-soft { color: #fca5a5; background: #000000; box-shadow: inset 0 0 0 1px rgb(248 113 113 / 0.35); }
.debt-paid { color: #065f46; background: #ecfdf5; box-shadow: inset 0 0 0 1px #a7f3d0; }
html.dark .debt-paid { color: #6ee7b7; background: #000000; box-shadow: inset 0 0 0 1px rgb(52 211 153 / 0.4); }
.pin-ring { animation: ring 2s ease-out infinite; }
.amt-chip { height: 2.1rem; border-radius: 9999px; padding: 0 0.9rem; font-size: 0.75rem; font-weight: 600; color: var(--color-brand-700); background: var(--color-brand-50); }
.net-card { background: var(--color-white); box-shadow: inset 0 0 0 1.5px var(--color-slate-200); }
.net-card:disabled { cursor: not-allowed; opacity: 0.45; }
/* own class names: the app-wide .net-mtn / .net-airtel chips are tinted, these cards stay black until chosen */
.pick-mtn { color: #a37a00; }
.pick-airtel { color: #c40000; }
html.dark .pick-mtn:not(.net-on) { color: #ffdf6b; }
html.dark .pick-airtel:not(.net-on) { color: #ff9a9a; }
/* The pay button: the network's own colours once one is chosen */
.pay-btn { display: inline-flex; align-items: center; justify-content: center; gap: 0.5rem; color: #fff; background: linear-gradient(135deg, #14918a, #0f766e 55%, #0a3b38); box-shadow: 0 12px 26px -16px rgb(0 0 0 / 0.55); transition: transform 0.12s ease, filter 0.15s ease; }
.pay-btn:hover { filter: brightness(1.05); }
.pay-btn:active { transform: scale(0.98); }
.pick-mtn.net-on { color: #1f1a00; background: #ffcc00; box-shadow: inset 0 0 0 2px #e0a800; }
.pick-airtel.net-on { color: #fff; background: #e40000; box-shadow: inset 0 0 0 2px #9e0000; }
.net-card:not(.net-on):not(:disabled):hover { box-shadow: inset 0 0 0 1.5px var(--color-slate-400); }
.step-no { display: flex; width: 1.6rem; height: 1.6rem; flex-shrink: 0; align-items: center; justify-content: center; border-radius: 9999px; font-size: 0.75rem; font-weight: 700; }
.step-mtn { color: #1f1a00; background: #ffcc00; }
.step-airtel { color: #fff; background: #e40000; }
.h-13 { height: 3.25rem; }
.review-ring { animation: ring 2s ease-out infinite; }
@keyframes ring { 0% { box-shadow: 0 0 0 0 rgb(245 158 11 / 0.35); } 100% { box-shadow: 0 0 0 18px rgb(245 158 11 / 0); } }
.card-in { animation: card-in 0.4s cubic-bezier(0.16, 1, 0.3, 1) backwards; }
@keyframes card-in { from { opacity: 0; transform: translateY(8px); } }
@media (prefers-reduced-motion: reduce) {
  .card-in, .review-ring, .pin-ring { animation: none; }
}
</style>
