<script setup>
import { ref } from 'vue'
import { CheckCircle2, Receipt } from '@lucide/vue'
import { useTenant } from '@/composables/useTenant'
import { formatUGX, formatDate, formatPeriod } from '@/utils/format'
import PageHeader from '@/components/PageHeader.vue'
import StatusBadge from '@/components/StatusBadge.vue'
import BaseModal from '@/components/BaseModal.vue'
import EmptyState from '@/components/EmptyState.vue'
import PayRentForm from '@/components/PayRentForm.vue'

const { rental, payments, dues, balance } = useTenant()

const paying = ref(null)
const justPaid = ref(false)

async function onPaid() {
  paying.value = null
  justPaid.value = true
  await Promise.all([rental.reload('payments'), rental.reload('notifications')])
}
</script>

<template>
  <PageHeader title="Payments" subtitle="Pay your rent and see your payment history." />

  <div v-if="justPaid" class="card mb-6 flex items-center gap-3 border-emerald-200 p-4">
    <CheckCircle2 class="size-5 text-emerald-600" />
    <p class="text-sm text-slate-700">Payment successful. You'll also get a confirmation notification.</p>
  </div>

  <!-- Outstanding -->
  <section class="card mb-6">
    <div class="flex items-center justify-between border-b border-slate-100 px-5 py-4">
      <h2 class="text-sm font-semibold text-slate-900">Outstanding</h2>
      <p class="text-sm text-slate-500">Total <span class="font-semibold text-slate-900">{{ formatUGX(balance) }}</span></p>
    </div>
    <ul v-if="dues.length" class="divide-y divide-slate-100">
      <li v-for="d in dues" :key="d.id" class="flex flex-col gap-3 px-5 py-4 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <p class="text-sm font-medium text-slate-900">
            {{ formatPeriod(d.period) }} rent <StatusBadge :status="d.status" class="ml-1 align-middle" />
          </p>
          <p class="mt-0.5 text-sm text-slate-500">Due {{ formatDate(d.dueDate) }}</p>
        </div>
        <div class="flex items-center gap-4">
          <div class="text-right"><p class="text-base font-semibold text-slate-900">{{ formatUGX(d.balance) }}</p><p v-if="d.amountPaid" class="text-xs text-slate-500">{{ formatUGX(d.amountPaid) }} of {{ formatUGX(d.amount) }} paid</p></div>
          <button class="btn-primary" @click="paying = d">Pay now</button>
        </div>
      </li>
    </ul>
    <EmptyState v-else :icon="CheckCircle2" title="Nothing to pay" text="You're fully up to date." />
  </section>

  <!-- History -->
  <section class="card overflow-hidden">
    <div class="border-b border-slate-100 px-5 py-4">
      <h2 class="text-sm font-semibold text-slate-900">Payment history</h2>
    </div>
    <div class="overflow-x-auto">
      <table v-if="payments.length" class="min-w-full divide-y divide-slate-100">
        <thead>
          <tr>
            <th class="table-head">Period</th>
            <th class="table-head">Amount</th>
            <th class="table-head">Due</th>
            <th class="table-head">Paid on</th>
            <th class="table-head">Method</th>
            <th class="table-head">Status</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100">
          <tr v-for="p in payments" :key="p.id">
            <td class="table-cell font-medium text-slate-900">{{ formatPeriod(p.period) }}</td>
            <td class="table-cell">{{ formatUGX(p.amount) }}</td>
            <td class="table-cell">{{ formatDate(p.dueDate) }}</td>
            <td class="table-cell">{{ formatDate(p.paidAt) }}</td>
            <td class="table-cell">{{ p.method ?? '—' }}</td>
            <td class="table-cell"><StatusBadge :status="p.status" /></td>
          </tr>
        </tbody>
      </table>
      <EmptyState v-else :icon="Receipt" title="No payments yet" />
    </div>
  </section>

  <BaseModal :model-value="Boolean(paying)" title="Pay rent" @update:model-value="!$event && (paying = null)">
    <PayRentForm v-if="paying" :payment="paying" @paid="onPaid" @cancel="paying = null" />
  </BaseModal>
</template>
