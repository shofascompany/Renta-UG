<script setup>
import { computed, ref } from 'vue'
import {
  Wallet, CalendarClock, MapPin, ArrowUpRight, Receipt, AlertCircle, Phone, Mail, MessageCircle, Zap, ShieldCheck,
  Clock, Banknote, ArrowDownLeft, Smartphone,
} from '@lucide/vue'
import ListRow from '@/components/admin/ListRow.vue'
import { useTenant } from '@/composables/useTenant'
import { formatUGX, formatDate, formatPeriod, daysUntil, timeLeft } from '@/utils/format'
import BaseModal from '@/components/BaseModal.vue'
import PayRentForm from '@/components/PayRentForm.vue'
import PushPrompt from '@/components/PushPrompt.vue'

// Only what a tenant needs at a glance: what they owe, their lease, their home.
// Everything else has its own page (My home, Payments, Notifications via the bell).
const { rental, tenant, property, payments, dues, balance } = useTenant()

const firstName = computed(() => tenant.value?.name.split(' ')[0] ?? '')
const nextDue = computed(() => dues.value[0])
const overdue = computed(() => dues.value.some((d) => d.status === 'overdue'))
const lastPayment = computed(() =>
  payments.value.filter((p) => p.paidAt).sort((a, b) => String(b.paidAt).localeCompare(String(a.paidAt)))[0],
)
const totalPaid = computed(() => payments.value.reduce((s, p) => s + p.amountPaid, 0))

// Rows: latest paid months and cash vs mobile money
const isCash = (p) => /cash/i.test(p.method ?? '')
const recentPaid = computed(() =>
  payments.value.filter((p) => p.paidAt && p.amountPaid).sort((a, b) => String(b.paidAt).localeCompare(String(a.paidAt))).slice(0, 4),
)
const payWays = computed(() => {
  const ways = { 'Mobile money': { label: 'Mobile money', count: 0, total: 0 }, Cash: { label: 'Cash', count: 0, total: 0 } }
  for (const p of payments.value) {
    if (!p.paidAt || !p.amountPaid) continue
    const w = ways[isCash(p) ? 'Cash' : 'Mobile money']
    w.count += 1
    w.total += p.amountPaid
  }
  return Object.values(ways).filter((w) => w.count).sort((a, b) => b.total - a.total)
})

const daysLeft = computed(() => (tenant.value?.leaseEnd ? daysUntil(tenant.value.leaseEnd) : null))
// New tenant who hasn't paid yet: their rental time has not started, so no days are counted
const notStarted = computed(() => !tenant.value?.leaseEnd && !payments.value.some((p) => p.status === 'paid'))
const timeEnded = computed(() => daysLeft.value !== null && daysLeft.value < 0)
const endingSoon = computed(() => daysLeft.value !== null && daysLeft.value >= 0 && daysLeft.value <= 7)
const leaseProgress = computed(() => {
  const t = tenant.value
  if (!t?.leaseStart || !t?.leaseEnd) return 0
  const start = new Date(t.leaseStart).getTime()
  const end = new Date(t.leaseEnd).getTime()
  return Math.min(100, Math.max(0, ((Date.now() - start) / (end - start)) * 100))
})

// ── Rent coverage: which months are paid, when each ends, and when it was recharged ──
const pad = (n) => String(n).padStart(2, '0')
const now = new Date()
const thisPeriod = `${now.getFullYear()}-${pad(now.getMonth() + 1)}`
const monthBounds = (period) => {
  const [y, m] = period.split('-').map(Number)
  return { start: new Date(y, m - 1, 1), end: new Date(y, m, 0) } // day 0 of next month = last day
}
const shortDate = (d) => d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })
const longDate = (d) => d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })
const paidOn = (iso) =>
  new Date(iso).toLocaleString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', hour: 'numeric', minute: '2-digit', hour12: true })

// This month: day X of N, days remaining, paid or not
const current = computed(() => {
  const { start, end } = monthBounds(thisPeriod)
  const total = end.getDate()
  const day = now.getDate()
  const charge = payments.value.find((p) => p.period === thisPeriod)
  return {
    name: start.toLocaleDateString('en-GB', { month: 'long' }),
    end,
    day,
    total,
    left: total - day, // full days after today
    progress: Math.round((day / total) * 100),
    paid: charge?.status === 'paid',
    charge,
  }
})

