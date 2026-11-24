<script setup>
import { computed, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  Crown, Check, Copy, ShieldCheck, Clock, Phone, Send, User, Receipt, Sparkles, Lock, ArrowLeft, ArrowRight,
  CircleCheck, CircleX, CircleSlash, Building2, Users, Wallet, BellRing, BarChart3, MessageCircle, ChevronRight,
  Home, Building, Infinity as InfinityIcon, BadgeCheck, PartyPopper, RefreshCw, Minus, Plus,
} from '@lucide/vue'
import { useAuthStore } from '@/stores/auth'
import { useRentalStore } from '@/stores/rental'
import { useBillingStore, daysBetween, paidWith } from '@/stores/billing'
import { formatUGX, formatDate } from '@/utils/format'
import { NETWORKS, NETWORK_IDS, prettyPhone, dialCodeOf, dialHref, sendSteps } from '@/lib/networks'
import { copyText } from '@/lib/clipboard'
import AppLink from '@/components/AppLink.vue'
import { askConfirm } from '@/composables/useConfirm'
import EmptyState from '@/components/EmptyState.vue'

// Landlord's subscription to Renta UG, one page per step (the step lives in the address, so Back works):
//   overview                → status, usage, billing history, "Renew"
//   ?step=capacity          → 0. not subscribed yet: how many houses + rooms they will register (first sign-in)
//   ?step=package           → 1. Small / Big scale + monthly / yearly
//   ?step=line              → 2. the Renta UG line to pay to (MTN / Airtel)
//   ?step=send              → 3. how to send the money
//   ?step=confirm           → 4. the full names registered on the line used → submit
//   (a payment is waiting)  → 5. waiting for the main admin to confirm
// No reason / reference code: Renta UG matches the money by the sender's registered names.
const auth = useAuthStore()
const rental = useRentalStore()
const billing = useBillingStore()
const route = useRoute()
const router = useRouter()

const s = computed(() => billing.mine)
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Africa/Kampala' })
const pending = computed(() => billing.payments.find((p) => p.status === 'pending' && p.landlordId === auth.user?.id) ?? null)
const history = computed(() => billing.payments.filter((p) => p.landlordId === auth.user?.id))
const tierName = (t) => (t === 'big' ? 'Big scale' : 'Small scale')

// ── Choices, kept in the address ──
const tier = computed(() => {
  const t = ['small', 'big'].includes(route.query.tier) ? route.query.tier : recommended.value
  return t === 'small' && !smallAllowed.value ? 'big' : t
})
const plan = computed(() => (['monthly', 'yearly'].includes(route.query.plan) ? route.query.plan : 'yearly'))
const sim = computed(() => (NETWORK_IDS.includes(route.query.sim) ? route.query.sim : null))
const go = (q) => router.push({ query: { ...route.query, ...q } })

// ── Which page ──
// The business size comes first (asked once, at the first sign-in; it can be changed from the packages).
const STEPS = computed(() => ['capacity', 'package', 'line', 'send', 'confirm'])
const page = computed(() => {
  if (s.value.exempt) return 'overview'
  if (pending.value) return 'waiting'
  const want = route.query.step
  // The business size before anything else (only once the database has the column: database/51)
  if (!s.value.active && planned.value == null && auth.profile && 'planned_units' in auth.profile) return 'capacity'
  if (!STEPS.value.includes(want)) return s.value.active ? 'overview' : 'package' // locked → straight to the packages
  if (['send', 'confirm'].includes(want) && !account.value) return 'line'
  return want
})
const stepNo = computed(() => STEPS.value.indexOf(page.value) + 1)
function back() {
  const i = STEPS.value.indexOf(page.value)
  if (i > 0) return go({ step: STEPS.value[i - 1] })
  router.push({ query: {} })
}

// ── 0. Business size (first sign-in) ──
const planned = computed(() => auth.profile?.planned_units ?? null)
const capacity = ref(planned.value ?? (rental.properties.length || ''))
watch(planned, (v) => v != null && (capacity.value = v))
const capNum = computed(() => Math.max(0, Math.round(Number(capacity.value) || 0)))
const capTier = computed(() => billing.recommendedTier(Math.max(capNum.value, rental.properties.length)))
const capChips = computed(() => [
  { label: '1 – 5', value: 5 },
  { label: `Up to ${billing.settings.smallMaxUnits}`, value: billing.settings.smallMaxUnits },
  { label: '20', value: 20 },
  { label: '50', value: 50 },
  { label: '100+', value: 100 },
])
const bump = (n) => (capacity.value = Math.max(1, capNum.value + n))
const capBusy = ref(false)
const capError = ref('')
async function saveCapacity() {
  capError.value = ''
  if (capNum.value < 1) return (capError.value = 'Enter how many houses and rooms you will register (at least 1).')
  if (capNum.value < rental.properties.length) return (capError.value = `You already have ${rental.properties.length} houses and rooms registered.`)
  capBusy.value = true
  try {
    await billing.setPlannedUnits(capNum.value)
    router.push({ query: { step: 'package', tier: capTier.value, plan: plan.value } })
  } catch (e) {
    capError.value = e.message
  } finally {
    capBusy.value = false
  }
}

// ── Status (overview) ──
const headline = computed(() => {
  if (s.value.exempt) return 'Free for life'
  if (!s.value.until) return 'Not subscribed yet'
  if (!s.value.active) return `Ended on ${formatDate(s.value.until)}`
  return `Active until ${formatDate(s.value.until)}`
})
const planLabel = computed(() => {
  if (s.value.exempt) return 'Permanent free account'
  if (!s.value.until) return 'Not subscribed'
  if (!s.value.plan) return 'Added by Renta UG'
  return `${tierName(s.value.tier)} · ${s.value.plan === 'yearly' ? 'Yearly' : 'Monthly'}`
})
const meter = computed(() => {
  if (!s.value.active || s.value.exempt) return 0
  const total = s.value.plan === 'yearly' ? 365 : 30
  return Math.max(4, Math.min(100, Math.round(((s.value.daysLeft + 1) / total) * 100)))
})

// ── 1. Package ──
const units = computed(() => rental.properties.length)
const max = computed(() => billing.settings.smallMaxUnits)
// The package is chosen for the bigger of: what they have now, and what they said they will register
const need = computed(() => Math.max(units.value, planned.value ?? 0))
const recommended = computed(() => billing.recommendedTier(need.value))
const smallAllowed = computed(() => need.value <= max.value)
const limit = computed(() => billing.unitLimit)
const scales = computed(() => [
  { id: 'small', name: 'Small scale', icon: Home, fits: `Up to ${max.value} houses and rooms`, who: 'A few rental houses or rooms.' },
  { id: 'big', name: 'Big scale', icon: Building, fits: 'Any number of houses and rooms', who: 'Rentals with many rooms, apartment blocks, several properties.' },
])
const price = computed(() => billing.price(tier.value, plan.value))
const months = computed(() => (plan.value === 'yearly' ? 12 : 1))
const features = [
  [Building2, 'Houses, rentals and rooms'],
  [Users, 'Tenants, with or without smartphones'],
  [Wallet, 'Cash and mobile money with receipts'],
  [BellRing, 'Reminders and payment notifications'],
  [BarChart3, 'Reports, transactions and records'],
]
const addDays = (iso, n) => {
  const d = new Date(`${iso}T00:00:00Z`)
  d.setUTCDate(d.getUTCDate() + n)
  return d.toISOString().slice(0, 10)
}
const period = computed(() => {
  const start = s.value.active && s.value.until ? addDays(s.value.until, 1) : today()
  // A subscription month is 30 days; a year is 365 (same as database/53)
  return { start, end: addDays(start, (months.value === 12 ? 365 : 30 * months.value) - 1) }
})

