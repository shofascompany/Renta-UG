<script setup>
import { computed, reactive, ref } from 'vue'
import { CalendarPlus, CheckCircle2, Banknote } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { formatUGX, formatDate, formatPeriod } from '@/utils/format'
import PageHeader from '@/components/PageHeader.vue'
import StatusBadge from '@/components/StatusBadge.vue'
import StatCard from '@/components/StatCard.vue'
import BaseModal from '@/components/BaseModal.vue'
import CashPaymentModal from '@/components/CashPaymentModal.vue'

const rental = useRentalStore()
const status = ref('all')
const flash = ref('')

const list = computed(() =>
  rental.payments
    .filter((p) => status.value === 'all' || p.status === status.value)
    .sort((a, b) => b.dueDate.localeCompare(a.dueDate)),
)

const totals = computed(() => ({
  paid: rental.payments.reduce((s, p) => s + p.amountPaid, 0),
  pending: rental.payments.filter((p) => p.status === 'pending').reduce((s, p) => s + p.balance, 0),
  overdue: rental.payments.filter((p) => p.status === 'overdue').reduce((s, p) => s + p.balance, 0),
}))

function showFlash(msg) {
  flash.value = msg
  setTimeout(() => (flash.value = ''), 4000)
}

// ── Create monthly charges ──
const charging = ref(false)
const thisMonth = new Date().toLocaleDateString('en-CA').slice(0, 7)
const charge = reactive({ period: thisMonth, dueDate: `${thisMonth}-05` })
const busy = ref(false)
const error = ref('')

async function createCharges() {
  busy.value = true
  error.value = ''
  try {
    const n = await rental.generateCharges(charge.period, charge.dueDate)
    charging.value = false
    showFlash(n ? `Created ${n} rent charge${n === 1 ? '' : 's'} and notified tenants.` : 'All tenants already have a charge for that month.')
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}

// ── Record cash (applied to the oldest unpaid rent first) ──
const cashFor = ref(null) // tenant id, or '' for 'choose a tenant'
const cashOpen = computed(() => cashFor.value !== null)
</script>

<template>
  <PageHeader title="Payments" subtitle="All rent payments across your properties.">
    <button class="btn-secondary" @click="cashFor = ''"><Banknote class="size-4" /> Record cash payment</button>
    <button class="btn-primary" @click="charging = true"><CalendarPlus class="size-4" /> Create rent charges</button>
  </PageHeader>

  <p v-if="flash" class="card mb-6 flex items-center gap-2 border-emerald-200 p-4 text-sm text-slate-700">
    <CheckCircle2 class="size-5 text-emerald-600" /> {{ flash }}
  </p>

  <div class="mb-6 grid gap-4 sm:grid-cols-3">
    <StatCard label="Total collected" :value="formatUGX(totals.paid)" />
    <StatCard label="Pending" :value="formatUGX(totals.pending)" :tone="totals.pending ? 'warn' : 'default'" />
    <StatCard label="Overdue" :value="formatUGX(totals.overdue)" :tone="totals.overdue ? 'danger' : 'default'" />
  </div>

  <div class="mb-4 inline-flex rounded-lg border border-slate-200 p-0.5 text-sm">
    <button
      v-for="f in ['all', 'paid', 'pending', 'overdue']"
      :key="f"
      class="rounded-md px-3 py-1.5 font-medium capitalize transition-colors"
      :class="status === f ? 'bg-slate-100 text-slate-900' : 'text-slate-500 hover:text-slate-700'"
      @click="status = f"
    >
      {{ f }}
    </button>
  </div>

  <section class="card overflow-hidden">
    <div class="overflow-x-auto">
      <table v-if="list.length" class="min-w-full divide-y divide-slate-100">
        <thead>
          <tr>
            <th class="table-head">Tenant</th>
            <th class="table-head">Property</th>
            <th class="table-head">Period</th>
            <th class="table-head">Amount</th>
            <th class="table-head">Due</th>
            <th class="table-head">Paid on</th>
            <th class="table-head">Method</th>
            <th class="table-head">Status</th>
            <th class="table-head"></th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100">
          <tr v-for="p in list" :key="p.id">
            <td class="table-cell font-medium text-slate-900">{{ rental.tenantById(p.tenantId)?.name }}</td>
            <td class="table-cell">{{ rental.propertyById(p.propertyId)?.name ?? '—' }}</td>
            <td class="table-cell">{{ formatPeriod(p.period) }}</td>
            <td class="table-cell">
              {{ formatUGX(p.amount) }}
              <p v-if="p.status !== 'paid' && p.amountPaid" class="text-xs text-amber-700">{{ formatUGX(p.balance) }} left</p>
            </td>
            <td class="table-cell">{{ formatDate(p.dueDate) }}</td>
            <td class="table-cell">{{ formatDate(p.paidAt) }}</td>
            <td class="table-cell">{{ p.method ?? '—' }}</td>
            <td class="table-cell"><StatusBadge :status="p.status" /></td>
            <td class="table-cell text-right">
              <button v-if="p.status !== 'paid'" class="btn-ghost px-2 py-1 text-xs" @click="cashFor = p.tenantId">Record cash</button>
            </td>
          </tr>
        </tbody>
      </table>
      <p v-else class="px-5 py-10 text-center text-sm text-slate-500">
        {{ rental.payments.length ? 'No payments with this status.' : 'No payments yet. Use "Create rent charges" to bill your tenants for a month.' }}
      </p>
    </div>
  </section>

  <BaseModal v-model="charging" title="Create rent charges">
    <form class="space-y-4" @submit.prevent="createCharges">
      <p class="text-sm text-slate-600">
        Bills every current tenant their property's monthly rent. Tenants get a notification and can pay from their dashboard.
      </p>
      <div class="grid grid-cols-2 gap-4">
        <div>
          <label class="label" for="cperiod">Month</label>
          <input id="cperiod" v-model="charge.period" type="month" class="input" required />
        </div>
        <div>
          <label class="label" for="cdue">Due date</label>
          <input id="cdue" v-model="charge.dueDate" type="date" class="input" required />
        </div>
      </div>
      <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
      <div class="flex justify-end gap-2 pt-2">
        <button type="button" class="btn-secondary" @click="charging = false">Cancel</button>
        <button type="submit" class="btn-primary" :disabled="busy">{{ busy ? 'Creating…' : 'Create charges' }}</button>
      </div>
    </form>
  </BaseModal>

  <CashPaymentModal :model-value="cashOpen" :tenant-id="cashFor || null" @update:model-value="!$event && (cashFor = null)" />
</template>
