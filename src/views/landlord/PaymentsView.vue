<script setup>
import { computed, ref } from 'vue'
import {
  CheckCircle2, Banknote, X, Search, FileDown, EllipsisVertical, CalendarDays, Check, ChevronDown,
  AlertCircle, Clock, CircleCheck, History, HandCoins, ChevronRight,
} from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useRentAnalytics, longMonth, downloadCSV } from '@/composables/useRentAnalytics'
import { formatUGX, formatDate, formatPeriod } from '@/utils/format'
import BaseModal from '@/components/BaseModal.vue'
import DropMenu from '@/components/admin/DropMenu.vue'
import CashPaymentModal from '@/components/CashPaymentModal.vue'
import CashReviewList from '@/components/CashReviewList.vue'

// Payments: this month at a glance, cash waiting for confirmation, then every rent charge grouped by month.
const rental = useRentalStore()
const a = useRentAnalytics()
const status = ref('all') // all | pending | overdue | paid
const query = ref('')
const month = ref('') // '' = all months
const flash = ref('')

const tenantName = (id) => rental.tenantById(id)?.name ?? 'Former tenant'
const houseName = (id) => rental.placeName(id)
const initials = (name) => name.split(' ').map((p) => p[0]).slice(0, 2).join('').toUpperCase()

const monthsWithCharges = computed(() => [...new Set(rental.payments.map((p) => p.period))].sort().reverse())
const list = computed(() => {
  const q = query.value.trim().toLowerCase()
  return rental.payments
    .filter((p) => status.value === 'all' || p.status === status.value)
    .filter((p) => !month.value || p.period === month.value)
    .filter((p) => !q || `${tenantName(p.tenantId)} ${houseName(p.propertyId)} ${p.reference ?? ''}`.toLowerCase().includes(q))
    .sort((x, y) => y.period.localeCompare(x.period) || x.status.localeCompare(y.status) || tenantName(x.tenantId).localeCompare(tenantName(y.tenantId)))
})
// Grouped by rent month, newest first
const groups = computed(() => {
  const map = new Map()
  for (const p of list.value) {
    if (!map.has(p.period)) map.set(p.period, { period: p.period, rows: [], billed: 0, collected: 0 })
    const g = map.get(p.period)
    g.rows.push(p)
    g.billed += p.amount
    g.collected += p.amountPaid
  }
  return [...map.values()]
})
const counts = computed(() => ({
  all: rental.payments.length,
  paid: rental.payments.filter((p) => p.status === 'paid').length,
  pending: rental.payments.filter((p) => p.status === 'pending').length,
  overdue: rental.payments.filter((p) => p.status === 'overdue').length,
}))
const dueTotal = computed(() => rental.payments.filter((p) => p.status === 'pending').reduce((s, p) => s + p.balance, 0))

function showFlash(msg) {
  flash.value = msg
  setTimeout(() => (flash.value = ''), 5000)
}

const thisMonth = new Date().toLocaleDateString('en-CA').slice(0, 7)

// ── Cash (confirmed before it counts) ──
const cashFor = ref(null)
const cashOpen = computed(() => cashFor.value !== null)
const toConfirm = computed(() => rental.pendingCash)
const pendingCash = computed(() => rental.pendingCash)
const cashHistoryOpen = ref(false)
const cashHistory = computed(() => [...rental.cash_payments].sort((x, y) => y.createdAt.localeCompare(x.createdAt)))

