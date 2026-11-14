<script setup>
import { computed, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { Zap, CalendarCheck2, ChevronLeft, ShieldCheck, Smartphone, Clock, Sparkles } from '@lucide/vue'
import { api } from '@/lib/api'
import { useTenant } from '@/composables/useTenant'
import { formatUGX, formatDate } from '@/utils/format'
import PayRentForm from '@/components/PayRentForm.vue'

// Recharge: pay rent in advance in ONE mobile money payment. Nothing is chosen for the tenant:
// they pick how many months, then the number that pays. Unpaid rent is always cleared first.
// The server works out the exact amount; the "paid up to" date follows the rental-time rules
// (each paid month adds one month on top of the time they already have, or from today if none).
const router = useRouter()
const { rental, tenant, property, dues, balance } = useTenant()

const OPTIONS = [
  { m: 1, tag: '' },
  { m: 2, tag: '' },
  { m: 3, tag: 'Popular' },
  { m: 6, tag: '' },
  { m: 12, tag: 'Full year' },
]
const months = ref(null)
const quote = ref(null)
const loading = ref(false)
const error = ref('')
let seq = 0

const rent = computed(() => quote.value?.rent ?? property.value?.rent ?? 0)
const owed = computed(() => quote.value?.outstanding ?? balance.value ?? 0)
const priceFor = (m) => owed.value + rent.value * m

async function loadQuote() {
  if (!months.value) return
  const mine = ++seq
  loading.value = true
  error.value = ''
  try {
    const q = await api('/api/momo/recharge-quote', { months: months.value })
    if (mine === seq) quote.value = q
  } catch (e) {
    if (mine === seq) error.value = e.message
  } finally {
    if (mine === seq) loading.value = false
  }
}
watch(months, loadQuote)

// Rental time after paying: unpaid months + the new months, added on top of the current end (or today)
const addMonths = (d, n) => {
  const x = new Date(d)
  const day = x.getDate()
  x.setDate(1)
  x.setMonth(x.getMonth() + n)
  x.setDate(Math.min(day, new Date(x.getFullYear(), x.getMonth() + 1, 0).getDate()))
  return x
}
const startFrom = computed(() => {
  const end = tenant.value?.leaseEnd ? new Date(`${tenant.value.leaseEnd}T00:00:00`) : null
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  return end && end > today ? end : today
})
const paidUntil = computed(() => (months.value ? addMonths(startFrom.value, months.value + dues.value.length) : null))
const currentEnd = computed(() => tenant.value?.leaseEnd)
const total = computed(() => (months.value ? (quote.value && !loading.value ? quote.value.total : priceFor(months.value)) : 0))

async function onPaid() {
  await Promise.all([rental.reload('payments'), rental.reload('notifications'), rental.reload('tenants')])
  router.push('/tenant/payments')
}
</script>

<template>
  <div class="mx-auto max-w-xl">
    <!-- Hero -->
    <header class="hero rise relative overflow-hidden rounded-3xl p-6 text-white sm:p-7">
      <div class="grid-pattern" aria-hidden="true" />
      <div class="glow" aria-hidden="true" />
      <div class="relative">
        <button type="button" class="back mb-4 inline-flex h-9 items-center gap-1 rounded-full pr-3.5 pl-2 text-sm font-medium" @click="router.back()">
          <ChevronLeft class="size-4" /> Back
        </button>
        <p class="flex items-center gap-2 text-xs font-semibold tracking-[0.14em] text-white/75 uppercase"><Zap class="size-3.5" /> Recharge</p>
        <h1 class="mt-2 text-[1.7rem] leading-tight font-bold tracking-tight">Pay ahead, stay worry-free</h1>
        <p class="mt-1.5 text-sm text-white/80">{{ property?.name }} · {{ formatUGX(rent) }} / month</p>

        <div class="mt-5 grid grid-cols-2 overflow-hidden rounded-2xl bg-white/10 ring-1 ring-white/15">
          <div class="p-3.5">
            <p class="text-[11px] font-medium tracking-wide text-white/65 uppercase">Paid up to</p>
            <p class="mt-1 text-base font-semibold">{{ currentEnd ? formatDate(currentEnd) : 'Not started' }}</p>
          </div>
          <div class="border-l border-white/15 p-3.5">
            <p class="text-[11px] font-medium tracking-wide text-white/65 uppercase">Unpaid now</p>
            <p class="mt-1 text-base font-semibold tabular-nums">{{ owed ? formatUGX(owed) : 'Nothing' }}</p>
          </div>
        </div>
      </div>
    </header>

    <!-- 1. Months -->
    <section class="rise mt-6" style="--d: 60ms">
      <h2 class="section-title">1 · How many months?</h2>
      <div class="grid grid-cols-3 gap-2.5 sm:grid-cols-5">
        <button
          v-for="o in OPTIONS"
          :key="o.m"
          type="button"
          class="opt relative flex flex-col items-center justify-center rounded-2xl border px-2 pt-4 pb-3 transition"
          :class="months === o.m ? 'opt-on border-transparent text-white' : 'border-slate-200 bg-white text-slate-800 hover:border-brand-300'"
          :aria-pressed="months === o.m"
          @click="months = o.m"
        >
          <span v-if="o.tag" class="absolute -top-2 rounded-full px-2 py-0.5 text-[10px] font-bold" :class="months === o.m ? 'bg-white text-brand-700' : 'bg-brand-600 text-white'">{{ o.tag }}</span>
          <span class="text-2xl leading-none font-bold">{{ o.m }}</span>
          <span class="mt-1 text-[11px] font-medium" :class="months === o.m ? 'text-white/80' : 'text-slate-500'">{{ o.m === 1 ? 'month' : 'months' }}</span>
          <span class="mt-2 text-[11px] font-semibold tabular-nums" :class="months === o.m ? 'text-white' : 'text-slate-700'">{{ formatUGX(rent * o.m) }}</span>
        </button>
      </div>
      <p v-if="!months" class="mt-3 flex items-center gap-2 px-1 text-sm text-slate-500"><Sparkles class="size-4 text-brand-500" /> Choose how many months you want to pay.</p>
    </section>

    <!-- Summary -->
    <Transition enter-active-class="transition duration-300" enter-from-class="opacity-0 translate-y-2">
      <section v-if="months" class="rise mt-6">
        <h2 class="section-title">Summary</h2>
        <div class="sheet p-5">
          <dl class="space-y-3 text-sm">
            <div v-if="owed" class="flex justify-between gap-4">
              <dt class="flex items-center gap-2 text-slate-500"><Clock class="size-4 text-amber-500" /> Unpaid rent (cleared first)</dt>
              <dd class="font-semibold text-slate-900 tabular-nums">{{ formatUGX(owed) }}</dd>
            </div>
            <div class="flex justify-between gap-4">
              <dt class="flex items-center gap-2 text-slate-500"><Zap class="size-4 text-brand-600" /> {{ months }} × {{ formatUGX(rent) }}</dt>
              <dd class="font-semibold text-slate-900 tabular-nums">{{ formatUGX(rent * months) }}</dd>
            </div>
            <div class="flex items-end justify-between gap-4 border-t border-slate-100 pt-4">
              <dt class="font-semibold text-slate-900">Total</dt>
              <dd class="text-[1.75rem] leading-none font-bold tracking-tight text-slate-900 tabular-nums" :class="loading && 'opacity-50'">{{ formatUGX(total) }}</dd>
            </div>
          </dl>
          <p v-if="paidUntil" class="mt-4 flex items-start gap-2.5 rounded-2xl bg-emerald-50 px-4 py-3 text-sm text-emerald-800">
            <CalendarCheck2 class="mt-0.5 size-4.5 shrink-0" />
            <span>Your rental time will run up to <strong class="font-semibold">{{ formatDate(paidUntil) }}</strong>.</span>
          </p>
          <p v-if="error" class="mt-4 rounded-xl bg-red-50 p-3 text-sm text-red-700">{{ error }}</p>
        </div>
      </section>
    </Transition>

    <!-- 2. Pay -->
    <section v-if="months && quote && !error" class="rise mt-6">
      <h2 class="section-title">2 · Pay with mobile money</h2>
      <div class="sheet p-5">
        <PayRentForm :key="months" :recharge="{ months, total: loading ? 0 : quote.total }" @paid="onPaid" @cancel="router.push('/tenant')" />
      </div>
    </section>

    <!-- Trust -->
    <ul class="mt-6 grid gap-2.5 text-sm text-slate-600 sm:grid-cols-3">
      <li class="flex items-center gap-2.5 rounded-2xl bg-white/70 px-3.5 py-3 ring-1 ring-slate-200/70"><Smartphone class="size-4.5 shrink-0 text-brand-600" /> MTN &amp; Airtel</li>
      <li class="flex items-center gap-2.5 rounded-2xl bg-white/70 px-3.5 py-3 ring-1 ring-slate-200/70"><ShieldCheck class="size-4.5 shrink-0 text-brand-600" /> Verified automatically</li>
      <li class="flex items-center gap-2.5 rounded-2xl bg-white/70 px-3.5 py-3 ring-1 ring-slate-200/70"><CalendarCheck2 class="size-4.5 shrink-0 text-brand-600" /> Time added on top</li>
    </ul>
  </div>
</template>

<style scoped>
.hero {
  --color-white: #fff;
  background: linear-gradient(135deg, #14918a 0%, #0f766e 45%, #0a3b38 100%);
  box-shadow: 0 20px 45px -22px rgb(10 59 56 / 0.6);
}
.grid-pattern {
  position: absolute;
  inset: 0;
  background-image:
    linear-gradient(rgb(255 255 255 / 0.06) 1px, transparent 1px),
    linear-gradient(90deg, rgb(255 255 255 / 0.06) 1px, transparent 1px);
  background-size: 28px 28px;
  mask-image: linear-gradient(180deg, #000, transparent 80%);
}
.glow {
  position: absolute;
  top: -45%;
  right: -20%;
  width: 20rem;
  height: 20rem;
  border-radius: 9999px;
  background: radial-gradient(circle, rgb(255 255 255 / 0.2), transparent 65%);
}
.back { background: rgb(255 255 255 / 0.14); box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.2); }
.back:active { transform: scale(0.96); }
.opt:active { transform: scale(0.97); }
.opt-on {
  --color-white: #fff;
  background: linear-gradient(140deg, #14b8a6, #0f766e 60%, #0a3b38);
  box-shadow: 0 10px 22px -12px rgb(15 118 110 / 0.9);
}
.rise {
  animation: rise 0.5s cubic-bezier(0.22, 1, 0.36, 1) backwards;
  animation-delay: var(--d, 0ms);
}
@keyframes rise { from { opacity: 0; transform: translateY(10px); } }
@media (prefers-reduced-motion: reduce) {
  .rise { animation: none; }
}
</style>
