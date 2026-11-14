<script setup>
import { computed, ref } from 'vue'
import { ArrowLeft, Phone, Banknote, Smartphone, DoorOpen, CalendarClock, Wallet, ChevronRight } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { timeLeft } from '@/composables/useRentAnalytics'
import { formatUGX, formatDate, formatPeriod, daysUntil } from '@/utils/format'
import CashPaymentModal from '@/components/CashPaymentModal.vue'

// Mini account page for a tenant without a smartphone: just the essentials, run by the landlord.
const props = defineProps({ id: String })
const rental = useRentalStore()
const showCash = ref(false)

const t = computed(() => rental.tenantById(props.id))
const house = computed(() => t.value && rental.propertyById(t.value.propertyId))
const dues = computed(() => (t.value ? rental.duesForTenant(t.value.id) : []))
const owed = computed(() => dues.value.reduce((s, p) => s + p.balance, 0))
const history = computed(() => (t.value ? rental.paymentsForTenant(t.value.id).slice(0, 4) : []))
const lastPaid = computed(() => (t.value ? rental.paymentsForTenant(t.value.id).find((p) => p.status === 'paid') : null))
const pendingCash = computed(() => (t.value ? rental.cashForTenant(t.value.id).filter((c) => c.status === 'pending') : []))
const left = computed(() => (t.value?.leaseEnd ? daysUntil(t.value.leaseEnd) : null))
const initials = (name) => (name ?? '?').split(' ').map((p) => p[0]).slice(0, 2).join('').toUpperCase()
</script>

<template>
  <div class="mx-auto max-w-lg">
    <RouterLink to="/landlord/managed" class="mb-4 inline-flex items-center gap-1.5 py-1 text-sm font-medium text-slate-500 hover:text-slate-900">
      <ArrowLeft class="size-4" /> Managed accounts
    </RouterLink>

    <div v-if="!t" class="py-20 text-center text-sm text-slate-500">Tenant not found.</div>

    <template v-else>
      <!-- Account card -->
      <section class="page-hero rise px-5 py-6">
        <div class="flex items-center gap-3.5">
          <span class="flex size-14 shrink-0 items-center justify-center rounded-2xl bg-white/15 text-lg font-bold ring-1 ring-white/25">{{ initials(t.name) }}</span>
          <div class="min-w-0">
            <p class="truncate text-xl font-semibold">{{ t.name }}</p>
            <p class="truncate text-sm text-white/75">{{ t.phone || 'No phone number' }} · no smartphone</p>
          </div>
        </div>
        <p class="mt-6 text-sm text-white/75">{{ owed ? 'Balance due' : 'Balance' }}</p>
        <p class="mt-0.5 text-4xl font-bold tracking-tight tabular-nums">{{ formatUGX(owed) }}</p>
        <p class="mt-1 text-sm text-white/70">{{ owed ? `${dues.length} unpaid month${dues.length === 1 ? '' : 's'}` : 'All paid up' }}</p>
        <div class="mt-6 grid grid-cols-2 gap-2.5">
          <button class="hero-btn hero-btn-solid" @click="showCash = true"><Banknote class="size-4" /> Record cash</button>
          <a v-if="t.phone" :href="`tel:${t.phone}`" class="hero-btn hero-btn-glass"><Phone class="size-4" /> Call</a>
          <RouterLink v-else :to="`/landlord/properties/${t.propertyId}`" class="hero-btn hero-btn-glass">Details</RouterLink>
        </div>
      </section>

      <p v-if="pendingCash.length" class="mt-4 rounded-xl border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800">
        {{ formatUGX(pendingCash.reduce((s, c) => s + c.amount, 0)) }} in cash is waiting for confirmation.
      </p>

      <!-- Few key details -->
      <div class="sheet rise mt-5" style="--d: 60ms">
        <dl class="divide-y divide-slate-100 text-sm">
          <div class="flex items-center gap-3 px-5 py-4">
            <span class="icon-disc disc-brand size-9"><DoorOpen class="size-4" /></span>
            <dt class="flex-1 text-slate-500">Room</dt>
            <dd class="text-right font-medium text-slate-900">{{ rental.placeName(t.propertyId) }}</dd>
          </div>
          <div class="flex items-center gap-3 px-5 py-4">
            <span class="icon-disc disc-emerald size-9"><Wallet class="size-4" /></span>
            <dt class="flex-1 text-slate-500">Rent</dt>
            <dd class="font-medium text-slate-900">{{ formatUGX(house?.rent) }} a month</dd>
          </div>
          <div class="flex items-center gap-3 px-5 py-4">
            <span class="icon-disc size-9" :class="left !== null && left <= 30 ? 'disc-amber' : 'disc-sky'"><CalendarClock class="size-4" /></span>
            <dt class="flex-1 text-slate-500">Stay</dt>
            <dd class="text-right">
              <p class="font-medium text-slate-900">{{ timeLeft(left) }}</p>
              <p v-if="t.leaseEnd" class="text-xs text-slate-500">ends {{ formatDate(t.leaseEnd) }}</p>
            </dd>
          </div>
          <div class="flex items-center gap-3 px-5 py-4">
            <span class="icon-disc disc-slate size-9"><Banknote class="size-4" /></span>
            <dt class="flex-1 text-slate-500">Last paid</dt>
            <dd class="text-right font-medium text-slate-900">{{ lastPaid ? formatPeriod(lastPaid.period) : 'Not yet' }}</dd>
          </div>
        </dl>
      </div>

      <!-- Last few months -->
      <h2 class="section-title mt-6">Recent months</h2>
      <div class="sheet">
        <ul v-if="history.length" class="divide-y divide-slate-100">
          <li v-for="p in history" :key="p.id" class="flex items-center justify-between gap-3 px-5 py-3.5 text-sm">
            <span class="font-medium text-slate-900">{{ formatPeriod(p.period) }}</span>
            <span class="flex items-center gap-2">
              <span class="tabular-nums text-slate-700">{{ formatUGX(p.status === 'paid' ? p.amount : p.balance) }}</span>
              <span class="rounded-md px-2 py-0.5 text-xs font-semibold" :class="p.status === 'paid' ? 'bg-emerald-50 text-emerald-700' : p.status === 'overdue' ? 'bg-red-50 text-red-700' : 'bg-amber-50 text-amber-700'">
                {{ p.status === 'paid' ? 'Paid' : p.status === 'overdue' ? 'Overdue' : 'Due' }}
              </span>
            </span>
          </li>
        </ul>
        <p v-else class="px-5 py-8 text-center text-sm text-slate-500">No rent charges yet.</p>
      </div>

      <!-- Got a smartphone -->
      <RouterLink :to="`/landlord/properties/${t.propertyId}`" class="sheet mt-5 flex items-center gap-3.5 px-5 py-4 transition hover:bg-slate-50">
        <span class="icon-disc disc-sky"><Smartphone class="size-5" /></span>
        <span class="min-w-0 flex-1">
          <span class="block font-medium text-slate-900">Got a smartphone?</span>
          <span class="block text-xs text-slate-500">Give them app access from the room page</span>
        </span>
        <ChevronRight class="size-4 text-slate-300" />
      </RouterLink>

      <CashPaymentModal v-model="showCash" :tenant-id="t.id" />
    </template>
  </div>
</template>
