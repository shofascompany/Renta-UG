<script setup>
import { computed, ref } from 'vue'
import {
  CheckCircle2, Banknote, X, Search, FileDown, EllipsisVertical, CalendarDays, Check, ChevronDown, ChevronLeft,
  AlertCircle, Clock, CircleCheck, History, HandCoins, ChevronRight, Smartphone, TrendingDown, Wallet,
  ArrowUpDown, ArrowDownAZ, ArrowUpZA, CalendarClock,
} from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useFilter } from '@/composables/useFilter'
import { searcher } from '@/lib/search'
import { useRentAnalytics, longMonth, downloadCSV } from '@/composables/useRentAnalytics'
import { formatUGX, formatDate, formatPeriod, dayOf } from '@/utils/format'
import { paymentKey, paymentOf } from '@/utils/paymentGroups'
import { NETWORKS } from '@/lib/networks'
import BaseModal from '@/components/BaseModal.vue'
import DropMenu from '@/components/admin/DropMenu.vue'
import RecordPaymentModal from '@/components/RecordPaymentModal.vue'
import PayAccountsModal from '@/components/PayAccountsModal.vue'
import CashReviewList from '@/components/CashReviewList.vue'

// Payments: this month at a glance and everything ever earned, cash waiting for confirmation, then every tenant's rent
// month. Sorted by the date of payment (newest first); the three-dot menu sorts by name or splits them into months.
// Tap one → its own page (PaymentDetailView: receipt, WhatsApp, Reverse payment).
const rental = useRentalStore()
const a = useRentAnalytics()
const status = useFilter('status', 'all', ['all', 'pending', 'overdue', 'paid'])
const query = useFilter('q', '')
const month = useFilter('month', '') // '' = all months
const flash = ref('')

const tenantName = (id) => rental.tenantById(id)?.name ?? 'Former tenant'
const houseName = (id) => rental.placeName(id)
const initials = (name) => name.split(' ').map((p) => p[0]).slice(0, 2).join('').toUpperCase()
const shortPeriod = (p) => {
  const [y, m] = p.split('-').map(Number)
  return new Date(y, m - 1, 1).toLocaleDateString('en-GB', { month: 'short', year: 'numeric' })
}

const monthsWithCharges = computed(() => [...new Set(rental.payments.map((p) => p.period))].sort().reverse())
// This month and search, before the status (the number beside each status comes from these)
const inScope = computed(() => {
  const hit = searcher(query.value)
  return rental.payments
    .filter((p) => !month.value || p.period === month.value)
    .filter((p) => hit(tenantName(p.tenantId), rental.tenantById(p.tenantId)?.phone, houseName(p.propertyId), p.reference, formatPeriod(p.period), p.method))
})
const list = computed(() => inScope.value.filter((p) => status.value === 'all' || p.status === status.value))

// ── Sort (three-dot menu → Sort by) ──
const SORTS = [
  { key: 'date', label: 'Date of payment', sub: 'Newest payments first', icon: CalendarClock },
  { key: 'az', label: 'Tenant A–Z', sub: 'By name', icon: ArrowDownAZ },
  { key: 'za', label: 'Tenant Z–A', sub: 'By name, the other way', icon: ArrowUpZA },
  { key: 'month', label: 'By month', sub: "Each tenant's payment per month", icon: CalendarDays },
]
const sort = useFilter('sort', 'date', SORTS.map((s) => s.key))
const sortNow = computed(() => SORTS.find((s) => s.key === sort.value) ?? SORTS[0])
const menuPage = ref('main') // the three-dot menu shows its main list, or the Sort by list

// The day money last came in for a month: paid in full → that day, part paid → its latest part
const lastIn = computed(() => {
  const m = {}
  for (const r of rental.payment_receipts) if (!m[r.paymentId] || Date.parse(r.receivedAt) > Date.parse(m[r.paymentId])) m[r.paymentId] = r.receivedAt
  return m
})
const paidOn = (p) => p.paidAt ?? (p.amountPaid ? lastIn.value[p.id] ?? null : null)
const periodKey = (r) => String(r.period ?? r.periods?.[0] ?? '')
const byName = (dir) => (x, y) => dir * tenantName(x.tenantId).localeCompare(tenantName(y.tenantId)) || periodKey(y).localeCompare(periodKey(x))

