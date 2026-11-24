<script setup>
import { computed, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ArrowLeft, ArrowRight, Copy, Check, Phone, Send, Clock, ChevronRight, ShieldCheck, BadgeCheck, CircleAlert, User, Wallet, PiggyBank, X } from '@lucide/vue'
import { useTenant } from '@/composables/useTenant'
import { formatUGX, formatDate, formatPeriod } from '@/utils/format'
import { nextCycle, coverage } from '@/utils/rentCycle'
import { NETWORKS, NETWORK_IDS, prettyPhone, dialCodeOf, dialHref, sendSteps } from '@/lib/networks'
import { copyText } from '@/lib/clipboard'
import PaymentCoverage from '@/components/PaymentCoverage.vue'
import BaseModal from '@/components/BaseModal.vue'

// Tenant pays rent with mobile money, straight to the landlord's number. One page per step:
//   1. /tenant/pay                       → the landlord's line to pay to (MTN or Airtel)
//   2. ?sim=mtn&step=amount              → how much they are going to pay (all or part), and how many
//                                          days that money lasts
//   3. ?sim=mtn&step=send                → how to send it (number + the amount they chose, the steps, dial)
//   4. ?sim=mtn&step=confirm             → the full names registered on the line used → submit
//   5. Waiting for the landlord to confirm
// ?complete=1: topping up a part payment ("Complete payment"): shows what is still remaining.
// No reason / pay code: the landlord matches the money by the sender's registered names.
const route = useRoute()
const router = useRouter()
const { rental, tenant, property, dues } = useTenant()

const suggested = computed(() => Math.max(0, Math.round(Number(route.query.amount) || 0)) || property.value?.rent || 0)
const completing = computed(() => route.query.complete === '1')
const label = computed(() => String(route.query.label || (completing.value ? 'Complete payment' : 'Rent')))
const rent = computed(() => Number(property.value?.rent ?? 0))
// Money already sent and waiting for the landlord: it is used first
const waiting = computed(() =>
  tenant.value ? rental.cashForTenant(tenant.value.id).filter((c) => c.status === 'pending').reduce((s, c) => s + c.amount, 0) : 0,
)
// The part-paid month being completed (money always goes to the oldest unpaid month first)
const partMonth = computed(() => dues.value.find((d) => d.amountPaid > 0) ?? dues.value[0] ?? null)
const owedTotal = computed(() => dues.value.reduce((s, d) => s + d.balance, 0))
const sim = computed(() => (NETWORK_IDS.includes(route.query.sim) ? route.query.sim : null))

const accounts = computed(() => (tenant.value ? rental.payAccountsOf(tenant.value.landlordId) : []))
const accountFor = (id) => accounts.value.find((a) => a.network === id)
const account = computed(() => (sim.value ? accountFor(sim.value) : null))
const net = computed(() => (sim.value ? NETWORKS[sim.value] : null))
const landlordName = computed(() => rental.owner?.full_name || 'your landlord')

// ── Amount ──
const typed = ref('')
watch(suggested, (v) => (typed.value = typed.value || String(v || '')), { immediate: true })
const amount = computed(() => Math.round(Number(String(typed.value).replace(/[^\d]/g, '')) || 0))
const amountOk = computed(() => amount.value >= 500)
const amountTouched = ref(false)
// Quick amounts: everything owed / the month's rent, half of it, or what is left on a part payment
const quick = computed(() => {
  const list = []
  if (completing.value && partMonth.value) list.push({ label: 'All remaining', value: partMonth.value.balance })
  if (owedTotal.value && owedTotal.value !== partMonth.value?.balance) list.push({ label: 'Everything owed', value: owedTotal.value })
  if (!owedTotal.value && rent.value) list.push({ label: 'One month', value: rent.value })
  const base = completing.value ? partMonth.value?.balance : owedTotal.value || rent.value
  if (base >= 1000) list.push({ label: 'Half', value: Math.round(base / 2 / 500) * 500 })
  return list.filter((q, i, all) => q.value >= 500 && all.findIndex((x) => x.value === q.value) === i)
})
// How long this money lasts once confirmed (same rule as the database)
const cover = computed(() => coverage({ tenant: tenant.value, dues: dues.value, rent: rent.value, amount: amount.value, before: waiting.value }))

