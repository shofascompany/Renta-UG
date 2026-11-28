<script setup>
import { computed, nextTick, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  ArrowLeft, Banknote, Smartphone, ImageDown, Loader2, MessageCircle, HandCoins, RotateCcw, CheckCircle2, ChevronRight,
  Hash, StickyNote, CalendarRange, CircleAlert,
} from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useReceiptDownload } from '@/composables/useReceiptDownload'
import { askConfirm } from '@/composables/useConfirm'
import { paymentOf, cashRecordOf } from '@/utils/paymentGroups'
import { formatUGX, formatDate, formatPeriod, dayOf } from '@/utils/format'
import { addDays, daysBetween, durationText, isoDay, RENT_MONTH_DAYS } from '@/utils/rentCycle'
import RecordPaymentModal from '@/components/RecordPaymentModal.vue'
import EmptyState from '@/components/EmptyState.vue'

// One tenant's rent month as a full page: the month, then every payment made towards it, each one WHOLE: its total,
// every month it paid with the dates each one covers, the day its rental time starts and its final date, the debt days
// it paid first. Its receipt (download or WhatsApp) and Reverse payment, which takes the whole payment back
// (database/63). Opened from Payments (a rent month) and Transactions (?receipt= shows that payment first).
const props = defineProps({ id: { type: String, required: true } })
const route = useRoute()
const router = useRouter()
const rental = useRentalStore()
const { saving, savePayment, sharePayment, canShare, instalmentsFor, windowsFor } = useReceiptDownload()

const charge = computed(() => rental.payments.find((p) => p.id === props.id) ?? null)
const tenant = computed(() => (charge.value ? rental.tenantById(charge.value.tenantId) : null))
const tenantName = computed(() => tenant.value?.name ?? 'Former tenant')
const firstName = computed(() => tenantName.value.split(' ')[0])
const initials = computed(() => tenantName.value.split(' ').map((w) => w[0]).slice(0, 2).join('').toUpperCase())
const house = computed(() => (charge.value && rental.propertyById(charge.value.propertyId) ? rental.placeName(charge.value.propertyId) : 'Removed house'))
const tenantLink = computed(() => {
  const t = tenant.value
  if (!t) return charge.value ? `/landlord/properties/${charge.value.propertyId}` : '/landlord/tenants'
  return t.managedByLandlord ? `/landlord/managed/${t.id}` : t.propertyId ? `/landlord/tenants/${t.id}` : `/landlord/properties/${charge.value.propertyId}`
})
const plan = computed(() => (charge.value ? instalmentsFor(charge.value.id) : null))
const onlyMonth = computed(() => route.query.only === 'month')
const periodOf = (paymentId) => rental.payments.find((p) => p.id === paymentId)?.period ?? ''
// The rental time each receipt bought, worked back from the day the rent ends now
const windows = computed(() => (charge.value ? windowsFor(charge.value.tenantId) : new Map()))

// Every payment towards this month, newest first, each one whole (every month it paid)
const payments = computed(() => {
  if (!plan.value) return []
  const seen = new Set()
  return [...plan.value.rows]
    .reverse()
    .map((row) => paymentOf(rental.payment_receipts, row.id, periodOf))
    .filter((p) => p && !seen.has(p.key) && seen.add(p.key))
    // Opened from a month (any sort but the date of payment): only this month's part of each payment
    .map((p) => {
      if (!onlyMonth.value) return p
      const receipts = p.receipts.filter((r) => r.paymentId === props.id)
      return { ...p, receipts, id: receipts[0]?.id ?? p.id, total: receipts.reduce((s, r) => s + r.amount, 0), whole: p.total }
    })
    .map((p) => {
      const months = p.receipts.map((r) => ({ id: r.id, period: periodOf(r.paymentId), amount: r.amount, window: windows.value.get(r.id) ?? null, here: r.paymentId === props.id }))
      const ws = months.map((m) => m.window).filter(Boolean)
      const from = ws.length ? ws.map((w) => w.from).sort()[0] : null
      const to = ws.length ? ws.map((w) => w.to).sort().at(-1) : null
      const days = ws.reduce((s, w) => s + w.days, 0)
      // Time that started before the day it was paid: debt days, paid first
      const payDay = dayOf(p.at)
      const debt = from && payDay && from < payDay ? Math.min(days, daysBetween(from, payDay)) : 0
      return {
        ...p, months, from, to, days, debt, added: days - debt,
        cash: cashRecordOf(p, rental.cash_payments),
        here: months.find((m) => m.here)?.amount ?? 0,
        focus: p.receipts.some((r) => r.id === route.query.receipt),
      }
    })
})
const only = computed(() => (payments.value.length === 1 ? payments.value[0] : null))