// What the list shows, in sections: by date of payment (default), by name, or one section per rent month
const sections = computed(() => {
  const rows = list.value
  if (sort.value === 'month') {
    const map = new Map()
    for (const p of [...rows].sort((x, y) => y.period.localeCompare(x.period) || x.status.localeCompare(y.status) || byName(1)(x, y))) {
      if (!map.has(p.period)) map.set(p.period, { key: p.period, title: formatPeriod(p.period), rows: [], billed: 0, collected: 0 })
      const g = map.get(p.period)
      g.rows.push(p)
      g.billed += p.amount
      g.collected += p.amountPaid
    }
    return [...map.values()].map((g) => ({ ...g, strong: formatUGX(g.collected), rest: ` of ${formatUGX(g.billed)}` }))
  }
  // Not split into months: one row per PAYMENT, with the whole amount paid (900,000 for 3 months is one row).
  // The months still owed are listed as they are.
  const showPaid = status.value === 'all' || status.value === 'paid'
  const pays = showPaid ? payItems.value : []
  const unpaid = rows.filter((p) => p.status !== 'paid' && p.balance > 0)
  const owed = formatUGX(unpaid.reduce((s, p) => s + p.balance, 0))
  // By name: month by month, like By month (opening one shows just that month)
  if (sort.value === 'az' || sort.value === 'za') {
    const all = [...rows].sort(byName(sort.value === 'az' ? 1 : -1))
    return all.length ? [{ key: sort.value, title: sort.value === 'az' ? 'Tenants A–Z' : 'Tenants Z–A', rows: all, strong: '', rest: `${all.length} rent month${all.length === 1 ? '' : 's'}` }] : []
  }
  const paid = [...pays].sort((x, y) => Date.parse(y.at) - Date.parse(x.at) || byName(1)(x, y))
  const due = [...unpaid].sort((x, y) => String(x.dueDate).localeCompare(String(y.dueDate)) || byName(1)(x, y))
  // A heading for each day money came in: Today, Yesterday, then the date
  const days = new Map()
  for (const p of paid) {
    const d = dayOf(p.at)
    if (!days.has(d)) days.set(d, { key: `day-${d}`, title: dayTitle(d), rows: [], total: 0 })
    const g = days.get(d)
    g.rows.push(p)
    g.total += p.total
  }
  return [
    ...[...days.values()].map((g) => ({ ...g, strong: formatUGX(g.total), rest: ` · ${g.rows.length} payment${g.rows.length === 1 ? '' : 's'}` })),
    due.length && { key: 'unpaid', title: 'Not paid yet', rows: due, strong: owed, rest: ' owed' },
  ].filter(Boolean)
})
const dayTitle = (d) => {
  const today = dayOf(new Date())
  const yesterday = dayOf(new Date(Date.now() - 864e5))
  if (d === today) return 'Today'
  if (d === yesterday) return 'Yesterday'
  return new Date(`${d}T12:00:00`).toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })
}
// Every payment towards the rent months shown, whole (utils/paymentGroups.js). Money paid before receipts existed:
// that month on its own.
const periodOfCharge = (id) => rental.payments.find((p) => p.id === id)?.period ?? ''
// Months of the chosen month + status, before the search (the search then looks at each WHOLE payment)
const unsearched = computed(() => rental.payments.filter((p) => (!month.value || p.period === month.value) && (status.value === 'all' || p.status === status.value)))
const payItems = computed(() => {
  const hit = searcher(query.value)
  return allPayItems.value.filter((x) => hit(
    tenantName(x.tenantId), rental.tenantById(x.tenantId)?.phone, houseName(x.propertyId), formatUGX(x.total), String(x.total),
    formatDate(x.at), x.method, x.reference, ...x.periods.map(formatPeriod),
  ))
})
const allPayItems = computed(() => {
  const shown = new Map(unsearched.value.map((p) => [p.id, p]))
  const firsts = new Map()
  for (const r of rental.payment_receipts) if (shown.has(r.paymentId) && !firsts.has(paymentKey(r))) firsts.set(paymentKey(r), r)
  const items = [...firsts.values()].map((r) => {
    const g = paymentOf(rental.payment_receipts, r.id, periodOfCharge)
    const first = rental.payments.find((p) => p.id === g.receipts[0].paymentId)
    return {
      kind: 'pay', id: `pay-${g.key}`, tenantId: g.tenantId, propertyId: first?.propertyId, total: g.total, at: g.at, method: g.method, reference: g.reference,
      periods: g.receipts.map((x) => periodOfCharge(x.paymentId)).filter(Boolean).sort(),
      to: { path: `/landlord/payments/${g.receipts[0].paymentId}`, query: { receipt: g.id } },
    }
  })
  const receipted = new Set(rental.payment_receipts.map((r) => r.paymentId))
  for (const p of unsearched.value) {
    if (p.amountPaid > 0 && !receipted.has(p.id)) items.push({ kind: 'pay', id: `old-${p.id}`, tenantId: p.tenantId, propertyId: p.propertyId, total: p.amountPaid, at: p.paidAt ?? p.dueDate, method: p.method, periods: [p.period], to: `/landlord/payments/${p.id}` })
  }
  return items
})
// "Dec 2026" or "Dec 2026 – Feb 2027 · 3 months"
const monthsText = (periods) => (periods.length > 1 ? `${shortPeriod(periods[0])} – ${shortPeriod(periods.at(-1))} · ${periods.length} months` : shortPeriod(periods[0]))
const SORTED = { date: 'Sorted by date of payment', az: 'Sorted by name, A–Z', za: 'Sorted by name, Z–A', month: 'Split into months' }
const ordered = computed(() => sections.value.flatMap((s) => s.rows)) // the list exactly as shown (for the download)

