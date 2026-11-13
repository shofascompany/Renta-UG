<script setup>
import { computed, ref } from 'vue'
import { Wallet, CalendarClock, Bell, MapPin, BedDouble, ArrowRight, CheckCircle2, Hourglass } from '@lucide/vue'
import { useTenant } from '@/composables/useTenant'
import { formatUGX, formatDate, formatPeriod, daysUntil } from '@/utils/format'
import PageHeader from '@/components/PageHeader.vue'
import StatCard from '@/components/StatCard.vue'
import StatusBadge from '@/components/StatusBadge.vue'
import NotificationItem from '@/components/NotificationItem.vue'
import BaseModal from '@/components/BaseModal.vue'
import PayRentForm from '@/components/PayRentForm.vue'
import PushPrompt from '@/components/PushPrompt.vue'

const { rental, tenant, property, payments, dues, notifications, unread, balance } = useTenant()

const firstName = computed(() => tenant.value?.name.split(' ')[0] ?? '')
const nextDue = computed(() => dues.value[0])
const daysLeft = computed(() => (tenant.value?.leaseEnd ? daysUntil(tenant.value.leaseEnd) : null))
const leaseHint = computed(() => (daysLeft.value === null ? 'Not set' : daysLeft.value < 0 ? 'Ended' : `${daysLeft.value} days left`))
const endingSoon = computed(() => daysLeft.value !== null && daysLeft.value >= 0 && daysLeft.value <= 7)

const paying = ref(null)
async function onPaid() {
  paying.value = null
  await Promise.all([rental.reload('payments'), rental.reload('notifications')])
}

const greeting = (() => {
  const h = new Date().getHours()
  return h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening'
})()
</script>