const statusText = { paid: 'Paid', pending: 'Due', overdue: 'Overdue' }
const isCash = (p) => /cash/i.test(p.method ?? '')
const methodText = (p) => (isCash(p) ? 'Cash' : p.method || 'Mobile money')
const dayMonth = (d) => new Date(d).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })
const range = (w) => (w.from.slice(0, 4) === w.to.slice(0, 4) ? `${dayMonth(w.from)} – ${formatDate(w.to)}` : `${formatDate(w.from)} – ${formatDate(w.to)}`)
const daysWord = (n) => `${n} day${n === 1 ? '' : 's'}`

// ── Record a payment (the month is not paid in full) ──
const recordOpen = ref(false)

// ── Reverse: the whole payment, after asking ──
const done = ref('')
// What it leaves: the rental time goes back by the days it gave; their only payment → no paid time
function afterReverse(p) {
  const t = tenant.value
  if (!t?.propertyId || !t.leaseEnd || !p.days) return null
  const end = isoDay(addDays(new Date(`${String(t.leaseEnd).slice(0, 10)}T12:00:00`), -p.days))
  const start = t.leaseStart ? String(t.leaseStart).slice(0, 10) : null
  const others = rental.payment_receipts.some((r) => r.tenantId === t.id && !p.receipts.some((x) => x.id === r.id))
  if (!others && (!start || end <= start)) return { back: p.days, end: null }
  return { back: p.days, end: start && end < start ? start : end }
}
async function reverse(p) {
  const after = afterReverse(p)
  const time = !after ? '' : after.end ? ` ${firstName.value}'s rental time goes back ${durationText(after.back)}, to ${formatDate(after.end)}.` : ` ${firstName.value} will have no paid rental time.`
  let result = null
  const ok = await askConfirm({
    title: 'Reverse this payment?',
    text: `${formatUGX(p.total)} from ${tenantName.value}, paid ${formatDate(p.at)}, will be taken off as if it was never made.`,
    note: `It paid ${p.months.map((m) => formatPeriod(m.period)).join(', ')}.${time} ${firstName.value} gets a notification. This cannot be undone.`,
    confirm: 'Yes, reverse it',
    cancel: 'Keep payment',
    working: 'Reversing…',
    tone: 'danger',
    icon: RotateCcw,
    action: async () => {
      result = await rental.reversePayment(p.id)
    },
  })
  if (!ok || !result) return
  const end = result.paid_to ? ` ${firstName.value}'s rental time now runs to ${formatDate(result.paid_to)}.` : result.days_back ? ` ${firstName.value} has no paid rental time now.` : ''
  done.value = `${formatUGX(result.reversed)} was taken off ${(result.months ?? []).map(formatPeriod).join(', ')}.${end} ${firstName.value} has been notified.`
  window.scrollTo({ top: 0, behavior: 'smooth' })
}

function back() {
  if (window.history.state?.back) router.back()
  else router.push('/landlord/payments')
}

// From Transactions: the payment it was about is the one shown first
onMounted(async () => {
  if (!charge.value && route.query.receipt) {
    const r = rental.payment_receipts.find((x) => x.id === route.query.receipt)
    if (r?.paymentId && r.paymentId !== props.id) return router.replace({ path: `/landlord/payments/${r.paymentId}`, query: route.query })
  }
  await nextTick()
  if (route.query.receipt) document.querySelector('.pd-focus')?.scrollIntoView({ block: 'start', behavior: 'smooth' })
})
</script>