const counts = computed(() => ({
  all: inScope.value.length,
  paid: inScope.value.filter((p) => p.status === 'paid').length,
  pending: inScope.value.filter((p) => p.status === 'pending').length,
  overdue: inScope.value.filter((p) => p.status === 'overdue').length,
}))
// Rooms with no tenant earn nothing: the rent they would bring in each month is money lost
const vacantRooms = computed(() => rental.properties.filter((p) => !rental.tenantForProperty(p.id)))
const vacantLoss = computed(() => vacantRooms.value.reduce((s, p) => s + (p.rent || 0), 0))
const owedIn = (key) => inScope.value.filter((p) => p.status === key).reduce((s, p) => s + p.balance, 0)

// Everything ever earned: every payment received (the same total as Transactions)
const paymentsIn = computed(() => new Set(rental.payment_receipts.map(paymentKey)).size + a.revenue.value.filter((r) => String(r.id).startsWith('charge-')).length)
const firstIn = computed(() => a.revenue.value.map((r) => r.at).filter(Boolean).sort((x, y) => Date.parse(x) - Date.parse(y))[0] ?? null)

const thisMonth = new Date().toLocaleDateString('en-CA').slice(0, 7)

// ── Cash (confirmed before it counts) ──
const cashFor = ref(null)
const cashOpen = computed(() => cashFor.value !== null)
const pendingCash = computed(() => rental.pendingCash)
const cashHistoryOpen = ref(false)
const numbersOpen = ref(false)
const payAccounts = computed(() => rental.payAccountsOf())
const cashHistory = computed(() => [...rental.cash_payments].sort((x, y) => y.createdAt.localeCompare(x.createdAt)))

const statusText = { paid: 'Paid', pending: 'Due', overdue: 'Overdue' }
const STATUS = [['all', 'All'], ['pending', 'Due'], ['overdue', 'Overdue'], ['paid', 'Paid']]
const statusPill = { paid: 'bg-emerald-50 text-emerald-700', pending: 'bg-amber-50 text-amber-700', overdue: 'bg-red-50 text-red-700' }

function exportCSV() {
  downloadCSV(`renta-payments-${new Date().toLocaleDateString('en-CA')}.csv`, [
    { label: 'Month', value: (p) => formatPeriod(p.period) },
    { label: 'Tenant', value: (p) => tenantName(p.tenantId) },
    { label: 'House', value: (p) => houseName(p.propertyId) },
    { label: 'Rent (UGX)', value: (p) => p.amount },
    { label: 'Paid (UGX)', value: (p) => p.amountPaid },
    { label: 'Balance (UGX)', value: (p) => p.balance },
    { label: 'Due date', value: (p) => p.dueDate },
    { label: 'Paid on', value: (p) => (p.paidAt ? formatDate(p.paidAt) : '') },
    { label: 'Method', value: (p) => p.method ?? '' },
    { label: 'Reference', value: (p) => p.reference ?? '' },
    { label: 'Status', value: (p) => statusText[p.status] },
  ], list.value)
}
</script>