// ── Which page ──
const STEPS = ['sim', 'amount', 'send', 'confirm']
const step = computed(() => {
  if (!sim.value || !account.value) return 'sim'
  const want = route.query.step
  if (want === 'send' || want === 'confirm') return amountOk.value ? want : 'amount'
  return 'amount'
})
const stepNo = computed(() => STEPS.indexOf(step.value) + 1)
const go = (q) => router.push({ query: { ...route.query, ...q } })
function back() {
  const i = STEPS.indexOf(step.value)
  if (i === 1) return go({ sim: undefined, step: undefined })
  if (i > 1) return go({ step: STEPS[i - 1] })
  return window.history.state?.back ? router.back() : router.push(PAYMENTS)
}
// ── Cancel: out of the payment, back to the Payments page (nothing has been submitted yet) ──
const PAYMENTS = '/tenant/payments'
const askCancel = ref(false)
const leave = () => router.replace(PAYMENTS)
function cancel() {
  // On the last card they have said the money is sent: ask first, so a real payment isn't left unreported
  if (step.value === 'confirm') askCancel.value = true
  else leave()
}
function toSend() {
  amountTouched.value = true
  if (amountOk.value) go({ step: 'send' })
}

// Late? The unpaid days come out of the next month.
const cycle = computed(() => (tenant.value ? nextCycle(tenant.value) : null))
const steps = computed(() => (account.value ? sendSteps(account.value, { amount: amount.value }).slice(0, -1) : []))
const dial = computed(() => dialCodeOf(account.value))

// ── Copy ──
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

