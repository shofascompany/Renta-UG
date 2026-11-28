<script setup>
import { computed } from 'vue'
import { CalendarCheck2, CircleAlert, CircleCheck, Sparkles } from '@lucide/vue'
import { formatUGX, formatDate, formatPeriod } from '@/utils/format'
import { coverage, coverageParts, debtSplit, durationText, isoDay, RENT_MONTH_DAYS } from '@/utils/rentCycle'

// What a payment pays for: "USh 750,000 pays for 2 months and 15 days: rental time runs up to 8 Feb 2027". When it is
// more than one piece of time (unpaid months, whole months, part of a month), each piece is listed with its dates.
// Paid time that has run out (debt days) is paid first, and only the rest is added: "Your 9 debt days are paid first,
// so 21 days are added". The payment is still one payment of the amount paid.
// Same rules as the database (database/52 + 61 + 63): a rent month is 30 days, part of a month's rent buys part of it in days.
const props = defineProps({
  tenant: Object, // { leaseEnd, name }
  dues: { type: Array, default: () => [] }, // unpaid rent months, oldest first
  rent: { type: Number, default: 0 },
  amount: { type: Number, default: 0 },
  before: { type: Number, default: 0 }, // already sent, waiting for the landlord
  payDay: { type: String, default: () => isoDay(new Date()) },
  you: { type: Boolean, default: true }, // tenant's own view ("you") or the landlord's ("they")
})

const args = computed(() => ({ tenant: props.tenant, dues: props.dues, rent: props.rent, amount: props.amount, before: props.before, payDay: props.payDay }))
const c = computed(() => coverage(args.value))
const parts = computed(() => coverageParts(args.value))
const split = computed(() => debtSplit(c.value, props.tenant)) // debt days first, then what is added
// Money left on a month that isn't full after this payment
const short = computed(() => {
  let left = props.before + props.amount
  for (const d of props.dues) {
    const o = Math.max(0, d.amount - d.amountPaid)
    if (left < o) return o - left
    left -= o
  }
  const extra = left
  return props.rent > 0 && extra % props.rent ? props.rent - (extra % props.rent) : 0
})
const who = computed(() => (props.you ? 'you' : 'they'))
const whose = computed(() => (props.you ? 'Your' : 'Their'))
const plural = (n, word) => `${n} ${word}${n === 1 ? '' : 's'}`
// "1 month is added", "21 days are added"
const isAre = (days) => (days === 1 || days === RENT_MONTH_DAYS ? 'is' : 'are')

// The big number: the time added (months, with the days over, or days). All of it to debt days: the debt days paid.
const big = computed(() => {
  const s = split.value
  if (s.debtPaid && !s.added) return { n: s.debtPaid, unit: s.debtPaid === 1 ? 'debt day' : 'debt days', plus: 'paid' }
  const m = Math.floor(s.added / RENT_MONTH_DAYS)
  const d = s.added % RENT_MONTH_DAYS
  const time = m
    ? { n: m, unit: m === 1 ? 'month' : 'months', plus: d ? `+${d} day${d === 1 ? '' : 's'}` : '' }
    : { n: d, unit: d === 1 ? 'day' : 'days', plus: '' }
  return s.debtPaid ? { ...time, plus: [time.plus, 'added'].filter(Boolean).join(' ') } : time
})
const dayMonth = (d) => new Date(d).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })
const range = (p) => (p.from.slice(0, 4) === p.to.slice(0, 4) ? `${dayMonth(p.from)} – ${formatDate(p.to)}` : `${formatDate(p.from)} – ${formatDate(p.to)}`)
// What each piece of time is
function note(p) {
  if (p.kind === 'due') return `${p.whole ? 'Unpaid rent' : 'Part of the unpaid rent'} of ${formatPeriod(p.period)}`
  if (p.kind === 'part') return p.cut ? 'Part of a month' : `Part of a month: ${formatUGX(p.paid)} of ${formatUGX(p.of)}`
  if (p.cut) return 'Completes a month paid in part before'
  return p.passed ? 'Time that was unpaid' : ''
}
</script>