// Tap a charge → its details
const openCharge = ref(null)
const charge_ = computed(() => rental.payments.find((p) => p.id === openCharge.value) ?? null)
function cashFromDetails() {
  cashFor.value = charge_.value.tenantId
  openCharge.value = null
}

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
    <!-- This month -->
    <section class="page-hero rise px-5 py-6 sm:px-8 sm:py-7">
      <p class="text-xs font-semibold tracking-[0.14em] text-white/70 uppercase">Payments · {{ longMonth(thisMonth) }}</p>
      <p class="mt-3 text-sm text-white/80">Collected this month</p>
      <p class="mt-0.5 text-[2rem] leading-tight font-bold tracking-tight tabular-nums sm:text-4xl">{{ formatUGX(a.thisMonth.value.collected) }}</p>

      <div class="mt-6 sm:max-w-xs">
        <button type="button" class="pay-action pay-action-solid w-full" @click="cashFor = ''">
          <span class="pay-ico bg-teal-600 text-white"><Banknote class="size-[1.15rem]" /></span>
          <span class="min-w-0 flex-1 text-left">
            <span class="block truncate text-sm font-semibold">Record cash</span>
            <span class="block truncate text-[11px] font-medium text-[#5b7a77]">Cash you received from a tenant</span>
          </span>
          <ChevronRight class="size-4 shrink-0 text-[#5b7a77]" />
        </button>
      </div>
    </section>
    <div v-if="flash" class="flex items-center gap-3 rounded-2xl border border-emerald-200 bg-emerald-50 p-3.5">
      <CheckCircle2 class="size-5 shrink-0 text-emerald-600" />
      <p class="flex-1 text-sm text-emerald-800">{{ flash }}</p>
      <button class="rounded-lg p-1 text-emerald-700 hover:bg-emerald-100" aria-label="Dismiss" @click="flash = ''"><X class="size-4" /></button>
    </div>

    <!-- Cash waiting for confirmation (only when there is some) -->
    <section v-if="pendingCash.length" class="rise" style="--d: 60ms">
      <h2 class="section-title">Cash to confirm</h2>
      <div class="sheet border-amber-200">
        <div class="flex items-center gap-3 border-b border-amber-100 bg-amber-50/70 px-4 py-3 sm:px-5">
          <span class="icon-tile tile-amber size-10"><HandCoins class="size-5" /></span>
          <p class="min-w-0 flex-1 text-sm text-amber-900">
            <strong>{{ pendingCash.length }}</strong> cash payment{{ pendingCash.length === 1 ? '' : 's' }} waiting.
            <span class="text-amber-800/80">{{ toConfirm.length ? 'Check the amount and confirm.' : 'Cash you record counts straight away.' }}</span>
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
      <div class="flex items-center gap-2">
        <div class="relative min-w-0 flex-1">
          <Search class="pointer-events-none absolute top-1/2 left-3.5 size-4 -translate-y-1/2 text-slate-400" />
          <input v-model="query" class="input h-11 rounded-xl bg-white pl-10" placeholder="Search tenant, house or reference" />
        </div>

        <!-- Month -->
        <DropMenu label="Choose month" width="w-60" trigger-class="tool-btn" :class="month && 'is-on'">
          <template #trigger>
            <CalendarDays class="size-[1.15rem]" />
            <span class="hidden sm:inline">{{ month ? longMonth(month) : 'All months' }}</span>
            <ChevronDown class="hidden size-4 text-slate-400 sm:block" />
            <span v-if="month" class="tool-dot sm:hidden" />
          </template>
          <template #default="{ close }">
            <div class="max-h-72 overflow-y-auto">
              <button type="button" class="menu-item" :class="!month && 'menu-item-on'" @click="month = ''; close()">
                <span class="flex-1 text-left">All months</span><Check v-if="!month" class="size-4" />
              </button>
              <button v-for="m in monthsWithCharges" :key="m" type="button" class="menu-item" :class="month === m && 'menu-item-on'" @click="month = m; close()">
                <span class="flex-1 text-left">{{ longMonth(m) }}</span><Check v-if="month === m" class="size-4" />
              </button>
            </div>
          </template>
        </DropMenu>

        <!-- More -->
        <DropMenu label="More options" width="w-64" trigger-class="tool-btn tool-icon">
          <template #trigger><EllipsisVertical class="size-[1.15rem]" /></template>
          <template #default="{ close }">
            <button type="button" class="menu-item" :disabled="!list.length" @click="exportCSV(); close()">
              <span class="menu-ico bg-emerald-50 text-emerald-700"><FileDown class="size-4" /></span>
              <span class="flex-1 text-left">Download list<span class="block text-xs font-normal text-slate-400">Excel / CSV file</span></span>
            </button>
            <button type="button" class="menu-item" @click="cashHistoryOpen = true; close()">
              <span class="menu-ico bg-amber-50 text-amber-700"><History class="size-4" /></span>
              <span class="flex-1 text-left">Cash history<span class="block text-xs font-normal text-slate-400">All cash payments</span></span>
            </button>
            <RouterLink to="/landlord/revenue" class="menu-item" @click="close()">
              <span class="menu-ico bg-sky-50 text-sky-700"><Banknote class="size-4" /></span>
              <span class="flex-1 text-left">Transactions<span class="block text-xs font-normal text-slate-400">Every payment received</span></span>
            </RouterLink>
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
      <p v-if="status === 'pending' && dueTotal" class="mt-2 px-1 text-xs text-slate-500">{{ formatUGX(dueTotal) }} due, not yet late.</p>
      <p v-if="status === 'overdue' && a.overdueTotal.value" class="mt-2 px-1 text-xs font-medium text-red-600">{{ formatUGX(a.overdueTotal.value) }} overdue.</p>

      <!-- Months -->
      <div v-for="g in groups" :key="g.period" class="mt-5">
        <div class="mb-2 flex items-baseline justify-between gap-3 px-1">
          <h3 class="text-sm font-semibold text-slate-900">{{ formatPeriod(g.period) }}</h3>
          <p class="text-xs text-slate-500 tabular-nums"><span class="font-semibold text-slate-900">{{ formatUGX(g.collected) }}</span> of {{ formatUGX(g.billed) }}</p>
        </div>
        <div class="sheet">
          <ul class="divide-y divide-slate-100">
            <li v-for="p in g.rows" :key="p.id">
              <button type="button" class="group flex w-full items-center gap-3.5 px-4 py-3.5 text-left transition-colors hover:bg-slate-50 active:bg-slate-100 sm:px-5" @click="openCharge = p.id">
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
                    {{ houseName(p.propertyId) }} ·
                    <template v-if="p.status === 'paid'">paid {{ formatDate(p.paidAt) }}<template v-if="p.method"> · {{ p.method }}</template></template>
                    <template v-else>due {{ formatDate(p.dueDate) }}<template v-if="p.amountPaid"> · {{ formatUGX(p.amountPaid) }} paid</template></template>
                  </p>
                </div>
                <div class="shrink-0 text-right">
                  <p class="text-sm font-semibold text-slate-900 tabular-nums">{{ formatUGX(p.status === 'paid' ? p.amount : p.balance) }}</p>
                  <span class="mt-0.5 inline-block rounded-md px-1.5 py-0.5 text-[11px] font-semibold" :class="statusPill[p.status]">{{ statusText[p.status] }}</span>
                </div>
                <ChevronRight class="hidden size-4 shrink-0 text-slate-300 group-hover:text-slate-500 sm:block" />
              </button>
            </li>
          </ul>
        </div>
      </div>

      <div v-if="!groups.length" class="sheet mt-4 flex flex-col items-center px-6 py-14 text-center">
        <span class="icon-tile tile-teal size-12"><CircleCheck class="size-6" /></span>
        <p class="mt-3 font-semibold text-slate-900">{{ counts.all ? 'Nothing matches' : 'No rent charges yet' }}</p>
        <p class="mt-1 max-w-xs text-sm text-slate-500">{{ counts.all ? 'Try another month, status or search.' : 'Rent charges for your tenants will appear here.' }}</p>
      </div>
    </section>

    <!-- Charge details -->
    <BaseModal :model-value="Boolean(charge_)" title="Rent charge" width="max-w-md" @update:model-value="!$event && (openCharge = null)">
      <div v-if="charge_" class="space-y-5">
        <div class="rounded-2xl px-5 py-5 text-white" :style="{ background: charge_.status === 'paid' ? 'linear-gradient(135deg,#14918a,#0a3b38)' : charge_.status === 'overdue' ? 'linear-gradient(135deg,#e0564b,#6e1610)' : 'linear-gradient(135deg,#f5b544,#b45309)' }">
          <p class="text-xs font-semibold tracking-wider text-white/75 uppercase">{{ formatPeriod(charge_.period) }} · {{ statusText[charge_.status] }}</p>
          <p class="mt-1 text-3xl font-bold tabular-nums">{{ formatUGX(charge_.status === 'paid' ? charge_.amount : charge_.balance) }}</p>
          <p class="mt-1 text-sm text-white/80">{{ charge_.status === 'paid' ? 'Paid in full' : `still owed of ${formatUGX(charge_.amount)}` }}</p>
        </div>
        <dl class="divide-y divide-slate-100 text-sm">
          <div class="flex justify-between gap-3 py-3"><dt class="text-slate-500">Tenant</dt><dd class="font-medium text-slate-900">{{ tenantName(charge_.tenantId) }}</dd></div>
          <div class="flex justify-between gap-3 py-3"><dt class="text-slate-500">House / room</dt><dd class="text-right font-medium text-slate-900">{{ houseName(charge_.propertyId) }}</dd></div>
          <div class="flex justify-between gap-3 py-3"><dt class="text-slate-500">Rent</dt><dd class="font-medium text-slate-900 tabular-nums">{{ formatUGX(charge_.amount) }}</dd></div>
          <div class="flex justify-between gap-3 py-3"><dt class="text-slate-500">Paid so far</dt><dd class="font-medium text-slate-900 tabular-nums">{{ formatUGX(charge_.amountPaid) }}</dd></div>
          <div class="flex justify-between gap-3 py-3"><dt class="text-slate-500">Due</dt><dd class="font-medium text-slate-900">{{ formatDate(charge_.dueDate) }}</dd></div>
          <div v-if="charge_.paidAt" class="flex justify-between gap-3 py-3"><dt class="text-slate-500">Paid on</dt><dd class="font-medium text-slate-900">{{ formatDate(charge_.paidAt) }}<span v-if="charge_.method"> · {{ charge_.method }}</span></dd></div>
          <div v-if="charge_.reference" class="flex justify-between gap-3 py-3"><dt class="text-slate-500">Reference</dt><dd class="font-mono text-xs font-medium text-slate-900">{{ charge_.reference }}</dd></div>
        </dl>
        <div class="grid gap-2" :class="charge_.status !== 'paid' && 'grid-cols-2'">
          <RouterLink :to="rental.tenantById(charge_.tenantId)?.propertyId ? `/landlord/tenants/${charge_.tenantId}` : `/landlord/properties/${charge_.propertyId}`" class="btn-secondary h-11">Open tenant</RouterLink>
          <button v-if="charge_.status !== 'paid'" class="btn-primary h-11" @click="cashFromDetails"><Banknote class="size-4" /> Record cash</button>
        </div>
      </div>
    </BaseModal>

    <!-- All cash payments -->
    <BaseModal v-model="cashHistoryOpen" title="Cash history" width="max-w-lg">
      <div class="-mx-5 -my-5">
        <CashReviewList :items="cashHistory" empty="No cash payments yet." />
      </div>
    </BaseModal>

    <CashPaymentModal :model-value="cashOpen" :tenant-id="cashFor || null" @update:model-value="!$event && (cashFor = null)" />
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
.pay-action-glass { color: #fff; background: rgb(255 255 255 / 0.12); box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.22); }
.pay-action-glass:hover { background: rgb(255 255 255 / 0.18); }
.pay-ico {
  display: flex;
  width: 2.35rem;
  height: 2.35rem;
  flex-shrink: 0;
  align-items: center;
  justify-content: center;
  border-radius: 0.8rem;
}

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

/* Menu rows */
.menu-item {
  display: flex;
  width: 100%;
  align-items: center;
  gap: 0.75rem;
  border-radius: 0.75rem;
  padding: 0.7rem 0.75rem;
  font-size: 0.9rem;
  font-weight: 500;
  color: var(--color-slate-700);
  transition: background-color 0.12s ease;
}
.menu-item:hover { background: var(--color-slate-50); }
.menu-item:disabled { opacity: 0.45; }
.menu-item-on { color: var(--color-brand-700); background: var(--color-brand-50); }
.menu-ico {
  display: flex;
  width: 2.25rem;
  height: 2.25rem;
  flex-shrink: 0;
  align-items: center;
  justify-content: center;
  border-radius: 0.7rem;
}
</style>