// ── Confirm: the names registered on the line used ──
const name = ref('')
const touched = ref(false)
const cleanName = computed(() => name.value.trim().replace(/\s+/g, ' ').toUpperCase())
const nameError = computed(() =>
  cleanName.value.split(' ').filter((w) => w.length >= 2).length < 2
    ? 'Enter the full names registered on the line you paid from (at least two names).'
    : '',
)
const sentMoney = ref(false)
const busy = ref(false)
const error = ref('')
const sent = ref(false)
const sentCover = ref(null)
async function submit() {
  touched.value = true
  error.value = ''
  if (nameError.value) return
  if (!sentMoney.value) return (error.value = 'Tick the box to confirm you have sent the money.')
  busy.value = true
  sentCover.value = { ...cover.value } // what it buys, before this payment joins the waiting list
  try {
    await rental.submitPayment({
      amount: amount.value,
      method: 'mobile_money',
      network: sim.value,
      note: `Sent from a line registered to ${cleanName.value}`,
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
  <div class="mx-auto max-w-lg pb-16">
    <!-- Back + progress -->
    <div v-if="!sent" class="sticky top-0 z-20 -mx-4 mb-4 bg-[var(--color-slate-50)]/85 px-4 py-2 backdrop-blur-lg sm:static sm:mx-0 sm:bg-transparent sm:px-0 sm:backdrop-blur-none">
      <div class="flex items-center gap-2">
        <button type="button" class="flex h-11 items-center gap-1.5 rounded-2xl bg-white pr-4 pl-3 text-sm font-semibold text-slate-700 shadow-sm ring-1 ring-slate-200 active:scale-95" @click="back">
          <ArrowLeft class="size-[1.1rem]" /> Back
        </button>
        <p class="ml-auto text-xs font-semibold tracking-[0.12em] text-slate-400 uppercase">Step {{ stepNo }} of 4</p>
      </div>
      <div class="mt-3 grid grid-cols-4 gap-1.5" aria-hidden="true">
        <span v-for="n in 4" :key="n" class="h-1.5 rounded-full transition-colors duration-500" :class="n <= stepNo ? 'bg-brand-600' : 'bg-slate-200'" />
      </div>
    </div>

    <!-- ── 5. Waiting for approval ── -->
    <section v-if="sent" class="card-in pt-4 text-center">
      <div class="review-ring mx-auto flex size-20 items-center justify-center rounded-full bg-amber-50 text-amber-600"><Clock class="size-9" /></div>
      <h1 class="mt-5 text-2xl font-bold tracking-tight text-slate-900">Waiting for approval</h1>
      <p class="mx-auto mt-2 max-w-sm text-[15px] leading-relaxed text-slate-600">
        Your payment of <strong class="text-slate-900">{{ formatUGX(amount) }}</strong> on {{ net?.short }} was submitted.
        It will be approved as soon as {{ landlordName }} confirms the money arrived.
      </p>
      <dl class="sheet mx-auto mt-6 max-w-sm divide-y divide-slate-100 px-4 text-left text-sm">
        <div class="flex justify-between gap-3 py-3"><dt class="text-slate-500">Sent to</dt><dd class="font-medium text-slate-900">{{ net?.short }} {{ prettyPhone(account?.phone) }}</dd></div>
        <div class="flex justify-between gap-3 py-3"><dt class="text-slate-500">Line registered to</dt><dd class="text-right font-semibold text-slate-900">{{ cleanName }}</dd></div>
        <div class="flex justify-between gap-3 py-3"><dt class="text-slate-500">Once confirmed</dt><dd class="text-right font-semibold text-slate-900">+{{ (sentCover ?? cover).days }} day{{ (sentCover ?? cover).days === 1 ? '' : 's' }} · to {{ formatDate((sentCover ?? cover).end) }}</dd></div>
      </dl>
      <div class="sheet mx-auto mt-4 max-w-sm p-4 text-left text-sm">
        <p class="flex items-center gap-2 font-medium text-slate-900"><BadgeCheck class="size-4.5 text-brand-600" /> What happens next</p>
        <ul class="mt-2 space-y-1.5 text-slate-600">
          <li>• Your landlord checks the money and approves it.</li>
          <li>• You get a notification once it is approved.</li>
          <li>• Your rent and balance update everywhere.</li>
        </ul>
      </div>
      <div class="mx-auto mt-6 grid max-w-sm gap-2.5">
        <RouterLink to="/tenant/payments" class="btn-primary h-12 rounded-2xl">See my payments</RouterLink>
        <RouterLink to="/tenant" class="btn-secondary h-12 rounded-2xl">Home</RouterLink>
      </div>
    </section>

    <template v-else>
      <!-- Amount card -->
      <header class="amount-card card-in relative overflow-hidden rounded-3xl p-5 text-white" :style="net ? { background: net.gradient, color: net.ink } : null">
        <p class="text-xs font-semibold tracking-[0.14em] uppercase opacity-75">{{ label }}</p>
        <p class="mt-1 text-[2rem] leading-tight font-bold tracking-tight tabular-nums">{{ formatUGX(amount) }}</p>
        <p class="mt-0.5 text-sm opacity-80">{{ property?.name }}</p>
      </header>

      <div v-if="cycle?.debtDays && step === 'sim'" class="card-in mt-3 flex items-start gap-3 rounded-2xl border border-amber-200 bg-amber-50 p-3.5 text-sm text-amber-900">
        <CircleAlert class="mt-0.5 size-4.5 shrink-0 text-amber-600" />
        <p>
          Your last month ended on <strong>{{ formatDate(tenant.leaseEnd) }}</strong>, so you have <strong>{{ cycle.debtDays }} debt day{{ cycle.debtDays === 1 ? '' : 's' }}</strong>.
          They are taken from this month: a full month paid today covers you up to <strong>{{ formatDate(cycle.end) }}</strong> ({{ cycle.days }} days).
        </p>
      </div>

      <Transition name="card" mode="out-in">
        <!-- 1. Line to pay to -->
        <section v-if="step === 'sim'" key="sim" class="mt-6">
          <h1 class="text-xl font-bold tracking-tight text-slate-900">Select the line to pay to</h1>
          <p class="mt-1 text-sm text-slate-500">You send the money from your phone, straight to {{ landlordName }}.</p>
          <div class="mt-4 grid gap-3">
            <button
              v-for="id in NETWORK_IDS" :key="id" type="button"
              class="sim-card group flex items-center gap-4 rounded-2xl bg-white p-4 text-left ring-1 ring-slate-200 transition"
              :class="accountFor(id) ? 'hover:-translate-y-0.5 hover:shadow-lg active:scale-[0.98]' : 'cursor-not-allowed opacity-55'"
              :disabled="!accountFor(id)"
              @click="go({ sim: id, step: 'amount' })"
            >
              <span class="sim-chip flex size-14 shrink-0 items-center justify-center rounded-2xl text-sm font-extrabold" :style="{ background: NETWORKS[id].gradient, color: NETWORKS[id].ink }">{{ NETWORKS[id].short.toUpperCase() }}</span>
              <span class="min-w-0 flex-1">
                <span class="block font-semibold text-slate-900">{{ NETWORKS[id].label }}</span>
                <span class="block truncate text-xs text-slate-500">{{ accountFor(id) ? `Pay to ${accountFor(id).accountName}` : 'Your landlord has not added this network' }}</span>
              </span>
              <ChevronRight v-if="accountFor(id)" class="size-5 shrink-0 text-slate-300 transition group-hover:translate-x-0.5 group-hover:text-slate-500" />
            </button>
          </div>
          <div v-if="!accounts.length" class="mt-4 rounded-2xl border border-slate-200 bg-white p-4 text-sm text-slate-600">
            <p class="font-medium text-slate-900">Mobile money isn't set up yet</p>
            <p class="mt-1">Your landlord hasn't added the number they receive money on. Pay them in cash for now, or ask them to add it in Renta.</p>
          </div>
          <button type="button" class="btn-secondary mt-5 h-12 w-full rounded-2xl text-[15px]" @click="cancel"><X class="size-4.5" /> Cancel</button>
          <p class="mt-5 flex items-center justify-center gap-1.5 text-xs text-slate-400"><ShieldCheck class="size-3.5" /> Renta never asks for your PIN</p>
        </section>

        <!-- 2. Amount -->
        <section v-else-if="step === 'amount'" key="amount" class="mt-6">
          <h1 class="text-xl font-bold tracking-tight text-slate-900">{{ completing ? 'Complete your payment' : 'How much are you going to pay?' }}</h1>
          <p class="mt-1 text-sm text-slate-500">
            {{ completing ? 'Top up what is left. Any amount helps: every shilling adds days to your rental time.' : 'Pay it all, or just part of it. Part of the rent buys part of the month, in days.' }}
          </p>

          <!-- Completing a part payment: what is left -->
          <div v-if="completing && partMonth" class="remain mt-4 rounded-2xl p-4">
            <div class="flex items-center gap-3">
              <span class="flex size-11 shrink-0 items-center justify-center rounded-xl bg-white/15"><PiggyBank class="size-5.5" /></span>
              <div class="min-w-0 flex-1">
                <p class="text-xs font-semibold tracking-[0.12em] uppercase opacity-75">Remaining · {{ formatPeriod(partMonth.period) }}</p>
                <p class="text-2xl font-bold tabular-nums">{{ formatUGX(partMonth.balance) }}</p>
              </div>
            </div>
            <div class="mt-3 h-2 overflow-hidden rounded-full bg-white/20"><span class="block h-full rounded-full bg-white" :style="{ width: `${Math.round((partMonth.amountPaid / partMonth.amount) * 100)}%` }" /></div>
            <p class="mt-1.5 text-xs opacity-80">{{ formatUGX(partMonth.amountPaid) }} of {{ formatUGX(partMonth.amount) }} paid<template v-if="owedTotal > partMonth.balance"> · {{ formatUGX(owedTotal) }} owed in total</template></p>
          </div>

          <form class="sheet mt-4 p-4" @submit.prevent="toSend">
            <label class="label" for="pay-amount">{{ completing ? 'Amount you have managed to top up (UGX)' : 'Amount you will pay (UGX)' }}</label>
            <div class="relative">
              <Wallet class="pointer-events-none absolute top-1/2 left-3.5 size-5 -translate-y-1/2 text-slate-400" />
              <input id="pay-amount" v-model="typed" class="input h-14 pl-11 text-xl font-bold tabular-nums" inputmode="numeric" autocomplete="off" data-cap="off" />
            </div>
            <div v-if="quick.length" class="mt-2.5 flex flex-wrap gap-2">
              <button v-for="q in quick" :key="q.label" type="button" class="amt-chip" :class="amount === q.value && 'amt-chip-on'" @click="typed = String(q.value)">{{ q.label }} · {{ formatUGX(q.value) }}</button>
            </div>
            <p v-if="amountTouched && !amountOk" class="field-error mt-2">Enter at least UGX 500.</p>

            <PaymentCoverage v-if="amountOk && tenant" class="mt-4" :tenant="tenant" :dues="dues" :rent="rent" :amount="amount" :before="waiting" />

            <button type="submit" class="btn-primary mt-5 h-12 w-full rounded-2xl text-[15px]">Continue with {{ amountOk ? formatUGX(amount) : 'this amount' }} <ArrowRight class="size-4.5" /></button>
            <button type="button" class="btn-secondary mt-2.5 h-12 w-full rounded-2xl text-[15px]" @click="cancel"><X class="size-4.5" /> Cancel</button>
          </form>
        </section>

        <!-- 3. Instructions -->
        <section v-else-if="step === 'send'" key="send" class="mt-6">
          <h1 class="text-xl font-bold tracking-tight text-slate-900">Send the money</h1>
          <p class="mt-1 text-sm text-slate-500">Follow these steps on your phone, then come back and continue.</p>
          <p class="said mt-3 flex items-center gap-2.5 rounded-2xl px-3.5 py-3 text-sm">
            <Wallet class="size-4.5 shrink-0" />
            <span>You said you will pay <strong class="tabular-nums">{{ formatUGX(amount) }}</strong>: it lasts {{ cover.days }} day{{ cover.days === 1 ? '' : 's' }}, up to {{ formatDate(cover.end) }}. Send exactly this amount.</span>
          </p>
          <div class="sheet mt-4 divide-y divide-slate-100">
            <div class="flex items-center gap-3 p-4">
              <div class="min-w-0 flex-1">
                <p class="text-xs font-medium text-slate-500">Send to ({{ net.label }})</p>
                <p class="mt-0.5 text-2xl font-bold tracking-wide text-slate-900 tabular-nums">{{ prettyPhone(account.phone) }}</p>
                <p class="mt-0.5 truncate text-sm text-slate-600">Name shown: <strong class="text-slate-900">{{ account.accountName.toUpperCase() }}</strong></p>
              </div>
              <button type="button" class="copy-btn" :class="copied === 'phone' && 'copy-done'" @click="copy('phone', localNumber(account.phone))">
                <Check v-if="copied === 'phone'" class="size-4" /><Copy v-else class="size-4" /> {{ copied === 'phone' ? 'Copied' : 'Copy' }}
              </button>
            </div>
            <div class="flex items-center gap-3 p-4">
              <div class="min-w-0 flex-1">
                <p class="text-xs font-medium text-slate-500">Amount</p>
                <p class="mt-0.5 text-2xl font-bold tracking-wide text-slate-900 tabular-nums">{{ formatUGX(amount) }}</p>
              </div>
              <button type="button" class="copy-btn" :class="copied === 'amount' && 'copy-done'" @click="copy('amount', String(amount))">
                <Check v-if="copied === 'amount'" class="size-4" /><Copy v-else class="size-4" /> {{ copied === 'amount' ? 'Copied' : 'Copy' }}
              </button>
            </div>
            <div class="p-4">
              <p class="text-sm font-semibold text-slate-900">How to send</p>
              <ol class="mt-3 space-y-3">
                <li v-for="(s, i) in steps" :key="i" class="flex gap-3 text-sm leading-relaxed text-slate-700">
                  <span class="step-no" :class="`net-${sim}`">{{ i + 1 }}</span>
                  <span class="pt-0.5">{{ s }}</span>
                </li>
              </ol>
            </div>
          </div>
          <div class="mt-5 grid gap-2.5">
            <a v-if="dial" :href="dialHref(dial)" class="dial-btn" :style="{ background: net.gradient, color: net.ink }"><Phone class="size-5" /> Dial {{ dial }}</a>
            <button type="button" class="btn-primary h-12 rounded-2xl text-[15px]" @click="go({ step: 'confirm' })">I've sent the money <ArrowRight class="size-4.5" /></button>
            <button type="button" class="btn-secondary h-12 rounded-2xl text-[15px]" @click="cancel"><X class="size-4.5" /> Cancel</button>
          </div>
        </section>

        <!-- 4. Confirm -->
        <section v-else-if="step === 'confirm'" key="confirm" class="mt-6">
          <h1 class="text-xl font-bold tracking-tight text-slate-900">Confirm your payment</h1>
          <p class="mt-1 text-sm text-slate-500">{{ landlordName }} finds your payment by the names registered on the line you sent it from.</p>
          <form class="sheet mt-4 space-y-4 p-4" @submit.prevent="submit">
            <div>
              <label class="label" for="from-name">Full names registered on the line you used</label>
              <div class="relative">
                <User class="pointer-events-none absolute top-1/2 left-3.5 size-4.5 -translate-y-1/2 text-slate-400" />
                <input id="from-name" v-model="name" class="input h-12 pl-10 text-base uppercase" placeholder="e.g. JOHN MUKASA" autocomplete="name" data-cap="characters" />
              </div>
              <p v-if="touched && nameError" class="field-error mt-1.5">{{ nameError }}</p>
              <p v-else class="mt-1.5 text-xs text-slate-500">Exactly as the network shows them when money is sent from that line.</p>
            </div>
            <dl class="divide-y divide-slate-100 rounded-2xl bg-slate-50 px-4 text-sm">
              <div class="flex justify-between gap-3 py-2.5"><dt class="text-slate-500">Amount sent</dt><dd class="font-semibold text-slate-900 tabular-nums">{{ formatUGX(amount) }}</dd></div>
              <div class="flex justify-between gap-3 py-2.5"><dt class="text-slate-500">Sent to</dt><dd class="text-right font-medium text-slate-900">{{ net.short }} {{ prettyPhone(account.phone) }}</dd></div>
            </dl>
            <label class="flex items-start gap-3 rounded-2xl border border-slate-200 p-3 text-sm text-slate-700">
              <input v-model="sentMoney" type="checkbox" class="size-5 accent-brand-600" />
              <span>I have sent this money, and the names above are exactly as registered on the line I used.</span>
            </label>
            <p v-if="error" class="form-error" role="alert">{{ error }}</p>
            <button type="submit" class="btn-primary h-12 w-full rounded-2xl text-[15px]" :data-busy="busy" :disabled="busy"><Send class="size-4.5" /> {{ busy ? 'Submitting…' : 'Submit payment' }}</button>
            <button type="button" class="btn-secondary h-12 w-full rounded-2xl text-[15px]" :disabled="busy" @click="cancel"><X class="size-4.5" /> Cancel</button>
          </form>
        </section>
      </Transition>
    </template>

    <!-- Cancel on the last card: have they sent the money already? -->
    <BaseModal v-model="askCancel" title="Cancel this payment?" center>
      <p class="text-sm leading-relaxed text-slate-600">
        If you have <strong class="text-slate-900">already sent</strong> {{ formatUGX(amount) }}, go back and submit it, so {{ landlordName }} can confirm it.
        Cancelling here does not return money you have sent.
      </p>
      <div class="mt-5 grid gap-2.5 sm:grid-cols-2">
        <button type="button" class="btn-primary h-12 rounded-2xl" @click="askCancel = false">Go back</button>
        <button type="button" class="btn-secondary h-12 rounded-2xl" @click="leave">I haven't sent it, cancel</button>
      </div>
    </BaseModal>
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
.copy-btn { display: inline-flex; height: 2.5rem; flex-shrink: 0; align-items: center; gap: 0.4rem; border-radius: 0.8rem; padding: 0 0.85rem; font-size: 0.8rem; font-weight: 600; color: var(--color-brand-700); background: var(--color-brand-50); transition: background-color 0.15s ease, transform 0.1s ease; }
.copy-btn:active { transform: scale(0.96); }
.copy-done { color: var(--color-emerald-700); background: var(--color-emerald-50); }
.step-no { display: flex; width: 1.6rem; height: 1.6rem; flex-shrink: 0; align-items: center; justify-content: center; border-radius: 9999px; font-size: 0.75rem; font-weight: 700; }
.dial-btn { display: inline-flex; height: 3rem; align-items: center; justify-content: center; gap: 0.5rem; border-radius: 1rem; font-size: 1rem; font-weight: 700; letter-spacing: 0.02em; box-shadow: 0 10px 22px -14px rgb(0 0 0 / 0.6); transition: transform 0.12s ease; }
.dial-btn:active { transform: scale(0.98); }
.amt-chip { height: 2.1rem; border-radius: 9999px; padding: 0 0.9rem; font-size: 0.75rem; font-weight: 600; color: var(--color-brand-700); background: var(--color-brand-50); transition: background-color 0.15s ease, color 0.15s ease; }
.amt-chip-on { color: #fff; background: #0f766e; }
.remain { --color-white: #fff; color: #fff; background: linear-gradient(135deg, #f59e0b 0%, #d97706 50%, #92400e 100%); box-shadow: 0 16px 34px -22px rgb(146 64 14 / 0.9); }
.said { color: var(--color-brand-700); background: var(--color-brand-50); box-shadow: inset 0 0 0 1px var(--color-brand-200); }
.review-ring { animation: ring 2s ease-out infinite; }
@keyframes ring { 0% { box-shadow: 0 0 0 0 rgb(245 158 11 / 0.35); } 100% { box-shadow: 0 0 0 18px rgb(245 158 11 / 0); } }
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