<template>
  <div v-if="amount > 0" class="cov overflow-hidden rounded-2xl">
    <div class="flex items-center gap-4 p-4">
      <span class="cov-days flex min-h-16 w-16 shrink-0 flex-col items-center justify-center rounded-2xl px-1 py-2 text-center">
        <span class="text-2xl leading-none font-extrabold tabular-nums">{{ big.n }}</span>
        <span class="mt-0.5 text-[10px] font-bold tracking-wide uppercase">{{ big.unit }}</span>
        <span v-if="big.plus" class="mt-0.5 text-[10px] leading-tight font-semibold opacity-90">{{ big.plus }}</span>
      </span>
      <div class="min-w-0 flex-1">
        <p class="text-xs font-semibold tracking-[0.12em] text-brand-700 uppercase">This payment covers</p>
        <p class="mt-0.5 text-[15px] leading-snug text-slate-700">
          <strong class="text-slate-900 tabular-nums">{{ formatUGX(amount) }}</strong> pays for
          <strong class="text-slate-900">{{ durationText(c.days) }}</strong><template v-if="!split.debtPaid">:
            {{ whose.toLowerCase() }} rental time runs up to <strong class="text-slate-900">{{ formatDate(c.end) }}</strong>.</template>
          <template v-else-if="split.added">.
            {{ whose }} {{ plural(split.debtPaid, 'debt day') }} {{ split.debtPaid === 1 ? 'is' : 'are' }} paid first, so
            <strong class="text-slate-900">{{ durationText(split.added) }}</strong> {{ isAre(split.added) }} added:
            {{ whose.toLowerCase() }} rental time runs up to <strong class="text-slate-900">{{ formatDate(c.end) }}</strong>.</template>
          <template v-else-if="split.behind">. All of it pays debt days: {{ who }} are still <strong class="text-slate-900">{{ plural(split.behind, 'day') }}</strong> behind.</template>
          <template v-else>. All of it pays {{ whose.toLowerCase() }} debt days: {{ whose.toLowerCase() }} rental time runs up to <strong class="text-slate-900">{{ formatDate(c.end) }}</strong>.</template>
        </p>
        <p class="mt-1 text-[11px] text-slate-500">{{ c.firstPayment ? 'Starts' : 'From' }} {{ formatDate(c.from) }} · up to {{ formatDate(c.end) }}</p>
      </div>
    </div>

    <!-- More than one piece of time: each one with its dates and its days -->
    <ul v-if="parts.length > 1" class="cov-rows">
      <li v-for="(p, i) in parts" :key="i" class="flex items-start justify-between gap-3 px-4 py-2.5 text-xs">
        <span class="min-w-0">
          <span class="block font-semibold text-slate-800 tabular-nums">{{ range(p) }}</span>
          <span v-if="note(p)" class="mt-0.5 block text-slate-500">{{ note(p) }}</span>
        </span>
        <span class="shrink-0 text-right font-bold text-slate-900 tabular-nums">{{ durationText(p.days) }}</span>
      </li>
    </ul>

    <!-- Debt days: paid first, the rest added -->
    <p v-if="split.debtPaid" class="cov-note cov-paid flex items-start gap-2 px-4 py-2.5 text-xs" data-debt>
      <CircleCheck class="mt-px size-4 shrink-0" />
      <span>
        <strong class="font-semibold">{{ plural(split.debtPaid, 'debt day') }} paid</strong> ({{ range(split) }}).
        <template v-if="split.added">The remaining {{ durationText(split.added) }} {{ isAre(split.added) }} added to {{ whose.toLowerCase() }} rental time.</template>
      </span>
    </p>
    <p v-if="split.behind" class="cov-note cov-warn flex items-start gap-2 px-4 py-2.5 text-xs">
      <CircleAlert class="mt-px size-4 shrink-0" />
      <span>{{ who === 'you' ? 'You are' : 'They are' }} still {{ plural(split.behind, 'debt day') }} behind after this payment.</span>
    </p>
    <p v-if="short" class="cov-note flex items-start gap-2 px-4 py-2.5 text-xs">
      <Sparkles class="mt-px size-4 shrink-0 text-brand-600" />
      <span>This is a part payment. {{ formatUGX(short) }} more completes the month, and {{ who }} can top it up any time.</span>
    </p>
    <p v-else-if="before" class="cov-note flex items-start gap-2 px-4 py-2.5 text-xs">
      <CalendarCheck2 class="mt-px size-4 shrink-0 text-brand-600" />
      <span>Counted after {{ formatUGX(before) }} already waiting for confirmation.</span>
    </p>
  </div>
</template>

<style scoped>
.cov { background: var(--color-brand-50); box-shadow: inset 0 0 0 1.5px var(--color-brand-200); }
html.dark .cov { background: #000000; }
.cov-days { --color-white: #fff; color: #fff; background: linear-gradient(140deg, #2dd4bf, #0f766e 60%, #0a3b38); box-shadow: 0 10px 22px -12px rgb(15 118 110 / 0.8); }
.cov-rows { border-top: 1px solid var(--color-brand-200); }
.cov-rows > li + li { border-top: 1px solid var(--color-brand-100); }
.cov-note { color: var(--color-slate-600); border-top: 1px solid var(--color-brand-200); }
.cov-paid { color: var(--color-emerald-800); background: var(--color-emerald-50); }
.cov-warn { color: var(--color-red-700); background: var(--color-red-50); }
</style>
