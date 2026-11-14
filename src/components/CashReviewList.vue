<script setup>
import { computed, ref } from 'vue'
import { Banknote, CheckCircle2, XCircle, Clock, Smartphone, UserCog } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useAuthStore } from '@/stores/auth'
import { formatUGX, formatDate } from '@/utils/format'
import BaseModal from './BaseModal.vue'

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
          <span class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-emerald-50 text-emerald-700">
            <Banknote class="size-5" />
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
              <p class="font-semibold text-slate-900 tabular-nums">
                {{ formatUGX(c.status === 'confirmed' ? c.confirmedAmount : c.amount) }}
              </p>
            </div>
            <p class="mt-0.5 truncate text-sm text-slate-500">
              {{ houseOf(c) ?? '—' }}<template v-if="showLandlord"> · {{ landlordOf(c) }}</template>
            </p>
            <p class="mt-1.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-slate-500">
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
            </div>
          </div>
        </div>
      </li>
    </ul>
    <p v-else class="px-5 py-10 text-center text-sm text-slate-500">{{ empty }}</p>

    <!-- Confirm -->
    <BaseModal :model-value="Boolean(confirming)" title="Confirm cash payment" width="max-w-md" @update:model-value="!$event && (confirming = null)">
      <form v-if="confirming" class="space-y-4" @submit.prevent="confirm">
        <div class="rounded-xl bg-slate-50 p-4 text-sm">
          <p class="font-medium text-slate-900">{{ tenantOf(confirming)?.name }}</p>
          <p class="mt-0.5 text-slate-500">
            {{ confirming.submittedRole === 'tenant' ? 'Reported' : 'Recorded' }} {{ formatUGX(confirming.amount) }} paid on {{ formatDate(confirming.paidOn) }}
          </p>
          <p class="mt-0.5 text-slate-500">Unpaid rent: <strong class="text-slate-900">{{ formatUGX(owedBy(confirming)) }}</strong></p>
          <p class="mt-2 text-xs text-slate-500">It tops up their rent: unpaid months first, then anything extra pays the next months ahead.</p>
        </div>
        <div>
          <label class="label" for="cr-amount">Amount actually received (UGX)</label>
          <input id="cr-amount" v-model="amount" class="input" inputmode="numeric" required />
          <p class="mt-1 text-xs text-slate-500">Correct it if the cash received was different. It's credited to the oldest unpaid rent first.</p>
        </div>
        <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
        <div class="flex justify-end gap-2">
          <button type="button" class="btn-secondary" @click="confirming = null">Cancel</button>
          <button :data-busy="Boolean(busy)" type="submit" class="btn-primary" :disabled="busy || !value">{{ busy ? 'Confirming…' : `Confirm ${formatUGX(value)}` }}</button>
        </div>
      </form>
    </BaseModal>

    <!-- Reject -->
    <BaseModal :model-value="Boolean(rejecting)" title="Reject cash payment" width="max-w-md" @update:model-value="!$event && (rejecting = null)">
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