// Paid months from this month onwards (or the last paid month if none are ahead)
const coverage = computed(() => {
  const paid = payments.value.filter((p) => p.status === 'paid').sort((a, b) => a.period.localeCompare(b.period))
  const ahead = paid.filter((p) => p.period >= thisPeriod)
  const list = ahead.length ? ahead : paid.slice(-1)
  return list.map((p, i) => {
    const { start, end } = monthBounds(p.period)
    const state = p.period === thisPeriod ? 'current' : p.period > thisPeriod ? 'upcoming' : 'ended'
    return {
      ...p,
      index: i + 1,
      name: start.toLocaleDateString('en-GB', { month: 'long', year: 'numeric' }),
      range: `${shortDate(start)} – ${longDate(end)}`,
      endsIn: Math.max(0, Math.ceil((end.setHours(23, 59, 59, 999) - Date.now()) / 86400000)),
      state,
      paidOnText: p.paidAt ? paidOn(p.paidAt) : null,
    }
  })
})
// "Paid" badge: inside paid rental time (or this month paid, for older records without a rental time)
const covered = computed(() => (tenant.value?.leaseEnd ? daysLeft.value >= 0 : current.value.paid))
const paidUntil = computed(() => {
  const last = coverage.value.at(-1)
  return last && last.state !== 'ended' ? monthBounds(last.period).end : null
})

// ── Landlord contact ──
const owner = computed(() => rental.owner)
const ownerInitials = computed(() =>
  (owner.value?.full_name ?? '?').split(' ').map((p) => p[0]).slice(0, 2).join('').toUpperCase(),
)
// WhatsApp needs the international number: 0772… → 256772…
const whatsapp = computed(() => {
  const d = String(owner.value?.phone ?? '').replace(/\D/g, '')
  if (d.length < 9) return null
  const intl = d.startsWith('0') ? `256${d.slice(1)}` : d.length === 9 ? `256${d}` : d
  return `https://wa.me/${intl}`
})

const paying = ref(null)
async function onPaid() {
  paying.value = null
  await Promise.all([rental.reload('payments'), rental.reload('notifications')])
}

const greeting = (() => {
  const h = new Date().getHours()
  return h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening'
})()
const today = new Date().toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long' })
</script>