// ── 2. Line to pay to ──
const accounts = computed(() => billing.settings.accounts)
const accountFor = (id) => accounts.value.find((a) => a.network === id)
const account = computed(() => (sim.value ? accountFor(sim.value) : null))
const net = computed(() => (sim.value ? NETWORKS[sim.value] : null))

// ── 3. Send ──
const steps = computed(() => (account.value ? sendSteps(account.value, { amount: price.value, payee: "Renta UG's" }).slice(0, -1) : []))
const dial = computed(() => dialCodeOf(account.value))

// ── 4. Confirm: the full names registered on the line used ──
const name = ref('')
const touched = ref(false)
const cleanName = computed(() => name.value.trim().replace(/\s+/g, ' ').toUpperCase())
const nameError = computed(() =>
  cleanName.value.split(' ').filter((w) => w.length >= 2).length < 2
    ? 'Enter the full names registered on the line you paid from (at least two names), exactly as the network shows them.'
    : '',
)
const sentMoney = ref(false)
const busy = ref(false)
const error = ref('')
async function submit() {
  touched.value = true
  error.value = ''
  if (nameError.value) return
  if (!sentMoney.value) return (error.value = 'Tick the box to confirm you have sent the money.')
  busy.value = true
  try {
    await billing.submitPayment({ tier: tier.value, plan: plan.value, network: sim.value, senderName: cleanName.value, paidOn: today() })
    name.value = ''
    sentMoney.value = false
    touched.value = false
    router.replace({ query: {} }) // the waiting page shows while the payment is pending
    window.scrollTo({ top: 0, behavior: 'smooth' })
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}

// ── 5. Waiting ──
async function cancel() {
  if (!pending.value) return
  const id = pending.value.id
  await askConfirm({
    title: 'Withdraw this payment?',
    text: 'Only do this if you did not send the money.',
    confirm: 'Withdraw',
    cancel: 'Keep it',
    working: 'Withdrawing…',
    action: () => billing.cancelPayment(id),
  })
}
const checking = ref(false)
async function checkNow() {
  checking.value = true
  try {
    await Promise.all([billing.load(), billing.refreshProfile()])
  } finally {
    checking.value = false
  }
}
// The moment the main admin confirms: celebrate, then open the dashboard
const welcome = ref(false)
watch(pending, (now, before) => {
  if (before && !now && s.value.active) welcome.value = true
})

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

const statusPill = {
  pending: ['Waiting', Clock, 'pill-wait'],
  confirmed: ['Paid', CircleCheck, 'pill-ok'],
  rejected: ['Not confirmed', CircleX, 'pill-bad'],
  cancelled: ['Withdrawn', CircleSlash, 'pill-off'],
}
const days = (p) => (p.periodStart && p.periodEnd ? daysBetween(p.periodStart, p.periodEnd) + 1 : null)

// ── The subscription the landlord has paid for (latest confirmed payment) ──
const paid = computed(() => {
  const list = history.value.filter((p) => p.status === 'confirmed' && p.periodStart && p.periodEnd)
  if (!list.length) return null
  // The period running today, otherwise the latest one
  const t = today()
  const p = list.find((x) => x.periodStart <= t && x.periodEnd >= t) ?? [...list].sort((a, b) => b.periodEnd.localeCompare(a.periodEnd))[0]
  const total = days(p)
  const used = Math.min(total, Math.max(0, daysBetween(p.periodStart, t) + 1))
  const ahead = list.filter((x) => x.periodStart > p.periodEnd).length // renewals already paid on top
  return {
    ...p,
    total,
    used: p.periodStart > t ? 0 : used,
    left: Math.max(0, daysBetween(t, s.value.until ?? p.periodEnd)),
    pct: p.periodStart > t ? 0 : Math.round((used / total) * 100),
    length: p.months === 12 ? '1 year (365 days)' : `${p.months} month${p.months === 1 ? '' : 's'} (${p.months * 30} days)`,
    ahead,
  }
})

// ── Control panel: everything about billing in one place ──
const scrollTo = (id) => document.getElementById(id)?.scrollIntoView({ behavior: 'smooth', block: 'start' })
const controls = computed(() =>
  s.value.exempt
    ? [
        { icon: Building2, label: 'My properties', hint: `${units.value} house${units.value === 1 ? '' : 's'} and rooms`, to: '/landlord/properties', tone: 'c-teal' },
        { icon: Users, label: 'Tenants', hint: 'Everyone renting from you', to: '/landlord/tenants', tone: 'c-sky' },
        { icon: Wallet, label: 'Payments', hint: 'Confirm and record rent', to: '/landlord/payments', tone: 'c-violet' },
        { icon: MessageCircle, label: 'Contact Renta UG', hint: 'WhatsApp 0726 128782', wa: '256726128782', tone: 'c-green' },
      ]
    : [
        { icon: RefreshCw, label: s.value.active ? 'Renew early' : 'Renew now', hint: 'New time is added on top', run: () => go({ step: 'package', tier: s.value.tier || recommended.value, plan: s.value.plan || 'yearly' }), tone: 'c-teal' },
        { icon: Crown, label: 'Change package', hint: `${tierName(s.value.tier || recommended.value)} now`, run: () => go({ step: 'package' }), tone: 'c-gold' },
        { icon: Receipt, label: 'Billing history', hint: `${history.value.length} payment${history.value.length === 1 ? '' : 's'}`, run: () => scrollTo('billing-history'), tone: 'c-sky' },
        { icon: RefreshCw, label: checking.value ? 'Checking…' : 'Refresh status', hint: 'Get the latest from Renta UG', run: checkNow, tone: 'c-violet' },
        { icon: Building2, label: 'Houses and rooms', hint: limit.value != null ? `${units.value} of ${limit.value} used` : `${units.value} in your account`, to: '/landlord/properties', tone: 'c-slate' },
        { icon: MessageCircle, label: 'Contact Renta UG', hint: 'WhatsApp 0726 128782', wa: '256726128782', tone: 'c-green' },
      ],
)
const lastRejected = computed(() => (history.value[0]?.status === 'rejected' ? history.value[0] : null))
</script>

<template>
  <div class="mx-auto max-w-3xl">
    <p v-if="billing.unavailable" class="rounded-2xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">
      Subscriptions need a database update. Ask Renta UG to run <code>database/update_existing.sql</code>.
    </p>

    <template v-else-if="billing.loaded">
      <!-- ── Payment confirmed ── -->
      <section v-if="welcome" class="card-in sheet p-8 text-center">
        <div class="ok-ring mx-auto flex size-20 items-center justify-center rounded-full bg-emerald-50 text-emerald-600"><PartyPopper class="size-9" /></div>
        <h1 class="mt-5 text-2xl font-bold tracking-tight text-slate-900">Payment confirmed</h1>
        <p class="mx-auto mt-2 max-w-sm text-[15px] text-slate-600">
          Your {{ tierName(s.tier) }} subscription runs until <strong class="text-slate-900">{{ formatDate(s.until) }}</strong>. Your account is open.
        </p>
        <RouterLink to="/landlord" class="btn-primary mx-auto mt-6 h-12 max-w-xs rounded-2xl" @click="welcome = false">Go to my dashboard <ArrowRight class="size-4.5" /></RouterLink>
      </section>

      <!-- ── Waiting for Renta UG ── -->
      <section v-else-if="page === 'waiting'" class="card-in text-center">
        <div class="wait-ring mx-auto flex size-20 items-center justify-center rounded-full bg-amber-50 text-amber-600"><Clock class="size-9" /></div>
        <h1 class="mt-5 text-2xl font-bold tracking-tight text-slate-900">Waiting for confirmation</h1>
        <p class="mx-auto mt-2 max-w-md text-[15px] leading-relaxed text-slate-600">
          Renta UG is checking your payment of <strong class="text-slate-900">{{ formatUGX(pending.amount) }}</strong>.
          {{ s.active ? 'Your new time is added as soon as it is confirmed.' : 'Your account opens as soon as it is confirmed.' }}
        </p>
        <dl class="sheet mx-auto mt-6 max-w-md divide-y divide-slate-100 px-4 text-left text-sm">
          <div class="flex justify-between gap-3 py-3"><dt class="text-slate-500">Package</dt><dd class="font-medium text-slate-900">{{ tierName(pending.tier) }} · <span class="capitalize">{{ pending.plan }}</span></dd></div>
          <div class="flex justify-between gap-3 py-3"><dt class="text-slate-500">Sent to</dt><dd class="font-medium text-slate-900">{{ NETWORKS[pending.network]?.label }}</dd></div>
          <div class="flex justify-between gap-3 py-3"><dt class="text-slate-500">Line registered to</dt><dd class="text-right font-semibold text-slate-900">{{ pending.senderName }}</dd></div>
          <div class="flex justify-between gap-3 py-3"><dt class="text-slate-500">Submitted</dt><dd class="font-medium text-slate-900">{{ formatDate(pending.paidOn) }}</dd></div>
        </dl>
        <p class="mx-auto mt-4 max-w-md text-sm text-slate-500">Usually within a few hours. This page updates by itself, and you'll get a message in your inbox.</p>
        <div class="mx-auto mt-6 grid max-w-md gap-2.5 sm:grid-cols-2">
          <button type="button" class="btn-primary h-12 rounded-2xl" :data-busy="checking" :disabled="checking" @click="checkNow"><RefreshCw class="size-4.5" /> {{ checking ? 'Checking…' : 'Check now' }}</button>
          <button type="button" class="btn-secondary h-12 rounded-2xl" @click="cancel">Withdraw payment</button>
        </div>
        <AppLink phone="256726128782" class="mt-5 inline-flex items-center gap-2 text-sm font-medium text-brand-700"><MessageCircle class="size-4" /> Questions? WhatsApp 0726 128782</AppLink>
      </section>

      <!-- ── Overview ── -->
      <template v-else-if="page === 'overview'">
        <header class="mb-6">
          <p class="text-xs font-semibold tracking-[0.16em] text-brand-700 uppercase">Billing</p>
          <h1 class="mt-1 text-2xl font-bold tracking-tight text-slate-900 sm:text-3xl">Subscription</h1>
        </header>
        <section class="status-card card-in relative overflow-hidden rounded-[1.75rem] p-6 sm:p-8" :class="[!s.active && 'status-ended', s.exempt && 'status-free']">
          <span class="plan-badge inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-semibold">
            <component :is="s.exempt ? BadgeCheck : s.active ? Crown : Lock" class="size-3.5" /> {{ planLabel }}
          </span>
          <p class="mt-4 flex items-center gap-2 text-2xl font-bold tracking-tight sm:text-[2rem]"><InfinityIcon v-if="s.exempt" class="size-7" /> {{ headline }}</p>
          <p class="status-sub mt-1.5 text-sm">
            <template v-if="s.exempt">This landlord account uses Renta UG at no cost, with every feature and no time limit.</template>
            <template v-else-if="s.daysLeft === 0">Today is the last day covered.</template>
            <template v-else>{{ s.daysLeft }} day{{ s.daysLeft === 1 ? '' : 's' }} left. Renew any time: new time is added on top.</template>
          </p>
          <div v-if="s.active && !s.exempt" class="meter mt-5 h-2 max-w-md overflow-hidden rounded-full"><span class="block h-full rounded-full" :style="{ width: `${meter}%` }" /></div>
          <div v-if="limit != null" class="usage mt-5 max-w-md rounded-2xl p-3.5 text-sm">
            <div class="flex justify-between"><span>Houses and rooms</span><strong class="tabular-nums">{{ units }} of {{ limit }}</strong></div>
            <div class="mt-2 h-1.5 overflow-hidden rounded-full bg-white/15"><span class="block h-full rounded-full bg-white/80" :style="{ width: `${Math.min(100, (units / limit) * 100)}%` }" /></div>
          </div>
          <!-- Permanent account: what that means, shown only here -->
          <ul v-if="s.exempt" class="perm-list mt-5 grid max-w-xl gap-2 text-sm sm:grid-cols-2">
            <li><ShieldCheck class="size-4 shrink-0" /> Permanently registered: never deleted</li>
            <li><Lock class="size-4 shrink-0" /> Can't be suspended by anyone</li>
            <li><Building2 class="size-4 shrink-0" /> Your properties, tenants and records are always kept</li>
            <li><BadgeCheck class="size-4 shrink-0" /> No payments, no end date</li>
          </ul>
        </section>

        <!-- ── Your paid subscription ── -->
        <section v-if="paid && !s.exempt" class="paid card-in mt-5 overflow-hidden rounded-[1.5rem]">
          <div class="flex flex-wrap items-start justify-between gap-3 p-5 sm:p-6">
            <div>
              <p class="flex items-center gap-2 text-xs font-semibold tracking-[0.14em] text-brand-700 uppercase"><CircleCheck class="size-4" /> Paid subscription</p>
              <p class="mt-1.5 text-lg font-bold text-slate-900 sm:text-xl">{{ tierName(paid.tier) }} · {{ paid.plan === 'yearly' ? 'Yearly' : 'Monthly' }}</p>
              <p class="mt-0.5 text-sm text-slate-500">Paid {{ formatUGX(paid.amount) }} on {{ formatDate(paid.paidOn) }} · {{ paid.network === 'cash' ? 'Cash' : NETWORKS[paid.network]?.label }}</p>
            </div>
            <span class="days-left text-right">
              <span class="block text-3xl leading-none font-extrabold tabular-nums">{{ paid.left }}</span>
              <span class="mt-1 block text-[11px] font-semibold tracking-wide uppercase">day{{ paid.left === 1 ? '' : 's' }} left</span>
            </span>
          </div>

          <!-- Timeline: start → today → end -->
          <div class="px-5 sm:px-6">
            <div class="timeline relative h-2.5 rounded-full">
              <span class="timeline-fill absolute inset-y-0 left-0 rounded-full" :style="{ width: `${Math.max(3, paid.pct)}%` }" />
              <span class="timeline-now absolute top-1/2" :style="{ left: `${Math.min(97, Math.max(3, paid.pct))}%` }" aria-hidden="true" />
            </div>
            <div class="mt-2 flex justify-between text-xs text-slate-500">
              <span>Started {{ formatDate(paid.periodStart) }}</span>
              <span>Ends {{ formatDate(paid.periodEnd) }}</span>
            </div>
          </div>

          <dl class="mt-5 grid grid-cols-2 gap-px border-t border-slate-100 bg-slate-100 sm:grid-cols-4">
            <div class="fact"><dt>Paid on</dt><dd>{{ formatDate(paid.paidOn) }}</dd></div>
            <div class="fact"><dt>Length</dt><dd>{{ paid.length }}</dd><dd class="sub">{{ paid.total }} days</dd></div>
            <div class="fact"><dt>Starts</dt><dd>{{ formatDate(paid.periodStart) }}</dd></div>
            <div class="fact"><dt>Ends</dt><dd>{{ formatDate(paid.periodEnd) }}</dd><dd class="sub">{{ paid.used }} of {{ paid.total }} days used</dd></div>
          </dl>
          <p v-if="s.until && s.until !== paid.periodEnd" class="border-t border-slate-100 px-5 py-3 text-xs text-slate-500 sm:px-6">
            <Sparkles class="mr-1 inline size-3.5 text-brand-600" />
            {{ paid.ahead ? `You have ${paid.ahead} more period${paid.ahead === 1 ? '' : 's'} paid on top.` : 'Renta UG added extra days.' }} Your subscription runs until <strong class="text-slate-900">{{ formatDate(s.until) }}</strong>.
          </p>
        </section>

        <!-- ── Control panel ── -->
        <section class="panel card-in mt-5 rounded-[1.5rem] p-5 sm:p-6">
          <div class="flex items-center justify-between gap-3">
            <div>
              <p class="text-xs font-semibold tracking-[0.14em] text-slate-400 uppercase">Control panel</p>
              <p class="mt-0.5 text-base font-semibold text-slate-900">{{ s.exempt ? 'Your account' : 'Manage your subscription' }}</p>
            </div>
            <span class="flex size-10 items-center justify-center rounded-2xl bg-brand-50 text-brand-700"><Crown class="size-5" /></span>
          </div>
          <div class="mt-4 grid grid-cols-2 gap-2.5 sm:grid-cols-3">
            <component
              :is="c.to ? 'RouterLink' : c.wa ? AppLink : 'button'"
              v-for="(c, i) in controls"
              :key="c.label"
              :to="c.to"
              :phone="c.wa"
              :type="c.run ? 'button' : undefined"
              class="ctrl"
              :class="c.tone"
              :style="{ '--i': i }"
              @click="c.run && c.run()"
            >
              <span class="ctrl-ico"><component :is="c.icon" class="size-[1.15rem]" /></span>
              <span class="mt-3 block text-sm font-semibold text-slate-900">{{ c.label }}</span>
              <span class="mt-0.5 block truncate text-xs text-slate-500">{{ c.hint }}</span>
            </component>
          </div>
        </section>
      </template>

      <!-- ── Checkout steps ── -->
      <template v-else>
        <div class="sticky top-16 z-20 -mx-4 mb-5 bg-[var(--color-slate-50)]/85 px-4 py-2 backdrop-blur-lg sm:static sm:mx-0 sm:bg-transparent sm:px-0 sm:backdrop-blur-none">
          <div class="flex items-center gap-2">
            <button v-if="stepNo > 1 || s.active" type="button" class="back-btn" @click="back"><ArrowLeft class="size-[1.1rem]" /> Back</button>
            <p class="ml-auto text-xs font-semibold tracking-[0.12em] text-slate-400 uppercase">Step {{ stepNo }} of {{ STEPS.length }}</p>
          </div>
          <div class="mt-3 grid grid-cols-5 gap-1.5" aria-hidden="true">
            <span v-for="n in STEPS.length" :key="n" class="h-1.5 rounded-full transition-colors duration-500" :class="n <= stepNo ? 'bg-brand-600' : 'bg-slate-200'" />
          </div>
        </div>

        <!-- Order chip (after the package is chosen) -->
        <div v-if="stepNo > 2" class="order-chip card-in mb-5 flex items-center gap-3 rounded-2xl p-4">
          <span class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-white/15"><Crown class="size-5" /></span>
          <div class="min-w-0 flex-1">
            <p class="text-sm font-semibold">{{ tierName(tier) }} · {{ plan === 'yearly' ? 'Yearly' : 'Monthly' }}</p>
            <p class="text-xs opacity-75">{{ formatDate(period.start) }} – {{ formatDate(period.end) }}</p>
          </div>
          <p class="text-lg font-bold tabular-nums">{{ formatUGX(price) }}</p>
        </div>

        <p v-if="lastRejected && page === 'package'" class="mb-4 rounded-2xl border border-red-200 bg-red-50 p-3.5 text-sm text-red-700">
          Your last payment of {{ formatUGX(lastRejected.amount) }} was not confirmed{{ lastRejected.rejectReason ? `: ${lastRejected.rejectReason}` : '' }}. Please pay again or contact us.
        </p>

        <Transition name="card" mode="out-in">
          <!-- 0. Business size -->
          <section v-if="page === 'capacity'" key="capacity">
            <div class="cap-hero card-in relative overflow-hidden rounded-[1.75rem] p-6 sm:p-8">
              <span class="cap-badge inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-semibold"><Building2 class="size-3.5" /> Your business</span>
              <h1 class="mt-4 text-2xl font-bold tracking-tight sm:text-3xl">How big is your rental business?</h1>
              <p class="cap-sub mt-2 max-w-lg text-[15px] leading-relaxed">
                Tell us how many houses and rooms you will register on Renta UG. We match you to the package that fits, so you only pay for what you need.
              </p>
            </div>

            <form class="sheet card-in mt-5 p-5 sm:p-7" @submit.prevent="saveCapacity">
              <label class="label" for="cap-n">Houses and rooms you will register</label>
              <div class="mt-1 flex items-stretch gap-2">
                <button type="button" class="cap-step" aria-label="One less" :disabled="capNum <= 1" @click="bump(-1)"><Minus class="size-5" /></button>
                <input id="cap-n" v-model="capacity" type="number" inputmode="numeric" min="1" max="100000" class="input cap-input h-16 flex-1 text-center text-3xl font-bold tabular-nums" placeholder="0" />
                <button type="button" class="cap-step" aria-label="One more" @click="bump(1)"><Plus class="size-5" /></button>
              </div>
              <p class="mt-2 text-xs text-slate-500">Count every house you rent out, and every room in a rental. A rental with 8 rooms counts as 8.</p>

              <div class="mt-4 flex flex-wrap gap-2">
                <button v-for="c in capChips" :key="c.label" type="button" class="cap-chip" :class="capNum === c.value && 'cap-chip-on'" @click="capacity = c.value">{{ c.label }}</button>
              </div>

              <!-- Live match -->
              <div v-if="capNum >= 1" class="cap-match mt-6 flex items-center gap-4 rounded-2xl p-4 sm:p-5">
                <span class="cap-match-ico flex size-12 shrink-0 items-center justify-center rounded-2xl"><component :is="capTier === 'big' ? Building : Home" class="size-6" /></span>
                <div class="min-w-0 flex-1">
                  <p class="text-xs font-semibold tracking-[0.12em] text-brand-700 uppercase">Your package</p>
                  <p class="mt-0.5 text-lg font-bold text-slate-900">{{ tierName(capTier) }}</p>
                  <p class="text-sm text-slate-600">
                    {{ capTier === 'big' ? 'Any number of houses and rooms' : `Up to ${max} houses and rooms` }} ·
                    from <strong class="text-slate-900 tabular-nums">{{ formatUGX(billing.price(capTier, 'monthly')) }}</strong> a month
                  </p>
                </div>
              </div>

              <p v-if="capError" class="form-error mt-4" role="alert">{{ capError }}</p>
              <button type="submit" class="btn-primary mt-6 h-13 w-full rounded-2xl text-[15px]" :data-busy="capBusy" :disabled="capBusy || capNum < 1">
                {{ capBusy ? 'Saving…' : 'Continue to packages' }} <ArrowRight class="size-4.5" />
              </button>
              <p class="mt-3 text-center text-xs text-slate-400">You can change this later. Small scale stops at {{ max }}; Big scale has no limit.</p>
            </form>
          </section>

          <!-- 1. Package -->
          <section v-else-if="page === 'package'" key="package">
            <h1 class="text-xl font-bold tracking-tight text-slate-900 sm:text-2xl">Choose your package</h1>
            <p class="mt-1 text-sm text-slate-500">
              <template v-if="!s.active && !s.until">Pay to open your Renta UG account. </template>
              <template v-if="planned != null">You will register <strong class="text-slate-900">{{ need }} house{{ need === 1 ? '' : 's' }} and rooms</strong></template>
              <template v-else>You have <strong class="text-slate-900">{{ units }} house{{ units === 1 ? '' : 's' }} and rooms</strong></template>;
              we recommend <strong class="text-brand-700">{{ tierName(recommended) }}</strong>.
              <button type="button" class="font-semibold text-brand-700 underline-offset-2 hover:underline" @click="go({ step: 'capacity' })">Change</button>
            </p>
            <div class="mt-4 grid gap-3 sm:grid-cols-2">
              <button
                v-for="sc in scales" :key="sc.id" type="button"
                class="plan-card relative rounded-2xl p-5 text-left transition"
                :class="[tier === sc.id && 'plan-on', sc.id === 'small' && !smallAllowed && 'cursor-not-allowed opacity-55']"
                :disabled="sc.id === 'small' && !smallAllowed" :aria-pressed="tier === sc.id"
                @click="go({ tier: sc.id })"
              >
                <span v-if="recommended === sc.id" class="best absolute -top-2.5 right-4 inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[11px] font-bold"><Sparkles class="size-3" /> Recommended</span>
                <span class="flex items-center justify-between">
                  <span class="flex items-center gap-2 text-sm font-semibold text-slate-900"><span class="feat-ico"><component :is="sc.icon" class="size-3.5" /></span> {{ sc.name }}</span>
                  <span class="radio" :class="tier === sc.id && 'radio-on'"><Check v-if="tier === sc.id" class="size-3" /></span>
                </span>
                <span class="mt-3 block text-xl font-bold tracking-tight text-slate-900 tabular-nums">{{ formatUGX(billing.price(sc.id, 'monthly')) }}<span class="text-xs font-medium text-slate-500"> / month</span></span>
                <span class="block text-xs text-slate-500">or {{ formatUGX(billing.price(sc.id, 'yearly')) }} / year</span>
                <span class="mt-3 block text-xs font-semibold text-slate-700">{{ sc.fits }}</span>
                <span class="block text-xs leading-relaxed text-slate-500">{{ sc.who }}</span>
                <span v-if="sc.id === 'small' && !smallAllowed" class="mt-2 block text-xs font-semibold text-amber-700">{{ need }} is more than {{ max }}: choose Big scale.</span>
              </button>
            </div>

            <p class="mt-6 text-sm font-semibold text-slate-900">Pay monthly or yearly</p>
            <div class="period mt-2 grid grid-cols-2 gap-1 rounded-2xl p-1">
              <button v-for="pl in ['monthly', 'yearly']" :key="pl" type="button" class="relative rounded-xl px-3 py-3 text-left transition" :class="plan === pl ? 'period-on' : 'text-slate-600'" @click="go({ plan: pl })">
                <span class="block text-sm font-semibold">{{ pl === 'yearly' ? 'Yearly' : 'Monthly' }}</span>
                <span class="block text-xs tabular-nums opacity-80">{{ formatUGX(billing.price(tier, pl)) }} {{ pl === 'yearly' ? '/ year' : '/ month' }}</span>
                <span v-if="pl === 'yearly' && billing.yearlySavingPct(tier)" class="save-tag absolute top-2 right-2 rounded-full px-2 py-0.5 text-[10px] font-bold">Save {{ billing.yearlySavingPct(tier) }}%</span>
              </button>
            </div>
            <ul class="mt-5 grid gap-2.5 sm:grid-cols-2">
              <li v-for="f in features" :key="f[1]" class="flex items-center gap-2.5 text-sm text-slate-600"><span class="feat-ico"><component :is="f[0]" class="size-3.5" /></span> {{ f[1] }}</li>
            </ul>
            <button type="button" class="btn-primary mt-6 h-12 w-full rounded-2xl text-[15px]" :disabled="tier === 'small' && !smallAllowed" @click="go({ step: 'line' })">
              Continue · {{ formatUGX(price) }} <ArrowRight class="size-4.5" />
            </button>
          </section>

          <!-- 2. Line to pay to -->
          <section v-else-if="page === 'line'" key="line">
            <h1 class="text-xl font-bold tracking-tight text-slate-900 sm:text-2xl">Select the line to pay to</h1>
            <p class="mt-1 text-sm text-slate-500">You send the money from your phone to Renta UG.</p>
            <p v-if="!accounts.length" class="mt-4 rounded-2xl bg-white p-4 text-sm text-slate-600 ring-1 ring-slate-200">
              Renta UG hasn't added its payment numbers yet. Please contact us on WhatsApp 0726 128782.
            </p>
            <div class="mt-4 grid gap-3">
              <button
                v-for="id in NETWORK_IDS" :key="id" type="button"
                class="sim-card group flex items-center gap-4 rounded-2xl p-4 text-left transition"
                :class="accountFor(id) ? 'hover:-translate-y-0.5 active:scale-[0.98]' : 'cursor-not-allowed opacity-55'"
                :disabled="!accountFor(id)"
                @click="go({ sim: id, step: 'send' })"
              >
                <span class="sim-chip flex size-14 shrink-0 items-center justify-center rounded-2xl text-sm font-extrabold" :style="{ background: NETWORKS[id].gradient, color: NETWORKS[id].ink }">{{ NETWORKS[id].short.toUpperCase() }}</span>
                <span class="min-w-0 flex-1">
                  <span class="block font-semibold text-slate-900">{{ NETWORKS[id].label }}</span>
                  <span class="block truncate text-xs text-slate-500">{{ accountFor(id) ? `Pay to ${accountFor(id).accountName}` : 'Not available' }}</span>
                </span>
                <ChevronRight v-if="accountFor(id)" class="size-5 shrink-0 text-slate-300 transition group-hover:translate-x-0.5" />
              </button>
            </div>
            <p class="mt-5 flex items-center justify-center gap-1.5 text-xs text-slate-400"><ShieldCheck class="size-3.5" /> Renta UG never asks for your PIN</p>
          </section>

          <!-- 3. Instructions -->
          <section v-else-if="page === 'send'" key="send">
            <h1 class="text-xl font-bold tracking-tight text-slate-900 sm:text-2xl">Send the money</h1>
            <p class="mt-1 text-sm text-slate-500">Follow these steps on your phone, then come back and continue.</p>
            <div class="sheet mt-4 divide-y divide-slate-100">
              <div class="flex items-center gap-3 p-4">
                <div class="min-w-0 flex-1">
                  <p class="text-xs font-medium text-slate-500">Send to ({{ net.label }})</p>
                  <p class="mt-0.5 text-2xl font-bold tracking-wide text-slate-900 tabular-nums">{{ prettyPhone(account.phone) }}</p>
                  <p class="mt-0.5 truncate text-sm text-slate-600">Name shown: <strong class="text-slate-900">{{ account.accountName }}</strong></p>
                </div>
                <button type="button" class="copy-btn" :class="copied === 'phone' && 'copy-done'" @click="copy('phone', localNumber(account.phone))">
                  <Check v-if="copied === 'phone'" class="size-4" /><Copy v-else class="size-4" /> {{ copied === 'phone' ? 'Copied' : 'Copy' }}
                </button>
              </div>
              <div class="flex items-center gap-3 p-4">
                <div class="min-w-0 flex-1">
                  <p class="text-xs font-medium text-slate-500">Amount</p>
                  <p class="mt-0.5 text-2xl font-bold tracking-wide text-slate-900 tabular-nums">{{ formatUGX(price) }}</p>
                </div>
                <button type="button" class="copy-btn" :class="copied === 'amount' && 'copy-done'" @click="copy('amount', String(price))">
                  <Check v-if="copied === 'amount'" class="size-4" /><Copy v-else class="size-4" /> {{ copied === 'amount' ? 'Copied' : 'Copy' }}
                </button>
              </div>
              <div class="p-4">
                <p class="text-sm font-semibold text-slate-900">How to send</p>
                <ol class="mt-3 space-y-3">
                  <li v-for="(st, i) in steps" :key="i" class="flex gap-3 text-sm leading-relaxed text-slate-700">
                    <span class="step-no" :class="`net-${sim}`">{{ i + 1 }}</span>
                    <span class="pt-0.5">{{ st }}</span>
                  </li>
                </ol>
              </div>
            </div>
            <div class="mt-5 grid gap-2.5">
              <a v-if="dial" :href="dialHref(dial)" class="dial-btn" :style="{ background: net.gradient, color: net.ink }"><Phone class="size-5" /> Dial {{ dial }}</a>
              <button type="button" class="btn-primary h-12 rounded-2xl text-[15px]" @click="go({ step: 'confirm' })">I've sent the money <ArrowRight class="size-4.5" /></button>
            </div>
          </section>

          <!-- 4. Confirm -->
          <section v-else-if="page === 'confirm'" key="confirm">
            <h1 class="text-xl font-bold tracking-tight text-slate-900 sm:text-2xl">Confirm your payment</h1>
            <p class="mt-1 text-sm text-slate-500">Renta UG finds your payment by the names registered on the line you sent it from.</p>
            <form class="sheet mt-4 space-y-4 p-4 sm:p-5" @submit.prevent="submit">
              <div>
                <label class="label" for="sub-name">Full names registered on the line you used</label>
                <div class="relative">
                  <User class="pointer-events-none absolute top-1/2 left-3.5 size-4.5 -translate-y-1/2 text-slate-400" />
                  <input id="sub-name" v-model="name" class="input h-12 pl-10 text-base uppercase" placeholder="e.g. JOHN BOSCO MUKASA" autocomplete="name" data-cap="characters" />
                </div>
                <p v-if="touched && nameError" class="field-error mt-1.5">{{ nameError }}</p>
                <p v-else class="mt-1.5 text-xs text-slate-500">Exactly as the network shows them when money is sent from that line.</p>
              </div>
              <dl class="divide-y divide-slate-100 rounded-2xl bg-slate-50 px-4 text-sm">
                <div class="flex justify-between gap-3 py-2.5"><dt class="text-slate-500">Amount sent</dt><dd class="font-semibold text-slate-900 tabular-nums">{{ formatUGX(price) }}</dd></div>
                <div class="flex justify-between gap-3 py-2.5"><dt class="text-slate-500">Package</dt><dd class="font-medium text-slate-900">{{ tierName(tier) }} · {{ plan === 'yearly' ? 'Yearly' : 'Monthly' }}</dd></div>
                <div class="flex justify-between gap-3 py-2.5"><dt class="text-slate-500">Sent to</dt><dd class="text-right font-medium text-slate-900">{{ net.short }} {{ prettyPhone(account.phone) }}</dd></div>
              </dl>
              <label class="flex items-start gap-3 rounded-2xl border border-slate-200 p-3 text-sm text-slate-700">
                <input v-model="sentMoney" type="checkbox" class="size-5 accent-brand-600" />
                <span>I have sent this money, and the names above are exactly as registered on the line I used.</span>
              </label>
              <p v-if="error" class="form-error" role="alert">{{ error }}</p>
              <button type="submit" class="btn-primary h-12 w-full rounded-2xl text-[15px]" :data-busy="busy" :disabled="busy"><Send class="size-4.5" /> {{ busy ? 'Submitting…' : 'Submit payment' }}</button>
            </form>
          </section>
        </Transition>
      </template>

      <!-- ── Billing history (overview only) ── -->
      <section v-if="page === 'overview' && !s.exempt && !welcome" id="billing-history" class="mt-10 scroll-mt-20">
        <h2 class="flex items-center gap-2 text-lg font-semibold text-slate-900"><Receipt class="size-5 text-brand-600" /> Billing history</h2>
        <div v-if="!history.length" class="sheet mt-3"><EmptyState compact kind="money" title="No payments yet" text="Your subscription payments appear here." /></div>
        <ul v-else class="sheet mt-3 divide-y divide-slate-100">
          <li v-for="p in history" :key="p.id" class="flex flex-wrap items-center gap-x-4 gap-y-1 px-5 py-4 text-sm">
            <div class="min-w-0 flex-1">
              <p class="font-medium text-slate-900">{{ tierName(p.tier) }} · <span class="capitalize">{{ p.plan }}</span> · {{ formatUGX(p.amount) }}</p>
              <p class="text-xs text-slate-500">
                {{ formatDate(p.paidOn) }} · {{ paidWith(p.network) }}<template v-if="p.network !== 'cash'"> · {{ p.senderName }}</template>
                <template v-if="p.periodStart"> · covers {{ formatDate(p.periodStart) }} – {{ formatDate(p.periodEnd) }} ({{ days(p) }} days)</template>
                <template v-else-if="p.status === 'rejected'"> · {{ p.rejectReason || 'The money was not found' }}</template>
              </p>
            </div>
            <span class="pill" :class="statusPill[p.status][2]"><component :is="statusPill[p.status][1]" class="size-3.5" /> {{ statusPill[p.status][0] }}</span>
          </li>
        </ul>
      </section>
    </template>
  </div>
</template>

<style scoped>
.status-card {
  --color-white: #fff;
  color: #fff;
  background:
    radial-gradient(28rem 16rem at 95% -10%, rgb(250 204 21 / 0.18), transparent 70%),
    radial-gradient(30rem 18rem at -10% 120%, rgb(45 212 191 / 0.25), transparent 70%),
    linear-gradient(135deg, #0b1324 0%, #0a2a2c 55%, #0f4c47 100%);
  box-shadow: 0 30px 60px -34px rgb(10 42 44 / 0.9);
}
.status-ended { background: radial-gradient(28rem 16rem at 95% -10%, rgb(248 113 113 / 0.22), transparent 70%), linear-gradient(135deg, #1c1917 0%, #3b1414 60%, #511c1c 100%); }
.status-free { background: radial-gradient(28rem 16rem at 95% -10%, rgb(250 204 21 / 0.3), transparent 70%), linear-gradient(135deg, #0b1324 0%, #2b2006 60%, #4a3508 100%); }
.status-sub { color: rgb(255 255 255 / 0.72); }
.plan-badge { color: #fde68a; background: rgb(250 204 21 / 0.14); box-shadow: inset 0 0 0 1px rgb(250 204 21 / 0.35); }
.status-ended .plan-badge { color: #fecaca; background: rgb(248 113 113 / 0.16); box-shadow: inset 0 0 0 1px rgb(248 113 113 / 0.4); }
.meter { background: rgb(var(--glass) / 0.14); }
.meter span { background: linear-gradient(90deg, #5eead4, #facc15); }
.usage { background: rgb(var(--glass) / 0.08); box-shadow: inset 0 0 0 1px rgb(var(--glass) / 0.14); }

.perm-list li { display: flex; align-items: center; gap: 0.5rem; border-radius: 0.9rem; padding: 0.55rem 0.75rem; color: #fde68a; background: rgb(250 204 21 / 0.08); box-shadow: inset 0 0 0 1px rgb(250 204 21 / 0.22); }

/* Paid subscription card */
.paid { background: var(--color-white); box-shadow: inset 0 0 0 1px var(--color-slate-200), 0 20px 40px -30px rgb(15 23 42 / 0.45); }
.days-left { color: var(--color-brand-700); }
.timeline { background: var(--color-slate-100); }
.timeline-fill { background: linear-gradient(90deg, #2dd4bf, #0f766e); transition: width 1s cubic-bezier(0.22, 1, 0.36, 1); }
.timeline-now {
  width: 1rem; height: 1rem; margin: -0.5rem 0 0 -0.5rem; border-radius: 9999px;
  background: var(--color-white); box-shadow: 0 0 0 3px #0f766e, 0 4px 10px -2px rgb(15 118 110 / 0.6);
  animation: now-pulse 2.2s ease-out infinite;
}
@keyframes now-pulse { 0% { box-shadow: 0 0 0 3px #0f766e, 0 0 0 3px rgb(15 118 110 / 0.35); } 100% { box-shadow: 0 0 0 3px #0f766e, 0 0 0 12px rgb(15 118 110 / 0); } }
.fact { background: var(--color-white); padding: 0.9rem 1.1rem; }
.fact dt { font-size: 0.7rem; font-weight: 600; letter-spacing: 0.06em; text-transform: uppercase; color: var(--color-slate-500); }
.fact dd { margin-top: 0.2rem; font-size: 0.9rem; font-weight: 600; color: var(--color-slate-900); }
.fact dd.sub { margin-top: 0.1rem; font-size: 0.72rem; font-weight: 500; color: var(--color-slate-500); }

/* Control panel */
.panel { background: var(--color-white); box-shadow: inset 0 0 0 1px var(--color-slate-200), 0 20px 40px -30px rgb(15 23 42 / 0.45); }
.ctrl {
  display: block; border-radius: 1.1rem; padding: 0.95rem; text-align: left;
  background: var(--color-slate-50); box-shadow: inset 0 0 0 1px var(--color-slate-200);
  transition: transform 0.2s ease, box-shadow 0.2s ease, background-color 0.2s ease;
  animation: card-in 0.45s cubic-bezier(0.16, 1, 0.3, 1) backwards; animation-delay: calc(var(--i) * 45ms + 80ms);
}
.ctrl:hover { transform: translateY(-2px); background: var(--color-white); box-shadow: inset 0 0 0 1px var(--color-slate-300), 0 12px 24px -18px rgb(15 23 42 / 0.5); }
.ctrl:active { transform: scale(0.97); }
.ctrl-ico { --color-white: #fff; display: flex; width: 2.25rem; height: 2.25rem; align-items: center; justify-content: center; border-radius: 0.8rem; color: #fff; box-shadow: 0 8px 16px -10px rgb(0 0 0 / 0.6); }
.c-teal .ctrl-ico { background: linear-gradient(140deg, #2dd4bf, #0f766e); }
.c-gold .ctrl-ico { background: linear-gradient(140deg, #fbbf24, #b45309); }
.c-sky .ctrl-ico { background: linear-gradient(140deg, #38bdf8, #0369a1); }
.c-violet .ctrl-ico { background: linear-gradient(140deg, #a78bfa, #6d28d9); }
.c-slate .ctrl-ico { background: linear-gradient(140deg, #94a3b8, #334155); }
.c-green .ctrl-ico { background: linear-gradient(140deg, #4ade80, #15803d); }

/* 0. Business size */
.cap-hero {
  --color-white: #fff;
  color: #fff;
  background:
    radial-gradient(26rem 14rem at 100% -10%, rgb(250 204 21 / 0.2), transparent 70%),
    radial-gradient(28rem 16rem at -10% 120%, rgb(45 212 191 / 0.28), transparent 70%),
    linear-gradient(135deg, #0b1324 0%, #0a2a2c 55%, #0f4c47 100%);
  box-shadow: 0 30px 60px -34px rgb(10 42 44 / 0.9);
}
.cap-badge { color: #fde68a; background: rgb(250 204 21 / 0.14); box-shadow: inset 0 0 0 1px rgb(250 204 21 / 0.35); }
.cap-sub { color: rgb(255 255 255 / 0.75); }
.cap-input { -moz-appearance: textfield; appearance: textfield; }
.cap-input::-webkit-outer-spin-button, .cap-input::-webkit-inner-spin-button { -webkit-appearance: none; margin: 0; }
.cap-step {
  display: flex; width: 4rem; flex-shrink: 0; align-items: center; justify-content: center; border-radius: 1rem;
  color: var(--color-brand-700); background: var(--color-brand-50); transition: transform 0.1s ease;
}
.cap-step:active:not(:disabled) { transform: scale(0.94); }
.cap-step:disabled { opacity: 0.4; }
.cap-chip {
  border-radius: 9999px; padding: 0.45rem 0.9rem; font-size: 0.8rem; font-weight: 600;
  color: var(--color-slate-600); background: var(--color-slate-100); transition: background-color 0.15s ease, color 0.15s ease;
}
.cap-chip-on { color: #fff; background: #0f766e; }
.cap-match { background: var(--color-brand-50); box-shadow: inset 0 0 0 1.5px var(--color-brand-200); }
.cap-match-ico { --color-white: #fff; color: #fff; background: linear-gradient(140deg, #2dd4bf, #0f766e); box-shadow: 0 10px 20px -12px rgb(15 118 110 / 0.8); }

.order-chip {
  --color-white: #fff;
  color: #fff;
  background: linear-gradient(135deg, #14918a 0%, #0f766e 45%, #0a3b38 100%);
  box-shadow: 0 20px 45px -28px rgb(10 59 56 / 0.7);
}
.back-btn { display: flex; height: 2.75rem; align-items: center; gap: 0.4rem; border-radius: 1rem; padding: 0 1rem 0 0.75rem; font-size: 0.875rem; font-weight: 600; color: var(--color-slate-700); background: var(--color-white); box-shadow: 0 1px 2px rgb(15 23 42 / 0.06), inset 0 0 0 1px var(--color-slate-200); }
.back-btn:active { transform: scale(0.96); }

.plan-card { background: var(--color-white); box-shadow: inset 0 0 0 1px var(--color-slate-200); }
.plan-card:not(:disabled):hover { box-shadow: inset 0 0 0 1px var(--color-slate-300), 0 10px 24px -18px rgb(15 23 42 / 0.4); }
.plan-on, .plan-on:not(:disabled):hover { background: var(--color-brand-50); box-shadow: inset 0 0 0 2px var(--color-brand-500), 0 14px 30px -20px rgb(15 118 110 / 0.6); }
.best { color: #422006; background: linear-gradient(135deg, #fde68a, #facc15); box-shadow: 0 6px 14px -8px rgb(202 138 4 / 0.9); }
.radio { display: flex; width: 1.25rem; height: 1.25rem; flex-shrink: 0; align-items: center; justify-content: center; border-radius: 9999px; box-shadow: inset 0 0 0 1.5px var(--color-slate-300); }
.radio-on { color: #fff; background: #0f766e; box-shadow: none; }
.feat-ico { display: flex; width: 1.5rem; height: 1.5rem; flex-shrink: 0; align-items: center; justify-content: center; border-radius: 0.5rem; color: var(--color-brand-700); background: var(--color-brand-50); }
.period { background: var(--color-slate-100); }
.period-on { color: var(--color-slate-900); background: var(--color-white); box-shadow: 0 1px 2px rgb(15 23 42 / 0.08), 0 6px 16px -10px rgb(15 23 42 / 0.3); }
.save-tag { color: var(--color-emerald-800); background: var(--color-emerald-50); }

.sim-card { background: var(--color-white); box-shadow: inset 0 0 0 1px var(--color-slate-200); }
.sim-card:not(:disabled):hover { box-shadow: inset 0 0 0 1px var(--color-slate-300), 0 12px 26px -18px rgb(15 23 42 / 0.4); }
.sim-chip { box-shadow: 0 8px 18px -10px rgb(0 0 0 / 0.45); }

.copy-btn { display: inline-flex; height: 2.5rem; flex-shrink: 0; align-items: center; gap: 0.4rem; border-radius: 0.8rem; padding: 0 0.85rem; font-size: 0.8rem; font-weight: 600; color: var(--color-brand-700); background: var(--color-brand-50); }
.copy-btn:active { transform: scale(0.96); }
.copy-done { color: var(--color-emerald-700); background: var(--color-emerald-50); }
.step-no { display: flex; width: 1.6rem; height: 1.6rem; flex-shrink: 0; align-items: center; justify-content: center; border-radius: 9999px; font-size: 0.75rem; font-weight: 700; }
.dial-btn { display: inline-flex; height: 3rem; align-items: center; justify-content: center; gap: 0.5rem; border-radius: 1rem; font-size: 1rem; font-weight: 700; box-shadow: 0 10px 22px -14px rgb(0 0 0 / 0.6); }

.pill { display: inline-flex; align-items: center; gap: 0.3rem; border-radius: 9999px; padding: 0.2rem 0.6rem; font-size: 0.75rem; font-weight: 600; }
.pill-ok { color: var(--color-emerald-700); background: var(--color-emerald-50); }
.pill-wait { color: var(--color-amber-700); background: var(--color-amber-50); }
.pill-bad { color: var(--color-red-700); background: var(--color-red-50); }
.pill-off { color: var(--color-slate-500); background: var(--color-slate-100); }

.wait-ring { animation: ring 2s ease-out infinite; }
@keyframes ring { 0% { box-shadow: 0 0 0 0 rgb(245 158 11 / 0.35); } 100% { box-shadow: 0 0 0 18px rgb(245 158 11 / 0); } }
.ok-ring { box-shadow: 0 0 0 10px rgb(16 185 129 / 0.08); }
.card-in { animation: card-in 0.45s cubic-bezier(0.16, 1, 0.3, 1) backwards; }
@keyframes card-in { from { opacity: 0; transform: translateY(10px); } }
.card-enter-active, .card-leave-active { transition: opacity 0.3s ease, transform 0.35s cubic-bezier(0.16, 1, 0.3, 1); }
.card-enter-from { opacity: 0; transform: translateX(24px); }
.card-leave-to { opacity: 0; transform: translateX(-24px); }
@media (prefers-reduced-motion: reduce) {
  .card-in, .wait-ring, .ctrl, .timeline-now { animation: none; }
  .card-enter-active, .card-leave-active { transition: none; }
}
</style>