<template>
  <PageHeader :title="`${greeting}, ${firstName}`" subtitle="Here's what's happening with your rental." />

  <PushPrompt class="mb-6" />

  <!-- Last week of the stay -->
  <div v-if="endingSoon" class="card mb-6 flex items-start gap-4 border-amber-200 bg-amber-50/40 p-5">
    <div class="flex size-10 shrink-0 items-center justify-center rounded-full bg-amber-100 text-amber-700">
      <Hourglass class="size-5" />
    </div>
    <div>
      <p class="text-sm font-medium text-slate-900">
        {{ daysLeft === 0 ? 'Your stay ends today' : daysLeft === 1 ? 'Your stay ends tomorrow' : `${daysLeft} days left in your stay` }}
      </p>
      <p class="mt-0.5 text-sm text-slate-600">
        Your lease at {{ property?.name }} ends on {{ formatDate(tenant.leaseEnd) }}. Prepare your payment to renew, or talk to your landlord about your plans.
      </p>
    </div>
  </div>

  <!-- Rent due banner -->
  <div
    v-if="nextDue"
    class="card mb-6 flex flex-col gap-4 p-5 sm:flex-row sm:items-center sm:justify-between"
    :class="nextDue.status === 'overdue' ? 'border-red-200' : 'border-brand-200'"
  >
    <div class="flex items-start gap-4">
      <div
        class="flex size-10 shrink-0 items-center justify-center rounded-full"
        :class="nextDue.status === 'overdue' ? 'bg-red-50 text-red-600' : 'bg-brand-50 text-brand-600'"
      >
        <Wallet class="size-5" />
      </div>
      <div>
        <p class="text-sm font-medium text-slate-900">
          {{ formatPeriod(nextDue.period) }} rent
          <StatusBadge :status="nextDue.status" class="ml-1 align-middle" />
        </p>
        <p class="mt-0.5 text-sm text-slate-500">{{ formatUGX(nextDue.balance) }}<template v-if="nextDue.amountPaid"> left of {{ formatUGX(nextDue.amount) }}</template> · due {{ formatDate(nextDue.dueDate) }}</p>
      </div>
    </div>
    <button class="btn-primary" @click="paying = nextDue">Pay now</button>
  </div>
  <div v-else class="card mb-6 flex items-center gap-3 border-emerald-200 p-5">
    <CheckCircle2 class="size-5 text-emerald-600" />
    <p class="text-sm text-slate-700">You're all paid up. Nice work!</p>
  </div>

  <!-- Stats -->
  <div class="mb-6 grid grid-cols-2 gap-4 lg:grid-cols-3">
    <StatCard label="Balance due" :value="formatUGX(balance)" :icon="Wallet" :tone="balance ? 'warn' : 'default'" />
    <StatCard label="Lease ends" :value="formatDate(tenant?.leaseEnd)" :hint="leaseHint" :icon="CalendarClock" :tone="endingSoon ? 'warn' : 'default'" />
    <StatCard label="Notifications" :value="unread.length" hint="Unread" :icon="Bell" />
  </div>

  <div class="grid gap-6 lg:grid-cols-3">
    <section class="card lg:col-span-2">
      <div class="flex items-center justify-between border-b border-slate-100 px-5 py-4">
        <h2 class="text-sm font-semibold text-slate-900">Latest notifications</h2>
        <RouterLink to="/tenant/notifications" class="inline-flex items-center gap-1 text-sm font-medium text-brand-600 hover:text-brand-700">
          View all <ArrowRight class="size-3.5" />
        </RouterLink>
      </div>
      <p v-if="!notifications.length" class="px-5 py-8 text-center text-sm text-slate-500">No notifications yet.</p>
      <div class="divide-y divide-slate-100">
        <NotificationItem v-for="n in notifications.slice(0, 5)" :key="n.id" :notification="n" compact @read="rental.markNotificationRead" />
      </div>
    </section>

    <div class="space-y-6">
      <section v-if="property" class="card p-5">
        <h2 class="text-sm font-semibold text-slate-900">My home</h2>
        <p class="mt-3 text-base font-medium text-slate-900">{{ property.name }}</p>
        <p class="mt-1 flex items-center gap-1.5 text-sm text-slate-500"><MapPin class="size-3.5" /> {{ property.location }}</p>
        <p class="mt-1 flex items-center gap-1.5 text-sm text-slate-500"><BedDouble class="size-3.5" /> {{ property.bedrooms }} bed · {{ property.bathrooms }} bath · {{ property.type }}</p>
        <dl class="mt-4 space-y-2 border-t border-slate-100 pt-4 text-sm">
          <div class="flex justify-between"><dt class="text-slate-500">Monthly rent</dt><dd class="font-medium text-slate-900">{{ formatUGX(property.rent) }}</dd></div>
          <div class="flex justify-between"><dt class="text-slate-500">Lease start</dt><dd class="text-slate-900">{{ formatDate(tenant.leaseStart) }}</dd></div>
          <div class="flex justify-between"><dt class="text-slate-500">Lease end</dt><dd class="text-slate-900">{{ formatDate(tenant.leaseEnd) }}</dd></div>
        </dl>
        <RouterLink to="/tenant/home" class="btn-secondary mt-4 w-full">View details</RouterLink>
      </section>

      <section class="card">
        <div class="border-b border-slate-100 px-5 py-4">
          <h2 class="text-sm font-semibold text-slate-900">Recent payments</h2>
        </div>
        <p v-if="!payments.length" class="px-5 py-8 text-center text-sm text-slate-500">No payments yet.</p>
        <ul class="divide-y divide-slate-100">
          <li v-for="p in payments.slice(0, 4)" :key="p.id" class="flex items-center justify-between px-5 py-3">
            <div>
              <p class="text-sm font-medium text-slate-900">{{ formatPeriod(p.period) }}</p>
              <p class="text-xs text-slate-500">{{ formatUGX(p.amount) }}<template v-if="p.method"> · {{ p.method }}</template></p>
            </div>
            <StatusBadge :status="p.status" />
          </li>
        </ul>
      </section>
    </div>
  </div>

  <BaseModal :model-value="Boolean(paying)" title="Pay rent" @update:model-value="!$event && (paying = null)">
    <PayRentForm v-if="paying" :payment="paying" @paid="onPaid" @cancel="paying = null" />
  </BaseModal>
</template>