<template>
  <div class="mx-auto max-w-3xl">
    <!-- Greeting -->
    <header class="rise mb-7" style="--d: 0ms">
      <p class="text-xs font-semibold tracking-[0.14em] text-slate-400 uppercase">{{ today }}</p>
      <h1 class="mt-2 text-[1.75rem] leading-tight font-bold tracking-tight text-slate-900 sm:text-4xl">
        {{ greeting }},<br class="sm:hidden" />
        <span class="name-gradient">{{ firstName }}</span>
      </h1>
      <div v-if="property" class="mt-3 flex flex-wrap items-center gap-2 text-sm text-slate-500">
        <span
          class="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium ring-1 ring-inset"
          :class="notStarted ? 'bg-amber-50 text-amber-700 ring-amber-600/20' : timeEnded ? 'bg-slate-50 text-slate-600 ring-slate-500/15' : 'bg-emerald-50 text-emerald-700 ring-emerald-600/15'"
        >
          <span class="size-1.5 rounded-full" :class="notStarted ? 'bg-amber-500' : timeEnded ? 'bg-slate-400' : 'live-dot bg-emerald-500'" />
          {{ notStarted ? 'Waiting for your first payment' : timeEnded ? 'Rental time ended' : 'Renting now' }}
        </span>
        <span class="truncate">{{ property.name }} · {{ property.location }}</span>
      </div>
    </header>

    <PushPrompt class="mb-5" />

    <!-- Balance -->
    <section
      class="rise hero relative overflow-hidden rounded-3xl p-6 text-white shadow-lg sm:p-8"
      :class="overdue ? 'hero-overdue' : 'hero-ok'"
      style="--d: 60ms"
    >
      <div class="grid-pattern" aria-hidden="true" />
      <div class="blob" aria-hidden="true" />
      <div class="blob blob-2" aria-hidden="true" />

      <div class="relative">
        <!-- Title row -->
        <div class="flex items-center justify-between gap-3">
          <p class="flex items-center gap-2.5 text-sm font-medium text-white/85">
            <span class="flex size-8 items-center justify-center rounded-lg bg-white/15 ring-1 ring-white/20">
              <Wallet class="size-4" />
            </span>
            Rent account
          </p>
          <span class="chip">
            <AlertCircle v-if="overdue" class="size-3.5" />
            <span v-else class="size-1.5 rounded-full" :class="nextDue || notStarted ? 'bg-amber-300' : 'bg-emerald-300'" />
            {{ overdue ? 'Overdue' : nextDue ? `Due ${formatDate(nextDue.dueDate)}` : notStarted ? 'Not paid yet' : 'Up to date' }}
          </span>
        </div>

        <!-- Amount paid → Balance due -->
        <div class="mt-6 grid grid-cols-2 overflow-hidden rounded-2xl bg-white/10 ring-1 ring-white/15 backdrop-blur-sm">
          <div class="p-4 sm:p-5">
            <p class="text-xs font-medium tracking-wide text-white/70 uppercase">Amount paid</p>
            <p class="mt-1.5 text-xl font-semibold tracking-tight tabular-nums sm:text-3xl">{{ formatUGX(totalPaid) }}</p>
            <p class="mt-1 truncate text-xs text-white/60">
              {{ lastPayment ? `Last on ${formatDate(lastPayment.paidAt)}` : 'No payments yet' }}
            </p>
          </div>
          <div class="border-l border-white/15 p-4 sm:p-5">
            <p class="text-xs font-medium tracking-wide text-white/70 uppercase">Balance due</p>
            <p class="mt-1.5 text-xl font-semibold tracking-tight tabular-nums sm:text-3xl" :class="balance && overdue && 'text-red-100'">
              {{ formatUGX(balance) }}
            </p>
            <p class="mt-1 truncate text-xs text-white/60">
              <template v-if="nextDue">
                {{ formatPeriod(nextDue.period) }}<template v-if="dues.length > 1"> +{{ dues.length - 1 }}</template>
              </template>
              <template v-else>{{ formatUGX(property?.rent) }} / month</template>
            </p>
          </div>
        </div>

        <!-- Actions -->
        <div class="mt-6 grid gap-2.5" :class="nextDue ? 'grid-cols-2 sm:grid-cols-3' : 'grid-cols-2'">
          <button v-if="nextDue" class="hero-btn hero-btn-solid col-span-2 sm:col-span-1" @click="paying = nextDue">
            Pay now
          </button>
          <RouterLink to="/tenant/recharge" class="hero-btn" :class="nextDue ? 'hero-btn-glass' : 'hero-btn-solid'">
            <Zap class="size-4" /> {{ notStarted ? 'Pay first rent' : 'Recharge' }}
          </RouterLink>
          <RouterLink to="/tenant/payments" class="hero-btn hero-btn-glass">
            <Receipt class="size-4" /> History
          </RouterLink>
        </div>
      </div>
    </section>

    <!-- Rental time + home -->
    <div class="mt-4 grid gap-4 sm:grid-cols-2">
      <RouterLink
        to="/tenant/home"
        class="rise tile group relative overflow-hidden rounded-2xl border p-5"
        :class="endingSoon ? 'tile-warn border-amber-200' : 'tile-sky border-slate-200'"
        style="--d: 120ms"
      >
        <div class="flex items-center justify-between">
          <span
            class="flex size-10 items-center justify-center rounded-xl"
            :class="endingSoon ? 'bg-amber-100 text-amber-700' : 'bg-sky-50 text-sky-700'"
          >
            <CalendarClock class="size-5" />
          </span>
          <ArrowUpRight class="size-5 text-slate-300 transition group-hover:-translate-y-0.5 group-hover:translate-x-0.5 group-hover:text-slate-500" />
        </div>
        <p class="mt-4 text-sm text-slate-500">Rental time</p>
        <p class="mt-0.5 text-2xl font-semibold tracking-tight" :class="endingSoon ? 'text-amber-700' : 'text-slate-900'">
          <template v-if="daysLeft === null">Not started</template>
          <template v-else-if="daysLeft < 0">Ended</template>
          <template v-else>{{ timeLeft(daysLeft) }}</template>
        </p>
        <template v-if="tenant?.leaseEnd">
          <div class="mt-4 h-1.5 overflow-hidden rounded-full bg-slate-200/70">
            <div
              class="bar h-full rounded-full"
              :class="endingSoon ? 'bg-amber-500' : 'bg-sky-600'"
              :style="{ '--w': `${leaseProgress}%` }"
            />
          </div>
          <p class="mt-2 text-xs text-slate-500">{{ timeEnded ? 'Ended' : 'Ends' }} {{ formatDate(tenant.leaseEnd) }}</p>
        </template>
        <p v-else class="mt-3 text-xs leading-relaxed text-slate-500">You haven't paid yet. Your days start counting from the day you pay.</p>
      </RouterLink>

      <RouterLink
        v-if="property"
        to="/tenant/home"
        class="rise tile tile-brand group relative overflow-hidden rounded-2xl border border-slate-200 p-5"
        style="--d: 180ms"
      >
        <div class="flex items-center justify-between">
          <span class="flex size-10 items-center justify-center rounded-xl bg-brand-50 text-brand-700">
            <MapPin class="size-5" />
          </span>
          <ArrowUpRight class="size-5 text-slate-300 transition group-hover:-translate-y-0.5 group-hover:translate-x-0.5 group-hover:text-slate-500" />
        </div>
        <p class="mt-4 text-sm text-slate-500">My home</p>
        <p class="mt-0.5 truncate text-2xl font-semibold tracking-tight text-slate-900">{{ property.name }}</p>
        <p class="mt-1 truncate text-sm text-slate-500">{{ property.location }}</p>
        <p class="mt-3 text-xs text-slate-500">
          {{ property.bedrooms }} bed · {{ property.bathrooms }} bath · <span class="capitalize">{{ property.type }}</span>
        </p>
      </RouterLink>
    </div>

    <!-- Rent coverage -->
    <section class="rise coverage mt-4 overflow-hidden rounded-2xl border border-slate-200" style="--d: 240ms">
      <!-- This month -->
      <div class="coverage-head relative p-5 sm:p-6">
        <div class="flex items-start justify-between gap-3">
          <div>
            <p class="text-xs font-semibold tracking-[0.12em] text-brand-700 uppercase">Rent coverage</p>
            <h2 class="mt-1 text-lg font-semibold text-slate-900">{{ notStarted ? 'Rental time not started' : tenant?.leaseEnd ? 'Your rental time' : current.name }}</h2>
          </div>
          <span
            class="inline-flex shrink-0 items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium ring-1 ring-inset"
            :class="covered ? 'bg-emerald-50 text-emerald-700 ring-emerald-600/15' : 'bg-amber-50 text-amber-700 ring-amber-600/20'"
          >
            <ShieldCheck v-if="covered" class="size-3.5" />
            <AlertCircle v-else class="size-3.5" />
            {{ covered ? 'Paid' : 'Not paid yet' }}
          </span>
        </div>

        <!-- New tenant: nothing paid, so no days are counting yet -->
        <div v-if="notStarted" class="mt-4">
          <div class="flex items-end gap-3">
            <p class="countdown text-5xl leading-none font-bold tracking-tight tabular-nums">0</p>
            <p class="pb-1 text-sm leading-snug text-slate-600">days counted<br /><span class="text-slate-400">Starts the day you pay</span></p>
          </div>
          <p class="mt-4 text-sm leading-relaxed text-slate-600">
            You haven't paid rent yet, so your rental time hasn't started. When you pay, it starts that same day and runs one month for every month you pay.
          </p>
          <RouterLink to="/tenant/recharge" class="btn-primary mt-4 h-11 w-full rounded-xl sm:w-auto"><Zap class="size-4" /> Pay first rent</RouterLink>
        </div>

        <!-- Paid: count down to the end of the paid rental time -->
        <template v-else-if="tenant?.leaseEnd">
          <div class="mt-4 flex items-end gap-3">
            <p class="countdown text-5xl leading-none font-bold tracking-tight tabular-nums">{{ Math.max(0, daysLeft) }}</p>
            <p class="pb-1 text-sm leading-snug text-slate-600">
              day{{ Math.max(0, daysLeft) === 1 ? '' : 's' }} left<br />
              <span class="text-slate-400">{{ timeEnded ? 'Ended' : 'Ends' }} {{ formatDate(tenant.leaseEnd) }}</span>
            </p>
          </div>
          <div class="mt-4">
            <div class="h-2 overflow-hidden rounded-full bg-white/70 ring-1 ring-slate-200/60">
              <div class="bar month-bar h-full rounded-full" :style="{ '--w': `${leaseProgress}%` }" />
            </div>
            <p class="mt-1.5 text-xs text-slate-500">Started {{ formatDate(tenant.leaseStart) }}</p>
          </div>
          <p class="mt-4 text-sm text-slate-600">
            <template v-if="timeEnded">Your paid time has ended. Pay to continue: the new month runs on from {{ formatDate(tenant.leaseEnd) }}.</template>
            <template v-else>Paid up to <strong class="font-semibold text-slate-900">{{ formatDate(tenant.leaseEnd) }}</strong>. Paying early adds a month on top.</template>
          </p>
        </template>

        <template v-else>
        <div class="mt-4 flex items-end gap-3">
          <p class="countdown text-5xl leading-none font-bold tracking-tight tabular-nums">{{ current.left }}</p>
          <p class="pb-1 text-sm leading-snug text-slate-600">
            day{{ current.left === 1 ? '' : 's' }} left this month<br />
            <span class="text-slate-400">Ends {{ longDate(current.end) }}</span>
          </p>
        </div>

        <div class="mt-4">
          <div class="h-2 overflow-hidden rounded-full bg-white/70 ring-1 ring-slate-200/60">
            <div class="bar month-bar h-full rounded-full" :style="{ '--w': `${current.progress}%` }" />
          </div>
          <p class="mt-1.5 text-xs text-slate-500">Day {{ current.day }} of {{ current.total }}</p>
        </div>

        <p v-if="paidUntil" class="mt-4 text-sm text-slate-600">
          Paid up to <strong class="font-semibold text-slate-900">{{ longDate(paidUntil) }}</strong>.
          You'll get a notification when each paid month begins.
        </p>
        </template>
      </div>

      <!-- Paid months -->
      <div class="bg-white p-5 sm:p-6">
        <div class="flex items-center justify-between">
          <h3 class="text-sm font-semibold text-slate-900">Paid months</h3>
          <RouterLink to="/tenant/recharge" class="inline-flex items-center gap-1 text-sm font-medium text-brand-700 hover:text-brand-600">
            <Zap class="size-3.5" /> Recharge
          </RouterLink>
        </div>

        <ol v-if="coverage.length" class="timeline mt-4">
          <li v-for="(m, i) in coverage" :key="m.id" class="pop relative pb-5 pl-9 last:pb-0" :style="{ '--d': `${320 + i * 70}ms` }">
            <span
              class="absolute top-0.5 left-0 flex size-6 items-center justify-center rounded-full text-[11px] font-bold"
              :class="{
                'dot-current text-white': m.state === 'current',
                'bg-brand-50 text-brand-700 ring-1 ring-brand-200': m.state === 'upcoming',
                'bg-slate-100 text-slate-500': m.state === 'ended',
              }"
            >{{ m.index }}</span>

            <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
              <p class="font-medium text-slate-900">{{ m.name }}</p>
              <span class="text-xs font-medium" :class="m.state === 'current' ? 'text-brand-700' : 'text-slate-500'">
                <template v-if="m.state === 'current'">Ends in {{ m.endsIn }} day{{ m.endsIn === 1 ? '' : 's' }}</template>
                <template v-else-if="m.state === 'upcoming'">Starts {{ shortDate(monthBounds(m.period).start) }}</template>
                <template v-else>Ended</template>
              </span>
            </div>
            <p class="mt-0.5 text-sm text-slate-500">{{ m.range }}</p>
            <p v-if="m.paidOnText" class="mt-1.5 inline-flex items-center gap-1.5 rounded-md bg-slate-50 px-2 py-1 text-xs text-slate-600">
              <Receipt class="size-3.5 text-slate-400" /> Recharged {{ m.paidOnText }}<template v-if="m.method"> · {{ m.method }}</template>
            </p>
          </li>
        </ol>
        <p v-else class="mt-3 text-sm text-slate-500">No months paid yet. Use Recharge to pay ahead.</p>
      </div>
    </section>

    <!-- Rows, like the landlord's overview -->
    <div class="mt-6 grid gap-6 lg:grid-cols-2">
      <!-- Still to pay -->
      <section class="rise" style="--d: 270ms">
        <div class="flex items-center justify-between">
          <h2 class="section-title">Unpaid rent</h2>
          <RouterLink to="/tenant/payments" class="mb-2.5 text-xs font-semibold text-brand-700">All payments</RouterLink>
        </div>
        <div class="sheet">
          <ul v-if="dues.length" class="divide-y divide-slate-100">
            <ListRow
              v-for="d in dues.slice(0, 4)"
              :key="d.id"
              :title="`${formatPeriod(d.period)} rent`"
              :subtitle="`${d.status === 'overdue' ? 'Overdue since' : 'Due'} ${formatDate(d.dueDate)}`"
              :value="formatUGX(d.balance)"
              :value-class="d.status === 'overdue' ? 'text-red-600' : 'text-amber-700'"
              @click="paying = d"
            >
              <template #icon>
                <span class="icon-disc rounded-full" :class="d.status === 'overdue' ? 'disc-red' : 'disc-amber'">
                  <AlertCircle v-if="d.status === 'overdue'" class="size-5" />
                  <Clock v-else class="size-5" />
                </span>
              </template>
            </ListRow>
          </ul>
          <ul v-else>
            <ListRow to="/tenant/recharge" :title="notStarted ? 'Pay your first rent' : 'Nothing to pay'" :subtitle="notStarted ? 'Your rental time starts the day you pay' : 'Recharge any time to pay ahead'">
              <template #icon><span class="icon-disc rounded-full" :class="notStarted ? 'disc-amber' : 'disc-emerald'"><Zap v-if="notStarted" class="size-5" /><ShieldCheck v-else class="size-5" /></span></template>
            </ListRow>
          </ul>
        </div>
      </section>

      <!-- Latest payments -->
      <section class="rise" style="--d: 300ms">
        <div class="flex items-center justify-between">
          <h2 class="section-title">Latest payments</h2>
          <RouterLink to="/tenant/payments" class="mb-2.5 text-xs font-semibold text-brand-700">History</RouterLink>
        </div>
        <div class="sheet">
          <ul v-if="recentPaid.length" class="divide-y divide-slate-100">
            <ListRow
              v-for="p in recentPaid"
              :key="p.id"
              to="/tenant/payments"
              :title="`${formatPeriod(p.period)} rent`"
              :subtitle="`${isCash(p) ? 'Cash' : p.method || 'Mobile money'} · ${formatDate(p.paidAt)}`"
              :value="formatUGX(p.amountPaid)"
              value-class="text-emerald-700"
            >
              <template #icon>
                <span class="icon-disc" :class="isCash(p) ? 'disc-amber' : 'disc-emerald'">
                  <Banknote v-if="isCash(p)" class="size-5" />
                  <ArrowDownLeft v-else class="size-5" />
                </span>
              </template>
            </ListRow>
          </ul>
          <p v-else class="px-5 py-10 text-center text-sm text-slate-500">No payments yet.</p>
        </div>
      </section>

      <!-- How I pay -->
      <section v-if="recentPaid.length" class="rise lg:col-span-2" style="--d: 330ms">
        <h2 class="section-title">How I pay</h2>
        <div class="sheet">
          <ul class="divide-y divide-slate-100">
            <ListRow v-for="m in payWays" :key="m.label" to="/tenant/payments" :title="m.label" :subtitle="`${m.count} payment${m.count === 1 ? '' : 's'}`" :value="formatUGX(m.total)">
              <template #icon>
                <span class="icon-tile" :class="m.label === 'Cash' ? 'tile-amber' : 'tile-teal'">
                  <Banknote v-if="m.label === 'Cash'" class="size-[1.3rem]" />
                  <Smartphone v-else class="size-[1.3rem]" />
                </span>
              </template>
            </ListRow>
          </ul>
        </div>
      </section>
    </div>

    <!-- Contact landlord -->
    <section v-if="owner" class="rise card mt-4 rounded-2xl p-5 sm:p-6" style="--d: 300ms">
      <div class="flex items-center gap-3.5">
        <div class="avatar flex size-12 shrink-0 items-center justify-center rounded-full text-sm font-semibold text-white">
          {{ ownerInitials }}
        </div>
        <div class="min-w-0 flex-1">
          <p class="text-xs font-medium text-slate-500">Your landlord</p>
          <p class="truncate font-semibold text-slate-900">{{ owner.full_name }}</p>
        </div>
      </div>
      <div class="mt-5 grid gap-2.5" :class="['grid-cols-1', 'grid-cols-2', 'grid-cols-3'][(owner.phone ? 1 : 0) + (whatsapp ? 1 : 0)]">
        <a v-if="owner.phone" :href="`tel:${owner.phone}`" class="contact-btn">
          <Phone class="size-5 text-brand-700" /><span>Call</span>
        </a>
        <a v-if="whatsapp" :href="whatsapp" target="_blank" rel="noopener" class="contact-btn">
          <MessageCircle class="size-5 text-emerald-600" /><span>WhatsApp</span>
        </a>
        <a :href="`mailto:${owner.email}`" class="contact-btn">
          <Mail class="size-5 text-sky-600" /><span>Email</span>
        </a>
      </div>
    </section>
  </div>

  <BaseModal :model-value="Boolean(paying)" title="Pay rent" @update:model-value="!$event && (paying = null)">
    <PayRentForm v-if="paying" :payment="paying" @paid="onPaid" @cancel="paying = null" />
  </BaseModal>
