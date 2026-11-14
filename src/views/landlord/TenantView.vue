<script setup>
import { computed, ref } from 'vue'
import { useRouter } from 'vue-router'
import {
  Phone, Mail, DoorClosed, Wallet, CalendarClock, CalendarDays, Smartphone, UserCog, KeyRound, ReceiptText, ArrowLeft, Link2, LogOut, TriangleAlert,
} from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { formatUGX, formatDate, formatPeriod, daysUntil, timeLeft } from '@/utils/format'
import BaseModal from '@/components/BaseModal.vue'
import ConnectCodeModal from '@/components/ConnectCodeModal.vue'

// Full page about ONE tenant: who they are, where they live, their rental time and rent.
// Bottom tabs are hidden here (route meta focus); a back button returns to the list.
const props = defineProps({ id: { type: String, required: true } })
const rental = useRentalStore()
const router = useRouter()
const back = () => (window.history.state?.back ? router.back() : router.push('/landlord/tenants'))

const t = computed(() => rental.tenantById(props.id) ?? null)
const house = computed(() => t.value && rental.propertyById(t.value.propertyId))
const dues = computed(() => (t.value ? rental.duesForTenant(t.value.id) : []))
const owed = computed(() => dues.value.reduce((s, p) => s + p.balance, 0))
const overdue = computed(() => dues.value.some((p) => p.status === 'overdue'))
const paid = computed(() => (t.value ? rental.paymentsForTenant(t.value.id).filter((p) => p.amountPaid).reduce((s, p) => s + p.amountPaid, 0) : 0))
const lastPaid = computed(() => (t.value ? rental.paymentsForTenant(t.value.id).find((p) => p.status === 'paid') : null))
const left = computed(() => (t.value?.leaseEnd ? daysUntil(t.value.leaseEnd) : null))
const months = computed(() => {
  if (!t.value?.leaseStart || !t.value?.leaseEnd) return null
  const s = new Date(t.value.leaseStart)
  const e = new Date(t.value.leaseEnd)
  return Math.max(1, Math.round((e - s) / (30.44 * 86400000)))
})
const used = computed(() => {
  if (!t.value?.leaseStart || !t.value?.leaseEnd) return null
  const total = daysUntil(t.value.leaseEnd) - daysUntil(t.value.leaseStart)
  return total > 0 ? Math.min(100, Math.max(0, Math.round(((total - left.value) / total) * 100))) : 100
})
const account = computed(() =>
  !t.value ? null : t.value.userId
    ? { text: 'Uses the Renta app', icon: Smartphone, cls: 'bg-emerald-50 text-emerald-700' }
    : t.value.managedByLandlord
      ? { text: 'No smartphone · managed by you', icon: UserCog, cls: 'bg-slate-100 text-slate-700' }
      : { text: 'Not connected yet', icon: KeyRound, cls: 'bg-amber-50 text-amber-700' },
)
const initials = (name) => (name ?? '?').split(' ').map((p) => p[0]).slice(0, 2).join('').toUpperCase()