<template>
  <div class="mx-auto max-w-4xl space-y-6">
    <!-- This month, and everything earned -->
    <section class="page-hero rise px-5 py-6 sm:px-8 sm:py-7">
      <p class="text-xs font-semibold tracking-[0.14em] text-white/70 uppercase">Payments · {{ longMonth(thisMonth) }}</p>

      <!-- The three numbers that matter: this month, everything earned, what empty rooms cost -->
      <div class="mt-4 grid gap-2.5 sm:grid-cols-3" data-stats>
        <div class="stat stat-month">
          <span class="stat-ico"><CalendarDays class="size-[1.1rem]" /></span>
          <span class="stat-label">Collected this month</span>
          <span class="stat-value">{{ formatUGX(a.thisMonth.value.collected) }}</span>
          <span class="stat-sub">of {{ formatUGX(a.thisMonth.value.billed) }} billed</span>
        </div>
        <RouterLink to="/landlord/revenue" class="stat stat-earned" data-total-earned>
          <span class="stat-ico"><Wallet class="size-[1.1rem]" /></span>
          <span class="stat-label">Total income · all time</span>
          <span class="stat-value">{{ formatUGX(a.totalRevenue.value) }}</span>
          <span class="stat-sub">{{ paymentsIn }} payment{{ paymentsIn === 1 ? '' : 's' }}{{ firstIn ? ` since ${formatDate(firstIn)}` : '' }}</span>
        </RouterLink>
        <RouterLink :to="{ path: '/landlord/properties', query: { show: 'vacant' } }" class="stat" :class="vacantLoss ? 'stat-lost' : 'stat-full'" data-tour="vacancy-loss" data-lost>
          <span class="stat-ico"><component :is="vacantLoss ? TrendingDown : CircleCheck" class="size-[1.1rem]" /></span>
          <span class="stat-label">Lost to empty rooms</span>
          <span class="stat-value">{{ vacantLoss ? formatUGX(vacantLoss) : 'Nothing' }}</span>
          <span class="stat-sub">{{ vacantRooms.length ? `${vacantRooms.length} empty room${vacantRooms.length === 1 ? '' : 's'} · every month` : 'Every room has a tenant' }}</span>
        </RouterLink>
      </div>

      <div class="mt-5 grid gap-2.5 sm:grid-cols-2">
        <button type="button" class="pay-action pay-action-solid w-full" data-tour="record-payment" @click="cashFor = ''">
          <span class="pay-ico bg-teal-600 text-white"><HandCoins class="size-[1.15rem]" /></span>
          <span class="min-w-0 flex-1 text-left">
            <span class="block truncate text-sm font-semibold">Record payment</span>
            <span class="block truncate text-[11px] font-medium text-[#5b7a77]">Cash or mobile money received</span>
          </span>
          <ChevronRight class="size-4 shrink-0 text-[#5b7a77]" />
        </button>
        <button type="button" class="pay-action pay-action-glass w-full" data-tour="pay-numbers" @click="numbersOpen = true">
          <span class="pay-ico bg-white/15 text-white"><Smartphone class="size-[1.15rem]" /></span>
          <span class="min-w-0 flex-1 text-left">
            <span class="block truncate text-sm font-semibold">Mobile money numbers</span>
            <span class="block truncate text-[11px] font-medium text-white/70">{{ payAccounts.length ? payAccounts.map((a) => NETWORKS[a.network].short).join(' · ') : 'Add where tenants send rent' }}</span>
          </span>
          <ChevronRight class="size-4 shrink-0 text-white/70" />
        </button>
      </div>
    </section>

    <!-- No receiving number yet: tenants can't pay by mobile money -->
    <button v-if="!payAccounts.length" type="button" class="flex w-full items-center gap-3 rounded-2xl border border-amber-200 bg-amber-50 p-3.5 text-left" @click="numbersOpen = true">
      <span class="icon-tile tile-amber size-10"><Smartphone class="size-5" /></span>
      <span class="min-w-0 flex-1 text-sm text-amber-900"><strong>Add your mobile money number.</strong> Tenants with the app can then pay you with MTN or Airtel Mobile Money.</span>
      <ChevronRight class="size-4 shrink-0 text-amber-700" />
    </button>
    <div v-if="flash" class="flex items-center gap-3 rounded-2xl border border-emerald-200 bg-emerald-50 p-3.5">
      <CheckCircle2 class="size-5 shrink-0 text-emerald-600" />
      <p class="flex-1 text-sm text-emerald-800">{{ flash }}</p>
      <button class="rounded-lg p-1 text-emerald-700 hover:bg-emerald-100" aria-label="Dismiss" @click="flash = ''"><X class="size-4" /></button>
    </div>

    <!-- Cash waiting for confirmation (only when there is some) -->
    <section v-if="pendingCash.length" class="rise" style="--d: 60ms" data-tour="to-confirm">
      <h2 class="section-title">Payments to confirm</h2>
      <div class="sheet border-amber-200">
        <div class="flex items-center gap-3 border-b border-amber-100 bg-amber-50/70 px-4 py-3 sm:px-5">
          <span class="icon-tile tile-amber size-10"><HandCoins class="size-5" /></span>
          <p class="min-w-0 flex-1 text-sm text-amber-900">
            <strong>{{ pendingCash.length }}</strong> payment{{ pendingCash.length === 1 ? '' : 's' }} waiting.
            <span class="text-amber-800/80">Check your phone or cash, then confirm. The tenant gets a notification.</span>
          </p>
        </div>
        <div class="max-h-[24rem] overflow-y-auto">
          <CashReviewList :items="pendingCash" empty="Nothing waiting." />
        </div>
      </div>
    </section>

    <!-- Rent charges -->
    <section class="rise" style="--d: 100ms">
      <h2 class="section-title">Rent charges</h2>

      <!-- Toolbar -->
      <div class="flex items-center gap-2" data-tour="charges-tools">
        <div class="relative min-w-0 flex-1">
          <Search class="pointer-events-none absolute top-1/2 left-3.5 size-4 -translate-y-1/2 text-slate-400" />
          <input v-model="query" class="input h-11 rounded-xl bg-white pl-10" placeholder="Search tenant, house or reference" />
        </div>

        <!-- Month -->
        <DropMenu label="Choose month" title="Month" width="w-60" trigger-class="tool-btn" :class="month && 'is-on'">
          <template #trigger>
            <CalendarDays class="size-[1.15rem]" />
            <span class="hidden sm:inline">{{ month ? longMonth(month) : 'All months' }}</span>
            <ChevronDown class="hidden size-4 text-slate-400 sm:block" />
            <span v-if="month" class="tool-dot sm:hidden" />
          </template>
          <template #default="{ close }">
            <div>
              <button type="button" class="menu-item" :class="!month && 'menu-item-on'" @click="month = ''; close()">
                <span class="flex-1 text-left">All months</span><span v-if="!month" class="menu-check"><Check class="size-3" stroke-width="3" /></span>
              </button>
              <button v-for="m in monthsWithCharges" :key="m" type="button" class="menu-item" :class="month === m && 'menu-item-on'" @click="month = m; close()">
                <span class="flex-1 text-left">{{ longMonth(m) }}</span><span v-if="month === m" class="menu-check"><Check class="size-3" stroke-width="3" /></span>
              </button>
            </div>
          </template>
        </DropMenu>

        <!-- More: download, history, transactions, and Sort by (its own list) -->
        <DropMenu label="More options" width="w-72" trigger-class="tool-btn tool-icon" :class="sort !== 'date' && 'is-on'" @open="menuPage = 'main'">
          <template #trigger><EllipsisVertical class="size-[1.15rem]" /><span v-if="sort !== 'date'" class="tool-dot" /></template>
          <template #default="{ close }">
            <template v-if="menuPage === 'main'">
              <button type="button" class="menu-item" data-sort-menu @click="menuPage = 'sort'">
                <span class="menu-ico bg-violet-50 text-violet-700"><ArrowUpDown class="size-4" /></span>
                <span class="flex-1 text-left">Sort by<span class="menu-sub">{{ sortNow.label }}</span></span>
                <ChevronRight class="size-4 shrink-0 text-slate-400" />
              </button>
              <button type="button" class="menu-item" :disabled="!ordered.length" @click="exportCSV(); close()">
                <span class="menu-ico bg-emerald-50 text-emerald-700"><FileDown class="size-4" /></span>
                <span class="flex-1 text-left">Download list<span class="menu-sub">Excel / CSV file</span></span>
              </button>
              <button type="button" class="menu-item" @click="cashHistoryOpen = true; close()">
                <span class="menu-ico bg-amber-50 text-amber-700"><History class="size-4" /></span>
                <span class="flex-1 text-left">Payment history<span class="menu-sub">Cash and mobile money</span></span>
              </button>
              <RouterLink to="/landlord/revenue" class="menu-item" @click="close()">
                <span class="menu-ico bg-sky-50 text-sky-700"><Banknote class="size-4" /></span>
                <span class="flex-1 text-left">Transactions<span class="menu-sub">Every payment received</span></span>
              </RouterLink>
            </template>
            <!-- Sort by: the second list -->
            <template v-else>
              <button type="button" class="menu-item menu-back" @click="menuPage = 'main'">
                <ChevronLeft class="size-4 shrink-0 text-slate-500" />
                <span class="flex-1 text-left font-semibold text-slate-900">Sort by</span>
              </button>
              <button
                v-for="s in SORTS"
                :key="s.key"
                type="button"
                class="menu-item"
                :class="sort === s.key && 'menu-item-on'"
                :data-sort="s.key"
                @click="sort = s.key; close()"
              >
                <span class="menu-ico bg-slate-100 text-slate-600"><component :is="s.icon" class="size-4" /></span>
                <span class="flex-1 text-left">{{ s.label }}<span class="menu-sub">{{ s.key === 'date' ? `${s.sub} · the usual order` : s.sub }}</span></span>
                <span v-if="sort === s.key" class="menu-check"><Check class="size-3" stroke-width="3" /></span>
              </button>
            </template>
          </template>
        </DropMenu>
      </div>

      <!-- Status -->
      <div class="-mx-4 mt-3 flex gap-2 overflow-x-auto px-4 pb-1 sm:mx-0 sm:px-0" role="tablist" aria-label="Status">
        <button
          v-for="s in STATUS"
          :key="s[0]"
          type="button"
          role="tab"
          :aria-selected="status === s[0]"
          class="flex h-9 shrink-0 items-center gap-1.5 rounded-full px-4 text-sm font-medium transition"
          :class="status === s[0] ? 'bg-slate-900 text-white' : 'bg-white text-slate-600 ring-1 ring-slate-200 hover:bg-slate-50'"
          @click="status = s[0]"
        >{{ s[1] }} <span class="text-xs opacity-60 tabular-nums">{{ counts[s[0]] }}</span></button>
      </div>
      <p v-if="status === 'pending' && counts.pending" class="mt-2 px-1 text-xs text-slate-500">{{ formatUGX(owedIn('pending')) }} due, not yet late.</p>
      <p v-if="status === 'overdue' && counts.overdue" class="mt-2 px-1 text-xs font-medium text-red-600">{{ formatUGX(owedIn('overdue')) }} overdue.</p>
      <p v-if="ordered.length" class="mt-2 flex items-center gap-1.5 px-1 text-xs text-slate-500" data-sorted>
        <component :is="sortNow.icon" class="size-3.5" /> {{ SORTED[sort] }}
        <button v-if="sort !== 'date'" type="button" class="ml-1 font-semibold text-brand-700" @click="sort = 'date'">Back to date of payment</button>
      </p>

      <!-- The rent months, in the chosen order -->
      <div v-for="g in sections" :key="g.key" class="mt-5" :data-section="g.key">
        <div class="sec-head mb-2 flex items-baseline justify-between gap-3 px-1">
          <h3 class="text-sm font-semibold text-slate-900">{{ g.title }}</h3>
          <p class="text-xs text-slate-500 tabular-nums"><span v-if="g.strong" class="font-semibold text-slate-900">{{ g.strong }}</span>{{ g.rest }}</p>
        </div>
        <div class="sheet">
          <ul class="divide-y divide-slate-100">
            <li v-for="p in g.rows" :key="p.id">
              <!-- One whole payment -->
              <RouterLink v-if="p.kind === 'pay'" :to="p.to" class="group flex w-full items-center gap-3.5 px-4 py-3.5 text-left transition-colors hover:bg-slate-50 active:bg-slate-100 sm:px-5" data-pay>
                <span class="relative shrink-0">
                  <span class="icon-disc disc-emerald rounded-full text-xs font-bold">{{ initials(tenantName(p.tenantId)) }}</span>
                  <span class="absolute -right-0.5 -bottom-0.5 flex size-4.5 items-center justify-center rounded-full bg-emerald-500 ring-2 ring-white"><Check class="size-3 text-white" stroke-width="3" /></span>
                </span>
                <!-- The title: the whole amount paid, and the day it came in -->
                <div class="min-w-0 flex-1">
                  <p class="truncate font-semibold text-slate-900 tabular-nums" data-pay-title>{{ formatUGX(p.total) }} <span class="font-medium text-slate-500">· {{ formatDate(p.at) }}</span></p>
                  <p class="truncate text-xs text-slate-500"><span class="font-medium text-slate-700">{{ tenantName(p.tenantId) }}</span> · {{ monthsText(p.periods) }}<template v-if="p.method"> · {{ p.method }}</template></p>
                </div>
                <span class="shrink-0 rounded-md bg-emerald-50 px-1.5 py-0.5 text-[11px] font-semibold text-emerald-700">{{ p.periods.length > 1 ? `${p.periods.length} months` : '1 month' }}</span>
                <ChevronRight class="hidden size-4 shrink-0 text-slate-300 group-hover:text-slate-500 sm:block" />
              </RouterLink>
              <RouterLink v-else :to="{ path: `/landlord/payments/${p.id}`, query: { only: 'month' } }" class="group flex w-full items-center gap-3.5 px-4 py-3.5 text-left transition-colors hover:bg-slate-50 active:bg-slate-100 sm:px-5" data-charge>
                <span class="relative shrink-0">
                  <span class="icon-disc rounded-full text-xs font-bold" :class="p.status === 'paid' ? 'disc-emerald' : p.status === 'overdue' ? 'disc-red' : 'disc-amber'">{{ initials(tenantName(p.tenantId)) }}</span>
                  <span class="absolute -right-0.5 -bottom-0.5 flex size-4.5 items-center justify-center rounded-full ring-2 ring-white" :class="p.status === 'paid' ? 'bg-emerald-500' : p.status === 'overdue' ? 'bg-red-500' : 'bg-amber-500'">
                    <Check v-if="p.status === 'paid'" class="size-3 text-white" stroke-width="3" />
                    <AlertCircle v-else-if="p.status === 'overdue'" class="size-3 text-white" stroke-width="3" />
                    <Clock v-else class="size-3 text-white" stroke-width="3" />
                  </span>
                </span>
                <div class="min-w-0 flex-1">
                  <p class="truncate font-medium text-slate-900">{{ tenantName(p.tenantId) }}</p>
                  <p class="truncate text-xs text-slate-500">
                    <template v-if="sort !== 'month'">{{ shortPeriod(p.period) }} · </template>{{ houseName(p.propertyId) }} ·
                    <template v-if="p.status === 'paid'">paid {{ formatDate(p.paidAt) }}<template v-if="p.method"> · {{ p.method }}</template></template>
                    <template v-else-if="sort === 'date' && paidOn(p)">part paid {{ formatDate(paidOn(p)) }} · {{ formatUGX(p.amountPaid) }}</template>
                    <template v-else>due {{ formatDate(p.dueDate) }}<template v-if="p.amountPaid"> · {{ formatUGX(p.amountPaid) }} paid</template></template>
                  </p>
                </div>
                <div class="shrink-0 text-right">
                  <p class="text-sm font-semibold text-slate-900 tabular-nums">{{ formatUGX(p.status === 'paid' ? p.amount : p.balance) }}</p>
                  <span class="mt-0.5 inline-block rounded-md px-1.5 py-0.5 text-[11px] font-semibold" :class="statusPill[p.status]">{{ statusText[p.status] }}</span>
                </div>
                <ChevronRight class="hidden size-4 shrink-0 text-slate-300 group-hover:text-slate-500 sm:block" />
              </RouterLink>
            </li>
          </ul>
        </div>
      </div>

      <div v-if="!sections.length" class="sheet mt-4 flex flex-col items-center px-6 py-14 text-center">
        <span class="icon-tile tile-teal size-12"><CircleCheck class="size-6" /></span>
        <p class="mt-3 font-semibold text-slate-900">{{ rental.payments.length ? 'Nothing matches' : 'No rent charges yet' }}</p>
        <p class="mt-1 max-w-xs text-sm text-slate-500">{{ rental.payments.length ? 'Try another month, status or search.' : 'Rent charges for your tenants will appear here.' }}</p>
      </div>
    </section>

    <!-- All cash payments -->
    <BaseModal v-model="cashHistoryOpen" title="Payment history" width="max-w-lg">
      <div class="-mx-5 -my-5">
        <CashReviewList :items="cashHistory" empty="No payments recorded yet." />
      </div>
    </BaseModal>

    <RecordPaymentModal :model-value="cashOpen" :tenant-id="cashFor || null" @update:model-value="!$event && (cashFor = null)" />
    <PayAccountsModal v-model="numbersOpen" />
  </div>