<template>
  <div class="mx-auto max-w-3xl">
    <button type="button" class="mb-4 inline-flex items-center gap-1.5 py-1 text-sm font-medium text-slate-500 hover:text-slate-900" @click="back">
      <ArrowLeft class="size-4" /> Payments
    </button>

    <!-- Reversed just now -->
    <div v-if="done" class="rise mb-5 flex items-start gap-3 rounded-2xl border border-emerald-200 bg-emerald-50 p-4" role="status" data-reversed>
      <CheckCircle2 class="mt-0.5 size-5 shrink-0 text-emerald-600" />
      <div class="min-w-0 flex-1 text-sm text-emerald-900">
        <p class="font-semibold">Payment reversed</p>
        <p class="mt-0.5">{{ done }}</p>
      </div>
    </div>

    <template v-if="charge">
      <!-- The month -->
      <section class="pd-hero rise rounded-3xl px-5 py-6 sm:px-7 sm:py-7" :class="`pd-${charge.status}`">
        <p class="text-xs font-semibold tracking-[0.14em] text-white/80 uppercase">{{ formatPeriod(charge.period) }} · {{ statusText[charge.status] }}</p>
        <p class="mt-2 text-[2rem] leading-tight font-bold tracking-tight tabular-nums sm:text-4xl">{{ formatUGX(charge.status === 'paid' ? charge.amount : charge.balance) }}</p>
        <p class="mt-1 text-sm text-white/85">
          <template v-if="charge.status === 'paid'">Rent paid in full{{ charge.paidAt ? ` on ${formatDate(charge.paidAt)}` : '' }}</template>
          <template v-else-if="charge.amountPaid">Still owed · {{ formatUGX(charge.amountPaid) }} of {{ formatUGX(charge.amount) }} paid</template>
          <template v-else>Owed · due {{ formatDate(charge.dueDate) }}</template>
        </p>
        <div class="mt-5 flex items-center gap-3 rounded-2xl p-3 pd-glass">
          <span class="flex size-10 shrink-0 items-center justify-center rounded-xl pd-glass text-sm font-bold">{{ initials }}</span>
          <div class="min-w-0 flex-1">
            <p class="truncate font-semibold">{{ tenantName }}</p>
            <p class="truncate text-xs text-white/80">{{ house }}</p>
          </div>
          <RouterLink :to="tenantLink" class="pd-chip">Open <ChevronRight class="size-3.5" /></RouterLink>
        </div>
      </section>

      <!-- One payment: its receipt, straight away -->
      <div v-if="only" class="mt-4 grid gap-2.5" :class="canShare && 'sm:grid-cols-2'">
        <button type="button" class="btn-primary h-12 rounded-2xl" :data-busy="saving === only.id" :disabled="Boolean(saving)" @click="savePayment(only)">
          <Loader2 v-if="saving === only.id" class="size-4 animate-spin" /><ImageDown v-else class="size-4" /> {{ saving === only.id ? 'Saving…' : 'Download receipt' }}
        </button>
        <button v-if="canShare" type="button" class="wa-btn h-12 rounded-2xl" @click="sharePayment(only)"><MessageCircle class="size-4" /> Share on WhatsApp</button>
      </div>

      <!-- Each payment, whole -->
      <section v-for="(p, i) in payments" :key="p.key" class="rise mt-6" :style="{ '--d': `${60 + i * 40}ms` }">
        <h2 class="section-title">{{ payments.length > 1 ? `Payment ${payments.length - i} of ${payments.length}` : 'Payment' }}</h2>
        <div class="sheet overflow-hidden" :class="p.focus && 'pd-focus'">
          <!-- The total -->
          <div class="flex items-start gap-3.5 p-4 sm:p-5">
            <span class="icon-disc" :class="isCash(p) ? 'disc-amber' : 'disc-emerald'"><Banknote v-if="isCash(p)" class="size-5" /><Smartphone v-else class="size-5" /></span>
            <div class="min-w-0 flex-1">
              <p class="text-2xl font-bold tracking-tight text-slate-900 tabular-nums" data-total>{{ formatUGX(p.total) }}</p>
              <p class="mt-0.5 text-sm text-slate-500">{{ methodText(p) }} · paid {{ formatDate(p.at) }}</p>
              <p v-if="p.whole && p.whole !== p.total" class="mt-0.5 text-xs text-slate-500" data-part-of>
                This month's part of a payment of {{ formatUGX(p.whole) }}.
                <RouterLink :to="{ path: route.path, query: { receipt: p.id } }" class="font-semibold text-brand-700" replace>See the whole payment</RouterLink>
              </p>
              <p v-if="p.cash" class="mt-0.5 text-xs text-slate-400">Confirmed by {{ p.cash.reviewedRole === 'superadmin' ? 'Renta UG' : 'the landlord' }}{{ p.cash.reviewedAt ? ` on ${formatDate(p.cash.reviewedAt)}` : '' }}</p>
            </div>
          </div>

          <!-- More than this month: what of it is this month's, then every month with the dates it covers -->
          <p v-if="p.months.length > 1" class="border-t border-slate-100 px-4 py-3 text-sm text-slate-600 sm:px-5">
            <span class="font-semibold text-slate-900">Paid {{ p.months.length }} months.</span>
            {{ formatUGX(p.here) }} of it is the rent of {{ formatPeriod(charge.period) }}, the rest paid the other months.
          </p>
          <ul class="divide-y divide-slate-100 border-t border-slate-100" data-months>
            <li v-for="m in p.months" :key="m.id" class="flex items-start justify-between gap-3 px-4 py-3 sm:px-5" :class="m.here && p.months.length > 1 && 'pd-here'">
              <div class="min-w-0">
                <p class="flex flex-wrap items-center gap-x-2 gap-y-1 font-medium text-slate-900">
                  {{ formatPeriod(m.period) }}
                  <span v-if="m.here && p.months.length > 1" class="pd-badge">This month</span>
                </p>
                <p v-if="m.window" class="mt-0.5 text-xs text-slate-500 tabular-nums">{{ range(m.window) }} · {{ durationText(m.window.days) }}</p>
              </div>
              <p class="shrink-0 text-sm font-semibold text-slate-900 tabular-nums">{{ formatUGX(m.amount) }}</p>
            </li>
          </ul>

          <!-- The rental time it bought -->
          <template v-if="p.from">
            <dl class="grid grid-cols-2 border-t border-slate-100 text-sm" data-time>
              <div class="px-4 py-3 sm:px-5"><dt class="flex items-center gap-1.5 text-xs text-slate-500"><CalendarRange class="size-3.5" /> Rental time starts</dt><dd class="mt-0.5 font-semibold text-slate-900">{{ formatDate(p.from) }}</dd></div>
              <div class="border-l border-slate-100 px-4 py-3 sm:px-5"><dt class="text-xs text-slate-500">Final date</dt><dd class="mt-0.5 font-semibold text-slate-900">{{ formatDate(p.to) }}</dd></div>
            </dl>
            <p class="border-t border-slate-100 px-4 py-2.5 text-xs text-slate-500 sm:px-5">
              <template v-if="p.debt">{{ daysWord(p.debt) }} of debt paid first, then {{ durationText(p.added) }} added: {{ durationText(p.days) }} in all.</template>
              <template v-else>{{ durationText(p.days) }} of rental time.</template>
            </p>
          </template>
          <p v-else-if="!tenant?.propertyId" class="border-t border-slate-100 px-4 py-2.5 text-xs text-slate-500 sm:px-5">{{ firstName }} has moved out: the dates of this rental time are no longer counted.</p>

          <dl v-if="p.reference || p.note" class="divide-y divide-slate-100 border-t border-slate-100 text-sm">
            <div v-if="p.reference" class="flex items-center gap-3 px-4 py-3 sm:px-5"><Hash class="size-4 text-slate-400" /><dt class="flex-1 text-slate-500">Reference</dt><dd class="font-mono text-xs font-medium text-slate-900">{{ p.reference }}</dd></div>
            <div v-if="p.note" class="flex items-start gap-3 px-4 py-3 sm:px-5"><StickyNote class="mt-0.5 size-4 text-slate-400" /><dt class="flex-1 text-slate-500">Note</dt><dd class="max-w-[60%] text-right text-slate-900">{{ p.note }}</dd></div>
          </dl>

          <!-- This payment's own buttons -->
          <div class="flex flex-wrap items-center gap-2 border-t border-slate-100 p-3 sm:px-5">
            <template v-if="!only">
              <button type="button" class="pd-mini" :disabled="Boolean(saving)" @click="savePayment(p)">
                <Loader2 v-if="saving === p.id" class="size-4 animate-spin" /><ImageDown v-else class="size-4" /> {{ saving === p.id ? 'Saving…' : 'Receipt' }}
              </button>
              <button v-if="canShare" type="button" class="pd-mini pd-mini-wa" @click="sharePayment(p)"><MessageCircle class="size-4" /> WhatsApp</button>
            </template>
            <!-- Reversing takes back the WHOLE payment: offered where the whole payment is shown -->
            <button v-if="!(p.whole && p.whole !== p.total)" type="button" class="rev-btn" :class="only && 'w-full'" @click="reverse(p)"><RotateCcw class="size-4" /> Reverse payment</button>
          </div>
        </div>
      </section>

      <!-- Nothing paid yet -->
      <div v-if="!payments.length" class="sheet mt-6 flex items-start gap-3.5 p-5">
        <span class="icon-disc" :class="charge.status === 'overdue' ? 'disc-red' : 'disc-amber'"><CircleAlert class="size-5" /></span>
        <div class="min-w-0">
          <p class="font-semibold text-slate-900">No payment yet</p>
          <p class="mt-0.5 text-sm text-slate-500">{{ firstName }} has not paid anything for {{ formatPeriod(charge.period) }}. Record it here when the money comes in.</p>
        </div>
      </div>

      <!-- The month in detail -->
      <section class="rise mt-6" style="--d: 120ms">
        <h2 class="section-title">This month</h2>
        <div class="sheet">
          <dl class="divide-y divide-slate-100 text-sm">
            <div class="flex justify-between gap-3 px-4 py-3 sm:px-5"><dt class="text-slate-500">Rent</dt><dd class="font-medium text-slate-900 tabular-nums">{{ formatUGX(charge.amount) }}</dd></div>
            <div class="flex justify-between gap-3 px-4 py-3 sm:px-5"><dt class="text-slate-500">Paid so far</dt><dd class="font-medium text-slate-900 tabular-nums">{{ formatUGX(charge.amountPaid) }}</dd></div>
            <div v-if="charge.balance" class="flex justify-between gap-3 px-4 py-3 sm:px-5"><dt class="text-slate-500">Still owed</dt><dd class="font-semibold tabular-nums" :class="charge.status === 'overdue' ? 'text-red-600' : 'text-amber-700'">{{ formatUGX(charge.balance) }}</dd></div>
            <div class="flex justify-between gap-3 px-4 py-3 sm:px-5"><dt class="text-slate-500">Due</dt><dd class="font-medium text-slate-900">{{ formatDate(charge.dueDate) }}</dd></div>
            <div v-if="charge.paidAt" class="flex justify-between gap-3 px-4 py-3 sm:px-5"><dt class="text-slate-500">Paid in full on</dt><dd class="font-medium text-slate-900">{{ formatDate(charge.paidAt) }}</dd></div>
          </dl>
          <div v-if="plan && plan.rows.length" class="border-t border-slate-100 px-4 py-4 sm:px-5">
            <div class="flex items-baseline justify-between gap-3 text-xs">
              <p class="font-semibold tracking-[0.12em] text-slate-400 uppercase">{{ plan.rows.length > 1 ? `Paid in ${plan.rows.length} payments` : 'Rental time of this month' }}</p>
              <p class="font-semibold text-brand-700">{{ plan.days }} of {{ RENT_MONTH_DAYS }} days</p>
            </div>
            <div class="mt-2 h-2 overflow-hidden rounded-full bg-slate-100">
              <span class="block h-full rounded-full bg-gradient-to-r from-teal-400 to-teal-700" :style="{ width: `${Math.min(100, Math.round((plan.paid / plan.rent) * 100))}%` }" />
            </div>
          </div>
        </div>
      </section>

      <div class="mt-6 grid gap-2.5" :class="charge.status !== 'paid' && tenant?.propertyId && 'sm:grid-cols-2'">
        <RouterLink :to="tenantLink" class="btn-secondary h-12 rounded-2xl">Open tenant</RouterLink>
        <button v-if="charge.status !== 'paid' && tenant?.propertyId" type="button" class="btn-primary h-12 rounded-2xl" @click="recordOpen = true">
          <HandCoins class="size-4" /> {{ charge.amountPaid ? 'Record the rest' : 'Record payment' }}
        </button>
      </div>
      <RecordPaymentModal v-if="tenant?.propertyId" :model-value="recordOpen" :tenant-id="charge.tenantId" :preset-amount="charge.amountPaid ? charge.balance : 0" @update:model-value="recordOpen = $event" />
    </template>

    <!-- The month is gone (its only payment was reversed), or the link is old -->
    <div v-else class="sheet">
      <EmptyState
        kind="money"
        :title="done ? 'The month went with the payment' : 'This payment is no longer here'"
        :text="done ? 'It was a month paid ahead by that payment only, so nothing is owed for it.' : 'It may have been reversed. Your payments list has everything there is now.'"
        to="/landlord/payments"
        action="Back to payments"
      />
    </div>
  </div>
