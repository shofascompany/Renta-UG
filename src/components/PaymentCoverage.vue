<script setup>
import { computed } from 'vue'
import { CalendarCheck2, CircleAlert, Sparkles } from '@lucide/vue'
import { formatUGX, formatDate } from '@/utils/format'
import { coverage, isoDay } from '@/utils/rentCycle'

// How long a payment lasts: "UGX 150,000 covers 15 days · up to 12 Jun 2026".
// Same rule as the database (database/52): part of a month's rent buys part of the month in days.
const props = defineProps({
  tenant: Object, // { leaseEnd, name }
  dues: { type: Array, default: () => [] }, // unpaid rent months, oldest first
  rent: { type: Number, default: 0 },
  amount: { type: Number, default: 0 },
  before: { type: Number, default: 0 }, // already sent, waiting for the landlord
  payDay: { type: String, default: () => isoDay(new Date()) },
  you: { type: Boolean, default: true }, // tenant's own view ("you") or the landlord's ("they")
})

const c = computed(() => coverage({ tenant: props.tenant, dues: props.dues, rent: props.rent, amount: props.amount, before: props.before, payDay: props.payDay }))
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
const pct = computed(() => Math.min(100, Math.round((c.value.days / 31) * 100)))
</script>

<template>
  <div v-if="amount > 0" class="cov overflow-hidden rounded-2xl">
    <div class="flex items-center gap-4 p-4">
      <span class="cov-days flex size-16 shrink-0 flex-col items-center justify-center rounded-2xl">
        <span class="text-2xl leading-none font-extrabold tabular-nums">{{ c.days }}</span>
        <span class="mt-0.5 text-[10px] font-bold tracking-wide uppercase">day{{ c.days === 1 ? '' : 's' }}</span>
      </span>
      <div class="min-w-0 flex-1">
        <p class="text-xs font-semibold tracking-[0.12em] text-brand-700 uppercase">This payment covers</p>
        <p class="mt-0.5 text-[15px] leading-snug text-slate-700">
          <strong class="text-slate-900 tabular-nums">{{ formatUGX(amount) }}</strong> lasts
          <strong class="text-slate-900">{{ c.days }} day{{ c.days === 1 ? '' : 's' }}</strong>:
          {{ whose.toLowerCase() }} rental time runs up to <strong class="text-slate-900">{{ formatDate(c.end) }}</strong>.
        </p>
      </div>
    </div>
    <div class="px-4 pb-4">
      <div class="cov-bar h-2 overflow-hidden rounded-full"><span class="block h-full rounded-full" :style="{ width: `${Math.max(4, pct)}%` }" /></div>
      <div class="mt-1.5 flex justify-between text-[11px] text-slate-500">
        <span>{{ c.firstPayment ? 'Starts' : 'From' }} {{ formatDate(c.from) }}</span>
        <span>Up to {{ formatDate(c.end) }}</span>
      </div>
    </div>

    <p v-if="c.debtDays && c.endsBeforeToday" class="cov-note cov-warn flex items-start gap-2 px-4 py-2.5 text-xs">
      <CircleAlert class="mt-px size-4 shrink-0" />
      <span>{{ whose }} time ended {{ c.debtDays }} day{{ c.debtDays === 1 ? '' : 's' }} ago. After this payment {{ who }} are still {{ -c.daysFromToday }} day{{ -c.daysFromToday === 1 ? '' : 's' }} behind.</span>
    </p>
    <p v-else-if="c.debtDays" class="cov-note flex items-start gap-2 px-4 py-2.5 text-xs">
      <CircleAlert class="mt-px size-4 shrink-0 text-amber-600" />
      <span>{{ c.debtDays }} debt day{{ c.debtDays === 1 ? '' : 's' }} (since {{ formatDate(tenant.leaseEnd) }}) are part of these days.</span>
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
.cov-days { --color-white: #fff; color: #fff; background: linear-gradient(140deg, #2dd4bf, #0f766e 60%, #0a3b38); box-shadow: 0 10px 22px -12px rgb(15 118 110 / 0.8); }
.cov-bar { background: rgb(15 118 110 / 0.12); }
.cov-bar span { background: linear-gradient(90deg, #2dd4bf, #0f766e); transition: width 0.4s cubic-bezier(0.22, 1, 0.36, 1); }
.cov-note { color: var(--color-slate-600); border-top: 1px solid var(--color-brand-200); }
.cov-warn { color: var(--color-red-700); background: var(--color-red-50); }
</style>