</template>

<style scoped>
/* Top card actions */
.pay-action {
  --color-white: #fff;
  display: flex;
  height: 3.75rem;
  align-items: center;
  gap: 0.7rem;
  border-radius: 1.1rem;
  padding: 0 0.7rem;
  transition: transform 0.15s ease, background-color 0.15s ease;
}
.pay-action:active { transform: scale(0.97); }
.pay-action-solid { background: #fff; color: #0a3b38; box-shadow: 0 10px 22px -12px rgb(0 0 0 / 0.5); }
.pay-action-glass { color: #fff; background: rgb(var(--glass) / 0.12); box-shadow: inset 0 0 0 1px rgb(var(--glass) / 0.22); }
.pay-action-glass:hover { background: rgb(var(--glass) / 0.18); }
.pay-ico {
  display: flex;
  width: 2.35rem;
  height: 2.35rem;
  flex-shrink: 0;
  align-items: center;
  justify-content: center;
  border-radius: 0.8rem;
}
/* Date (and month) headings: scroll away with their payments */
.sec-head {
  margin-left: -0.25rem;
  margin-right: -0.25rem;
  padding: 0.55rem 0.5rem;
}
/* The three stat cards on the hero: each its own colour, in light and dark mode */
.stat {
  --color-white: #fff;
  position: relative;
  display: flex;
  min-width: 0;
  flex-direction: column;
  border-radius: 1.1rem;
  padding: 0.9rem 1rem 0.95rem;
  color: #fff;
  background: rgb(255 255 255 / 0.1);
  box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.16);
  transition: transform 0.15s ease, background-color 0.15s ease;
}
a.stat:active { transform: scale(0.985); }
a.stat:hover { background: rgb(255 255 255 / 0.15); }
.stat-ico { display: flex; width: 2.1rem; height: 2.1rem; align-items: center; justify-content: center; border-radius: 0.7rem; margin-bottom: 0.6rem; }
.stat-label { font-size: 0.6875rem; font-weight: 600; letter-spacing: 0.1em; text-transform: uppercase; color: rgb(255 255 255 / 0.75); }
.stat-value { margin-top: 0.2rem; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 1.35rem; font-weight: 800; letter-spacing: -0.01em; font-variant-numeric: tabular-nums; }
.stat-sub { margin-top: 0.1rem; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 0.7rem; color: rgb(255 255 255 / 0.72); }
.stat-month .stat-ico { color: #0a3b38; background: #ccfbf1; }
.stat-earned { background: linear-gradient(135deg, rgb(251 191 36 / 0.3), rgb(16 185 129 / 0.22)); box-shadow: inset 0 0 0 1px rgb(253 230 138 / 0.45); }
.stat-earned .stat-ico { color: #78350f; background: linear-gradient(140deg, #fde68a, #f59e0b); }
.stat-lost { background: linear-gradient(135deg, rgb(248 113 113 / 0.28), rgb(251 146 60 / 0.18)); box-shadow: inset 0 0 0 1px rgb(254 202 202 / 0.4); }
.stat-lost .stat-ico { color: #7f1d1d; background: linear-gradient(140deg, #fecaca, #f87171); }
.stat-full .stat-ico { color: #064e3b; background: #a7f3d0; }
html.dark .stat { background: #000000; }
html.dark .stat-earned { box-shadow: inset 0 0 0 1px rgb(252 211 77 / 0.45); }
html.dark .stat-lost { box-shadow: inset 0 0 0 1px rgb(248 113 113 / 0.45); }

/* Toolbar buttons (month / more) */
:deep(.tool-btn) {
  position: relative;
  display: inline-flex;
  height: 2.75rem;
  min-width: 2.75rem;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  border-radius: 0.875rem;
  border: 1px solid var(--color-slate-200);
  background: var(--color-white);
  padding: 0 0.85rem;
  font-size: 0.875rem;
  font-weight: 500;
  color: var(--color-slate-700);
  transition: background-color 0.15s ease, border-color 0.15s ease;
}
:deep(.tool-btn:hover) { background: var(--color-slate-50); }
:deep(.tool-btn[aria-expanded='true']) { border-color: var(--color-brand-200); background: var(--color-brand-50); color: var(--color-brand-700); }
:deep(.tool-icon) { padding: 0; }
.is-on :deep(.tool-btn) { border-color: var(--color-brand-200); color: var(--color-brand-700); }
.tool-dot {
  position: absolute;
  top: 0.45rem;
  right: 0.45rem;
  width: 0.5rem;
  height: 0.5rem;
  border-radius: 9999px;
  background: var(--color-brand-600);
  box-shadow: 0 0 0 2px var(--color-white);
}
</style>
