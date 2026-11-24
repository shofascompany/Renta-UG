<script setup>
import { computed, ref } from 'vue'
import { Banknote, CheckCircle2, XCircle, Clock, Smartphone, UserCog, MessageSquareQuote, HandCoins, ImageDown, Loader2, Equal } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useAuthStore } from '@/stores/auth'
import { formatUGX, formatDate } from '@/utils/format'
import { useReceiptDownload } from '@/composables/useReceiptDownload'
import BaseModal from './BaseModal.vue'
import PaymentCoverage from './PaymentCoverage.vue'

// Cash payments. Only the tenant's LANDLORD reviews them:
//   reported by a tenant   → the landlord confirms (amount can be corrected) or rejects
//   recorded by a landlord → counts straight away (older entries still waiting can be confirmed by the landlord)
// The main admin only sees them (read only).
defineProps({
  items: { type: Array, required: true },
  showLandlord: Boolean, // main admin: show which landlord
  empty: { type: String, default: 'No cash payments.' },
})

const rental = useRentalStore()
const auth = useAuthStore()

const canReview = (c) => c.status === 'pending' && auth.isLandlord
const tenantOf = (c) => rental.tenantById(c.tenantId)
const houseOf = (c) => {
  const t = tenantOf(c)
  return (rental.propertyById(t?.propertyId ?? t?.lastPropertyId) ? rental.placeName(t?.propertyId ?? t?.lastPropertyId) : undefined)
}
const landlordOf = (c) => rental.landlords.find((l) => l.id === c.landlordId)?.name ?? 'Landlord'
const owedBy = (c) => rental.duesForTenant(c.tenantId).reduce((s, p) => s + p.balance, 0)

// ── Confirm (amount can be corrected) ──
const confirming = ref(null)
const amount = ref('')
const busy = ref(false)
const error = ref('')
const done = ref('')

function startConfirm(c) {
  confirming.value = c
  amount.value = String(c.amount)
  error.value = ''
}
const value = computed(() => Math.round(Number(String(amount.value).replace(/[^\d]/g, '')) || 0))
// What confirming does to the tenant's rental time
const cTenant = computed(() => (confirming.value ? tenantOf(confirming.value) : null))
const cDues = computed(() => (confirming.value ? rental.duesForTenant(confirming.value.tenantId) : []))
const cRent = computed(() => Number(rental.propertyById(cTenant.value?.propertyId)?.rent ?? 0))
const differs = computed(() => confirming.value && value.value && value.value !== confirming.value.amount)

// Receipts as images, like the tenant's
const { saving, saveCash } = useReceiptDownload()