</template>

<style scoped>
/* Hero: fixed colours so it looks the same in light and dark mode */
.hero-ok {
  background: linear-gradient(135deg, #14918a 0%, #0f766e 45%, #0a3b38 100%);
}
.hero-overdue {
  background: linear-gradient(135deg, #e0564b 0%, #b42318 50%, #6e1610 100%);
}

.hero {
  --color-white: #fff; /* dark mode remaps "white"; inside the card it must stay white */
  box-shadow: 0 20px 45px -20px rgb(10 59 56 / 0.55);
}
/* Faint grid texture, fading out towards the bottom */
.grid-pattern {
  position: absolute;
  inset: 0;
  background-image:
    linear-gradient(rgb(255 255 255 / 0.06) 1px, transparent 1px),
    linear-gradient(90deg, rgb(255 255 255 / 0.06) 1px, transparent 1px);
  background-size: 28px 28px;
  mask-image: linear-gradient(180deg, #000 0%, transparent 75%);
}
.chip {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  border-radius: 9999px;
  padding: 0.3rem 0.75rem;
  font-size: 0.75rem;
  font-weight: 500;
  background: rgb(255 255 255 / 0.15);
  box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.2);
  backdrop-filter: blur(6px);
}
.hero-btn {
  display: inline-flex;
  height: 3rem;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  border-radius: 0.875rem;
  font-size: 0.9375rem;
  font-weight: 600;
  transition: transform 0.15s ease, background-color 0.15s ease, box-shadow 0.15s ease;
}
.hero-btn:hover {
  transform: translateY(-1px);
}
.hero-btn:active {
  transform: scale(0.98);
}
.hero-btn-solid {
  background: #fff;
  color: #0a3b38;
  box-shadow: 0 6px 16px -6px rgb(0 0 0 / 0.35);
}
.hero-overdue .hero-btn-solid {
  color: #7a1a12;
}
.hero-btn-glass {
  color: #fff;
  background: rgb(255 255 255 / 0.12);
  box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.25);
}
.hero-btn-glass:hover {
  background: rgb(255 255 255 / 0.2);
}

/* Soft light blobs drifting slowly behind the hero content */
.blob {
  position: absolute;
  top: -40%;
  right: -15%;
  width: 22rem;
  height: 22rem;
  border-radius: 9999px;
  background: radial-gradient(circle, rgb(255 255 255 / 0.22), transparent 65%);
  animation: drift 14s ease-in-out infinite alternate;
}
.blob-2 {
  top: auto;
  right: auto;
  bottom: -55%;
  left: -20%;
  width: 18rem;
  height: 18rem;
  background: radial-gradient(circle, rgb(255 255 255 / 0.12), transparent 65%);
  animation-duration: 18s;
}

/* Tiles: faint tinted gradient (uses theme colours, so it follows dark mode) */
.tile {
  transition: transform 0.2s ease, box-shadow 0.2s ease;
}
.tile:hover {
  transform: translateY(-2px);
  box-shadow: 0 10px 30px -12px rgb(15 23 42 / 0.18);
}
.tile-sky {
  background: linear-gradient(160deg, var(--color-sky-50) 0%, var(--color-white) 60%);
}
.tile-brand {
  background: linear-gradient(160deg, var(--color-brand-50) 0%, var(--color-white) 60%);
}
.tile-warn {
  background: linear-gradient(160deg, var(--color-amber-50) 0%, var(--color-white) 60%);
}

/* Greeting: name in brand gradient */
.name-gradient {
  background: linear-gradient(90deg, var(--color-brand-600), #14b8a6 60%, var(--color-sky-600));
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}
.live-dot {
  box-shadow: 0 0 0 0 rgb(16 185 129 / 0.5);
  animation: ping 2.4s ease-out infinite;
}

.avatar {
  background: linear-gradient(135deg, #14918a, #0a3b38);
}
.contact-btn {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 0.375rem;
  min-height: 4.5rem;
  border-radius: 0.875rem;
  border: 1px solid var(--color-slate-200);
  background: linear-gradient(180deg, var(--color-white), var(--color-slate-50));
  font-size: 0.8125rem;
  font-weight: 500;
  color: var(--color-slate-700);
  transition: transform 0.15s ease, border-color 0.15s ease;
}
.contact-btn:hover {
  border-color: var(--color-brand-200);
  transform: translateY(-1px);
}
.contact-btn:active {
  transform: scale(0.97);
}

/* Rent coverage */
.coverage-head {
  background:
    radial-gradient(120% 90% at 100% 0%, var(--color-sky-50) 0%, transparent 55%),
    linear-gradient(160deg, var(--color-brand-50) 0%, var(--color-white) 85%);
}
.countdown {
  background: linear-gradient(135deg, #14918a 0%, #0f766e 45%, #0284c7 100%);
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}
.month-bar {
  background: linear-gradient(90deg, #14b8a6, #0f766e 60%, #0284c7);
}
.dot-current {
  background: linear-gradient(135deg, #14b8a6, #0f766e);
  box-shadow: 0 0 0 4px var(--color-brand-100);
}
/* Gradient line joining the months */
.timeline li:not(:last-child)::before {
  content: '';
  position: absolute;
  top: 1.75rem;
  bottom: 0.25rem;
  left: 0.6875rem;
  width: 2px;
  border-radius: 2px;
  background: linear-gradient(180deg, var(--color-brand-200), var(--color-slate-200));
}

/* Items pop in one by one */
.pop {
  animation: pop 0.4s cubic-bezier(0.34, 1.56, 0.64, 1) backwards;
  animation-delay: var(--d, 0ms);
}

/* Entrance: rise in, slightly staggered */
.rise {
  animation: rise 0.55s cubic-bezier(0.22, 1, 0.36, 1) backwards; /* backwards: hover lift still works after */
  animation-delay: var(--d, 0ms);
}
/* Lease bar fills on load */
.bar {
  width: var(--w);
  animation: fill 1.1s cubic-bezier(0.22, 1, 0.36, 1) 0.35s both;
}

@keyframes rise {
  from { opacity: 0; transform: translateY(12px); }
  to { opacity: 1; transform: none; }
}
@keyframes fill {
  from { width: 0; }
}
@keyframes drift {
  from { transform: translate(0, 0) scale(1); }
  to { transform: translate(-2.5rem, 1.5rem) scale(1.12); }
}

@keyframes pop {
  from { opacity: 0; transform: translateY(8px); }
}
@keyframes ping {
  70% { box-shadow: 0 0 0 6px rgb(16 185 129 / 0); }
  100% { box-shadow: 0 0 0 0 rgb(16 185 129 / 0); }
}

@media (prefers-reduced-motion: reduce) {
  .rise, .bar, .blob, .pop, .live-dot { animation: none; }
  .tile:hover { transform: none; }
}
</style>