</template>

<style scoped>
/* The month: its colour says paid / due / overdue. Dark mode: black, with that colour on the edge. */
.pd-hero { --color-white: #fff; color: #fff; }
.pd-paid { background: linear-gradient(135deg, #14918a, #0f766e 55%, #0a3b38); }
.pd-pending { background: linear-gradient(135deg, #f5b544, #d97706 55%, #92400e); }
.pd-overdue { background: linear-gradient(135deg, #e0564b, #b91c1c 55%, #6e1610); }
html.dark .pd-hero { background: #000000; }
html.dark .pd-paid { box-shadow: inset 0 0 0 1.5px rgb(45 212 191 / 0.5); }
html.dark .pd-pending { box-shadow: inset 0 0 0 1.5px rgb(251 191 36 / 0.5); }
html.dark .pd-overdue { box-shadow: inset 0 0 0 1.5px rgb(248 113 113 / 0.55); }
.pd-glass { background: rgb(255 255 255 / 0.14); box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.18); }
html.dark .pd-glass { background: rgb(255 255 255 / 0.08); }
.pd-chip { display: inline-flex; flex-shrink: 0; align-items: center; gap: 0.15rem; height: 2.1rem; border-radius: 9999px; padding: 0 0.75rem; font-size: 0.75rem; font-weight: 700; color: #0a3b38; background: #fff; }
.pd-focus { box-shadow: 0 0 0 2px var(--color-brand-500), 0 18px 40px -28px rgb(15 118 110 / 0.6); }
.pd-here { background: var(--color-brand-50); }
html.dark .pd-here { background: rgb(45 212 191 / 0.08); }
.pd-badge { border-radius: 9999px; padding: 0.1rem 0.5rem; font-size: 0.65rem; font-weight: 700; letter-spacing: 0.04em; text-transform: uppercase; color: var(--color-brand-700); background: var(--color-brand-100); }
/* WhatsApp: its own green */
.wa-btn { display: inline-flex; align-items: center; justify-content: center; gap: 0.5rem; font-weight: 600; color: #fff; background: linear-gradient(135deg, #25d366, #128c4a); box-shadow: 0 10px 22px -14px rgb(18 140 74 / 0.9); transition: transform 0.12s ease; }
.wa-btn:active { transform: scale(0.98); }
.pd-mini { display: inline-flex; height: 2.5rem; align-items: center; gap: 0.4rem; border-radius: 0.9rem; padding: 0 0.9rem; font-size: 0.8125rem; font-weight: 600; color: var(--color-brand-700); background: var(--color-brand-50); }
.pd-mini-wa { color: #128c4a; background: #e8f8ef; }
html.dark .pd-mini-wa { color: #4ade80; background: rgb(74 222 128 / 0.1); }
.pd-mini:active, .rev-btn:active { transform: scale(0.97); }
/* Reverse: red, never the main button */
.rev-btn { display: inline-flex; height: 2.75rem; align-items: center; justify-content: center; gap: 0.45rem; border-radius: 0.95rem; padding: 0 1rem; font-size: 0.875rem; font-weight: 600; color: #b91c1c; background: #fef2f2; box-shadow: inset 0 0 0 1px #fecaca; margin-left: auto; }
.rev-btn.w-full { margin-left: 0; }
html.dark .rev-btn { color: #fca5a5; background: #000000; box-shadow: inset 0 0 0 1px rgb(248 113 113 / 0.35); }
</style>