async function confirm() {
  error.value = ''
  if (!value.value) return (error.value = 'Enter the amount received.')
  busy.value = true
  try {
    const r = await rental.confirmCash(confirming.value.id, value.value)
    done.value = `${formatUGX(r.applied)} credited to ${tenantOf(confirming.value)?.name ?? 'the tenant'}${r.months_ahead ? ` (${r.months_ahead} month${r.months_ahead === 1 ? '' : 's'} ahead)` : ''}. They have been notified.`
    confirming.value = null
    setTimeout(() => (done.value = ''), 5000)
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}

// ── Reject ──
const rejecting = ref(null)
const reason = ref('')
function startReject(c) {
  rejecting.value = c
  reason.value = ''
  error.value = ''
}
async function reject() {
  busy.value = true
  error.value = ''
  try {
    await rental.rejectCash(rejecting.value.id, reason.value)
    rejecting.value = null
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}

const NET = { mtn: 'MTN', airtel: 'Airtel' }
const methodText = (c) => (c.method === 'mobile_money' ? `Mobile money${c.network ? ` · ${NET[c.network]}` : ''}` : 'Cash')

const statusStyle = {
  pending: 'bg-amber-50 text-amber-700 ring-amber-600/20',
  confirmed: 'bg-emerald-50 text-emerald-700 ring-emerald-600/15',
  rejected: 'bg-red-50 text-red-700 ring-red-600/15',
}
const statusText = (c) =>
  c.status === 'pending'
    ? auth.isLandlord ? 'Waiting for you' : 'Waiting for the landlord'
    : c.status === 'confirmed'
      ? `Confirmed by ${c.reviewedRole === 'superadmin' ? 'Renta UG' : 'landlord'}`
      : 'Rejected'
</script>

<template>
  <div>
    <p v-if="done" class="mb-3 flex items-center gap-2 rounded-xl border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-800">
      <CheckCircle2 class="size-4 shrink-0" /> {{ done }}
    </p>

    <ul v-if="items.length" class="divide-y divide-slate-100">
      <li v-for="c in items" :key="c.id" class="px-4 py-4 sm:px-5">
        <div class="flex items-start gap-3.5">
          <span class="flex size-10 shrink-0 items-center justify-center rounded-xl" :class="c.method === 'mobile_money' ? 'bg-amber-50 text-amber-700' : 'bg-emerald-50 text-emerald-700'">
            <Smartphone v-if="c.method === 'mobile_money'" class="size-5" />
            <Banknote v-else class="size-5" />
          </span>
          <div class="min-w-0 flex-1">
            <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
              <p class="font-medium text-slate-900">
                {{ tenantOf(c)?.name ?? 'Tenant' }}
                <span
                  v-if="tenantOf(c)?.managedByLandlord"
                  class="ml-1 inline-flex items-center gap-1 rounded-full bg-slate-100 px-2 py-0.5 align-middle text-[11px] font-medium text-slate-600"
                ><UserCog class="size-3" /> No smartphone</span>
              </p>
              <p class="text-right font-semibold text-slate-900 tabular-nums">
                {{ formatUGX(c.status === 'confirmed' ? c.confirmedAmount : c.amount) }}
                <span v-if="c.status === 'pending' && c.submittedRole === 'tenant'" class="block text-[11px] font-medium text-amber-700">tenant says they paid</span>
              </p>
            </div>
            <p class="mt-0.5 truncate text-sm text-slate-500">
              {{ houseOf(c) ?? '—' }}<template v-if="showLandlord"> · {{ landlordOf(c) }}</template>
            </p>
            <p class="mt-1.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-slate-500">
              <span class="font-medium text-slate-700">{{ methodText(c) }}</span>
              <span>Paid {{ formatDate(c.paidOn) }}</span>
              <span class="flex items-center gap-1">
                <component :is="c.submittedRole === 'tenant' ? Smartphone : UserCog" class="size-3.5" />
                {{ c.submittedRole === 'tenant' ? 'Reported by tenant' : 'Recorded by landlord' }}
              </span>
              <span v-if="c.status === 'confirmed' && c.confirmedAmount !== c.amount">Reported {{ formatUGX(c.amount) }}</span>
            </p>
            <p v-if="c.note" class="mt-1.5 rounded-lg bg-slate-50 px-2.5 py-1.5 text-xs text-slate-600">“{{ c.note }}”</p>
            <p v-if="c.status === 'rejected' && c.rejectReason" class="mt-1.5 text-xs text-red-600">Reason: {{ c.rejectReason }}</p>

            <div class="mt-3 flex flex-wrap items-center justify-between gap-2">
              <span class="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium ring-1 ring-inset" :class="statusStyle[c.status]">
                <Clock v-if="c.status === 'pending'" class="size-3.5" />
                <CheckCircle2 v-else-if="c.status === 'confirmed'" class="size-3.5" />
                <XCircle v-else class="size-3.5" />
                {{ statusText(c) }}
              </span>
              <div v-if="canReview(c)" class="flex gap-2">
                <button class="btn-secondary h-9 px-3 text-sm" @click="startReject(c)">Reject</button>
                <button class="btn-primary h-9 px-3 text-sm" @click="startConfirm(c)"><CheckCircle2 class="size-4" /> Confirm</button>
              </div>
              <button v-else-if="c.status === 'confirmed'" type="button" class="rc-btn" :disabled="Boolean(saving)" @click="saveCash(c)">
                <Loader2 v-if="saving === c.id" class="size-3.5 animate-spin" /><ImageDown v-else class="size-3.5" />
                {{ saving === c.id ? 'Saving…' : 'Download receipt' }}
              </button>
            </div>
          </div>
        </div>
      </li>
    </ul>
    <p v-else class="px-5 py-10 text-center text-sm text-slate-500">{{ empty }}</p>

    <!-- Confirm -->
    <BaseModal :model-value="Boolean(confirming)" center title="Confirm payment" width="max-w-lg" @update:model-value="!$event && (confirming = null)">
      <form v-if="confirming" class="space-y-4" @submit.prevent="confirm">
        <!-- What the tenant claims -->
        <div class="claim rounded-2xl p-4">
          <p class="flex items-center gap-2 text-xs font-semibold tracking-[0.12em] text-amber-800 uppercase">
            <MessageSquareQuote class="size-4" /> {{ confirming.submittedRole === 'tenant' ? `${tenantOf(confirming)?.name?.split(' ')[0] ?? 'The tenant'} says they paid` : 'Recorded' }}
          </p>
          <p class="mt-1.5 text-3xl font-bold tracking-tight text-slate-900 tabular-nums">{{ formatUGX(confirming.amount) }}</p>
          <dl class="mt-3 grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
            <div><dt class="text-xs text-slate-500">Tenant</dt><dd class="font-medium text-slate-900">{{ tenantOf(confirming)?.name }}</dd></div>
            <div><dt class="text-xs text-slate-500">How</dt><dd class="font-medium text-slate-900">{{ methodText(confirming) }}</dd></div>
            <div><dt class="text-xs text-slate-500">Date</dt><dd class="font-medium text-slate-900">{{ formatDate(confirming.paidOn) }}</dd></div>
            <div><dt class="text-xs text-slate-500">Unpaid rent now</dt><dd class="font-medium text-slate-900 tabular-nums">{{ formatUGX(owedBy(confirming)) }}</dd></div>
          </dl>
          <p v-if="confirming.note" class="mt-3 rounded-xl bg-white/70 px-3 py-2 text-xs text-slate-700">“{{ confirming.note }}”</p>
          <p v-if="confirming.method === 'mobile_money'" class="mt-2 text-xs text-slate-600">Check your phone for this money before confirming.</p>
        </div>

        <!-- What the landlord actually received: can be corrected -->
        <div class="recv rounded-2xl p-4">
          <label class="flex items-center gap-2 text-xs font-semibold tracking-[0.12em] text-brand-700 uppercase" for="cr-amount"><HandCoins class="size-4" /> Amount you actually received</label>
          <input id="cr-amount" v-model="amount" class="input mt-2 h-14 text-xl font-bold tabular-nums" inputmode="numeric" required />
          <div class="mt-2 flex flex-wrap items-center gap-2">
            <button v-if="differs" type="button" class="same-chip" @click="amount = String(confirming.amount)"><Equal class="size-3.5" /> Same as claimed · {{ formatUGX(confirming.amount) }}</button>
            <span v-else class="text-xs text-slate-500">Matches what the tenant says. Change it if you received a different amount.</span>
          </div>
          <p v-if="differs" class="mt-2 rounded-xl bg-amber-50 px-3 py-2 text-xs text-amber-900">
            You are confirming <strong>{{ formatUGX(value) }}</strong> instead of {{ formatUGX(confirming.amount) }}. The tenant is told the amount you confirmed.
          </p>
        </div>

        <PaymentCoverage v-if="cTenant && value" :tenant="cTenant" :dues="cDues" :rent="cRent" :amount="value" :pay-day="confirming.paidOn" :you="false" />

        <p v-if="error" class="rounded-xl bg-red-50 p-3 text-sm text-red-700">{{ error }}</p>
        <div class="grid grid-cols-2 gap-2">
          <button type="button" class="btn-secondary h-11" @click="confirming = null">Cancel</button>
          <button :data-busy="Boolean(busy)" type="submit" class="btn-primary h-11" :disabled="busy || !value">{{ busy ? 'Confirming…' : `Confirm ${formatUGX(value)}` }}</button>
        </div>
        <p class="text-center text-xs text-slate-400">Unpaid months first, then months ahead. The tenant gets a notification.</p>
      </form>
    </BaseModal>

    <!-- Reject -->
    <BaseModal :model-value="Boolean(rejecting)" center title="Reject payment" width="max-w-md" @update:model-value="!$event && (rejecting = null)">
      <form v-if="rejecting" class="space-y-4" @submit.prevent="reject">
        <p class="text-sm text-slate-600">
          {{ formatUGX(rejecting.amount) }} from {{ tenantOf(rejecting)?.name }} will not be added to their rent. They will be notified.
        </p>
        <div>
          <label class="label" for="cr-reason">Reason <span class="font-normal text-slate-400">(shown to the tenant)</span></label>
          <input id="cr-reason" v-model="reason" class="input" maxlength="200" placeholder="e.g. No cash was received on that day" />
        </div>
        <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
        <div class="flex justify-end gap-2">
          <button type="button" class="btn-secondary" @click="rejecting = null">Cancel</button>
          <button :data-busy="Boolean(busy)" type="submit" class="btn bg-red-600 text-white hover:bg-red-700" :disabled="busy">{{ busy ? 'Rejecting…' : 'Reject payment' }}</button>
        </div>
      </form>
    </BaseModal>
  </div>
</template>

<style scoped>
.claim { background: var(--color-amber-50); box-shadow: inset 0 0 0 1.5px var(--color-amber-200); }
.recv { background: var(--color-white); box-shadow: inset 0 0 0 1.5px var(--color-brand-200); }
.same-chip { display: inline-flex; align-items: center; gap: 0.3rem; height: 2rem; border-radius: 9999px; padding: 0 0.8rem; font-size: 0.75rem; font-weight: 600; color: var(--color-brand-700); background: var(--color-brand-50); }
.rc-btn { display: inline-flex; align-items: center; gap: 0.35rem; height: 2rem; border-radius: 9999px; padding: 0 0.8rem; font-size: 0.75rem; font-weight: 600; color: var(--color-brand-700); background: var(--color-brand-50); }
.rc-btn:active { transform: scale(0.96); }
</style>