// ── Connect (only while not connected) ──
const showCode = ref(false)
const accessOpen = ref(false)
const busy = ref(false)
const error = ref('')
const done = ref('')
function connect() {
  error.value = ''
  if (t.value.managedByLandlord) accessOpen.value = true // no smartphone → give app access by phone number
  else showCode.value = true // has a smartphone → 20-minute connection code
}
async function giveAccess() {
  busy.value = true
  error.value = ''
  try {
    const res = await rental.giveAppAccess(t.value.id)
    accessOpen.value = false
    done.value = `Connected. ${t.value.name.split(' ')[0]} can now sign in with ${res.phone}.`
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}

// ── End tenancy (asks first) ──
const endOpen = ref(false)
async function endTenancy() {
  busy.value = true
  error.value = ''
  try {
    await rental.endTenancy(t.value.id)
    endOpen.value = false
    router.replace('/landlord/tenants')
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}</script>

<template>
  <div class="mx-auto max-w-lg">
    <!-- Back -->
    <div class="sticky top-0 z-20 -mx-4 mb-4 flex items-center gap-2 bg-[var(--color-slate-50)]/85 px-4 py-2 backdrop-blur-lg sm:static sm:mx-0 sm:bg-transparent sm:px-0 sm:backdrop-blur-none">
      <button type="button" class="flex h-11 items-center gap-1.5 rounded-2xl bg-white pr-4 pl-3 text-sm font-semibold text-slate-700 shadow-sm ring-1 ring-slate-200 active:scale-95" @click="back">
        <ArrowLeft class="size-[1.1rem]" /> Back
      </button>
    </div>

    <div v-if="!t" class="py-20 text-center text-sm text-slate-500">Tenant not found.</div>

    <div v-else class="space-y-5 pb-6">      <!-- Who -->
      <div class="relative overflow-hidden rounded-3xl px-5 pt-6 pb-5 text-center text-white" style="background: linear-gradient(140deg, #14918a, #0f766e 50%, #0a3b38)">
        <div class="mx-auto flex size-16 items-center justify-center rounded-2xl bg-white/15 text-xl font-bold ring-1 ring-white/25">{{ initials(t.name) }}</div>
        <p class="mt-3 text-xl font-semibold">{{ t.name }}</p>
        <p class="mt-0.5 text-sm text-white/75">{{ rental.placeName(t.propertyId) }}</p>
        <span class="mt-3 inline-flex items-center gap-1.5 rounded-full bg-white/15 px-3 py-1 text-xs font-medium ring-1 ring-white/20">
          <component :is="account.icon" class="size-3.5" /> {{ account.text }}
        </span>
      </div>

      <!-- Money -->
      <div class="grid grid-cols-2 gap-3">
        <div class="rounded-2xl p-4" :class="owed ? (overdue ? 'bg-red-50' : 'bg-amber-50') : 'bg-emerald-50'">
          <p class="text-xs font-medium" :class="owed ? (overdue ? 'text-red-700' : 'text-amber-700') : 'text-emerald-700'">{{ owed ? (overdue ? 'Overdue' : 'Balance due') : 'Paid up' }}</p>
          <p class="mt-1 text-lg font-bold text-slate-900 tabular-nums">{{ formatUGX(owed) }}</p>
        </div>
        <div class="rounded-2xl bg-slate-50 p-4">
          <p class="text-xs font-medium text-slate-500">Paid so far</p>
          <p class="mt-1 text-lg font-bold text-slate-900 tabular-nums">{{ formatUGX(paid) }}</p>
        </div>
      </div>

      <!-- Rental time -->
      <div class="rounded-2xl border border-slate-200 p-4">
        <div class="flex items-center justify-between gap-3">
          <p class="flex items-center gap-2 text-sm font-medium text-slate-700"><CalendarClock class="size-4 text-slate-400" /> Rental time</p>
          <p class="text-sm font-semibold" :class="left !== null && left <= 30 ? 'text-amber-700' : 'text-slate-900'">{{ timeLeft(left) }}</p>
        </div>
        <div v-if="used !== null" class="mt-3 h-2 overflow-hidden rounded-full bg-slate-100">
          <div class="h-full rounded-full bg-gradient-to-r from-teal-400 to-teal-700" :style="{ width: `${used}%` }" />
        </div>
        <div class="mt-2 flex justify-between text-xs text-slate-500">
          <span>From {{ formatDate(t.leaseStart) }}</span>
          <span>{{ months ? `${months} month${months === 1 ? '' : 's'}` : '' }}</span>
          <span>To {{ formatDate(t.leaseEnd) }}</span>
        </div>
      </div>

      <!-- Details -->
      <dl class="divide-y divide-slate-100 text-sm">
        <div class="flex items-center gap-3 py-3">
          <Phone class="size-4 text-slate-400" /><dt class="flex-1 text-slate-500">Phone</dt>
          <dd><a v-if="t.phone" :href="`tel:${t.phone}`" class="font-medium text-brand-700">{{ t.phone }}</a><span v-else class="text-slate-400">—</span></dd>
        </div>
        <div v-if="t.email && !t.email.endsWith('@phone-signin.example.com')" class="flex items-center gap-3 py-3">
          <Mail class="size-4 text-slate-400" /><dt class="flex-1 text-slate-500">Email</dt>
          <dd class="min-w-0 truncate"><a :href="`mailto:${t.email}`" class="font-medium text-slate-900">{{ t.email }}</a></dd>
        </div>
        <div class="flex items-center gap-3 py-3">
          <DoorClosed class="size-4 text-slate-400" /><dt class="flex-1 text-slate-500">Lives in</dt>
          <dd class="text-right font-medium text-slate-900">{{ rental.placeName(t.propertyId) }}</dd>
        </div>
        <div class="flex items-center gap-3 py-3">
          <Wallet class="size-4 text-slate-400" /><dt class="flex-1 text-slate-500">Rent</dt>
          <dd class="font-medium text-slate-900">{{ formatUGX(house?.rent) }} a month</dd>
        </div>
        <div class="flex items-center gap-3 py-3">
          <ReceiptText class="size-4 text-slate-400" /><dt class="flex-1 text-slate-500">Last month paid</dt>
          <dd class="font-medium text-slate-900">{{ lastPaid ? formatPeriod(lastPaid.period) : 'Not yet' }}</dd>
        </div>
        <div class="flex items-center gap-3 py-3">
          <CalendarDays class="size-4 text-slate-400" /><dt class="flex-1 text-slate-500">Tenant since</dt>
          <dd class="font-medium text-slate-900">{{ formatDate(t.leaseStart ?? t.createdAt) }}</dd>
        </div>
      </dl>
    
      <p v-if="done" class="rounded-2xl border border-emerald-200 bg-emerald-50 p-3.5 text-sm text-emerald-800">{{ done }}</p>
      <p v-if="error && !endOpen && !accessOpen" class="text-sm text-red-600">{{ error }}</p>

      <!-- Actions -->
      <div class="grid gap-2.5 pt-1">
        <button v-if="!t.userId" type="button" class="btn-primary h-12 w-full rounded-2xl text-[15px]" @click="connect">
          <Link2 class="size-5" /> Connect tenant
        </button>
        <button type="button" class="btn-secondary h-12 w-full rounded-2xl border-red-200 text-[15px] text-red-600 hover:bg-red-50" @click="endOpen = true; error = ''">
          <LogOut class="size-5" /> End tenancy
        </button>
      </div>
    </div>

    <template v-if="t">
      <ConnectCodeModal v-if="showCode" v-model="showCode" :tenant-id="t.id" />

      <!-- Connect a tenant without a smartphone: their phone number becomes their login -->
      <BaseModal v-model="accessOpen" title="Connect tenant" width="max-w-md">
        <div class="space-y-4">
          <p class="text-sm leading-relaxed text-slate-600">
            {{ t.name }} will sign in to Renta with <strong class="text-slate-900">{{ t.phone || 'their phone number' }}</strong>, then add an email and choose a password. No code is needed.
          </p>
          <p v-if="!t.phone" class="rounded-xl bg-amber-50 p-3 text-sm text-amber-800">Add a phone number for this tenant first.</p>
          <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
          <div class="flex justify-end gap-2">
            <button type="button" class="btn-secondary" @click="accessOpen = false">Cancel</button>
            <button type="button" class="btn-primary" :data-busy="busy" :disabled="busy || !t.phone" @click="giveAccess">{{ busy ? 'Connecting…' : 'Connect' }}</button>
          </div>
        </div>
      </BaseModal>

      <!-- Confirm end of tenancy -->
      <BaseModal v-model="endOpen" title="End tenancy?" width="max-w-md">
        <div class="space-y-4">
          <div class="flex items-start gap-3.5 rounded-2xl bg-red-50 p-4">
            <span class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-red-100 text-red-600"><TriangleAlert class="size-5" /></span>
            <p class="text-sm leading-relaxed text-red-800">
              <strong>{{ t.name }}</strong> will move out of <strong>{{ rental.placeName(t.propertyId) }}</strong>. It becomes vacant, and their full history is kept in Records.
            </p>
          </div>
          <p v-if="owed" class="text-sm text-slate-600">They still owe <strong class="text-slate-900">{{ formatUGX(owed) }}</strong>. This stays on their record.</p>
          <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
          <div class="flex justify-end gap-2">
            <button type="button" class="btn-secondary" @click="endOpen = false">Keep tenant</button>
            <button type="button" class="btn bg-red-600 text-white hover:bg-red-700" :data-busy="busy" :disabled="busy" @click="endTenancy">{{ busy ? 'Ending…' : 'End tenancy' }}</button>
          </div>
        </div>
      </BaseModal>
    </template>
  </div>
</template>