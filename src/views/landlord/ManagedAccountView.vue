<script setup>
import { computed, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ArrowLeft, Phone, Banknote, Smartphone, DoorOpen, CalendarClock, Wallet, ChevronRight, Trash2, LogOut } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { timeLeft } from '@/composables/useRentAnalytics'
import { formatUGX, formatDate, formatPeriod, daysUntil } from '@/utils/format'
import RecordPaymentModal from '@/components/RecordPaymentModal.vue'
import DeleteTenantModal from '@/components/DeleteTenantModal.vue'
import BaseModal from '@/components/BaseModal.vue'

// Mini account page for a tenant without a smartphone: just the essentials, run by the landlord.
const props = defineProps({ id: String })
const rental = useRentalStore()
const router = useRouter()
const showCash = ref(false)
const deleteOpen = ref(false)

// End tenancy instead (history kept in Records)
const endOpen = ref(false)
const ending = ref(false)
const endError = ref('')
async function endTenancy() {
  ending.value = true
  endError.value = ''
  try {
    await rental.endTenancy(t.value.id)
    endOpen.value = false
    router.replace('/landlord/managed')
  } catch (e) {
    endError.value = e.message
  } finally {
    ending.value = false
  }
}

const t = computed(() => rental.tenantById(props.id))
const house = computed(() => t.value && rental.propertyById(t.value.propertyId))
const dues = computed(() => (t.value ? rental.duesForTenant(t.value.id) : []))
const owed = computed(() => dues.value.reduce((s, p) => s + p.balance, 0))
const pay = computed(() => (t.value ? rental.payStateFor(t.value.id) : null)) // Paid / Part paid / Not paid
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
        <div class="mt-6 flex items-center gap-2">
          <span class="hero-pay rounded-full px-3 py-1 text-xs font-bold" :class="`hero-pay-${pay?.key}`">{{ pay?.label }}</span>
          <span class="text-sm text-white/80">{{ pay?.detail }}</span>
        </div>
        <p class="mt-2 text-sm text-white/75">{{ pay?.key === 'paid' ? 'Nothing to pay' : 'To pay now' }}</p>
        <p class="mt-0.5 text-4xl font-bold tracking-tight tabular-nums">{{ formatUGX(pay?.owed ?? owed) }}</p>
        <p class="mt-1 text-sm text-white/70">{{ dues.length ? `${dues.length} unpaid month${dues.length === 1 ? '' : 's'}` : pay?.key === 'paid' ? 'Paid' : 'Not paid yet' }}</p>
        <div class="mt-6 grid grid-cols-2 gap-2.5">
          <button class="hero-btn hero-btn-solid" @click="showCash = true"><Banknote class="size-4" /> Record payment</button>
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

      <!-- Remove -->
      <div class="mt-5 grid gap-2.5 sm:grid-cols-2">
        <button type="button" class="btn-secondary h-12 rounded-2xl border-red-200 text-red-600 hover:bg-red-50" @click="endOpen = true"><LogOut class="size-4.5" /> End tenancy</button>
        <button type="button" class="btn h-12 rounded-2xl bg-red-600 text-white hover:bg-red-700" @click="deleteOpen = true"><Trash2 class="size-4.5" /> Delete tenant</button>
      </div>

      <RecordPaymentModal v-model="showCash" :tenant-id="t.id" />
      <DeleteTenantModal v-model="deleteOpen" :tenant="t" @deleted="router.replace('/landlord/managed')" @end-instead="endOpen = true" />
      <BaseModal v-model="endOpen" title="End tenancy?" width="max-w-md">
        <div class="space-y-4">
          <p class="text-sm leading-relaxed text-slate-600">
            <strong class="text-slate-900">{{ t.name }}</strong> moves out of <strong class="text-slate-900">{{ rental.placeName(t.propertyId) }}</strong>. The room becomes empty and their payment history is kept in Records.
          </p>
          <p v-if="owed" class="text-sm text-slate-600">They still owe <strong class="text-slate-900">{{ formatUGX(owed) }}</strong>. This stays on their record.</p>
          <p v-if="endError" class="text-sm text-red-600">{{ endError }}</p>
          <div class="flex justify-end gap-2">
            <button type="button" class="btn-secondary" @click="endOpen = false">Keep tenant</button>
            <button type="button" class="btn bg-red-600 text-white hover:bg-red-700" :data-busy="ending" :disabled="ending" @click="endTenancy">{{ ending ? 'Ending…' : 'End tenancy' }}</button>
          </div>
        </div>
      </BaseModal>
    </template>
  </div>
</template>

<style scoped>
.hero-pay { --color-white: #fff; color: #fff; }
.hero-pay-paid { background: #059669; }
.hero-pay-part { background: #d97706; }
.hero-pay-unpaid { background: #dc2626; }
</style>
