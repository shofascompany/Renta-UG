<script setup>
import { computed, ref } from 'vue'
import { DoorOpen, Star, CheckCircle2, XCircle, TriangleAlert, Clock } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useAuthStore } from '@/stores/auth'
import { formatDate, formatUGX } from '@/utils/format'
import AdminHeader from '@/components/admin/AdminHeader.vue'
import BaseModal from '@/components/BaseModal.vue'

// Landlords: their tenants' requests to leave a room. Only the landlord approves or declines.
// Approve → the tenancy ends (history kept, room vacant) and the tenant is signed out.
const rental = useRentalStore()
const auth = useAuthStore()
const filter = ref('pending') // pending | all

const tenantName = (id) => rental.tenantById(id)?.name ?? 'Tenant'
const place = (id) => (id && rental.propertyById(id) ? rental.placeName(id) : 'Room')
const owedBy = (id) => rental.duesForTenant(id).reduce((s, p) => s + p.balance, 0)
const landlordName = (id) => rental.landlords.find((l) => l.id === id)?.name

const list = computed(() =>
  [...rental.move_out_requests]
    .filter((r) => filter.value === 'all' || r.status === 'pending')
    .sort((a, b) => Number(b.status === 'pending') - Number(a.status === 'pending') || b.createdAt.localeCompare(a.createdAt)),
)
const STATUS = {
  pending: ['Waiting', 'bg-amber-50 text-amber-700'],
  approved: ['Approved', 'bg-emerald-50 text-emerald-700'],
  declined: ['Declined', 'bg-red-50 text-red-700'],
  cancelled: ['Cancelled', 'bg-slate-100 text-slate-600'],
}

const openId = ref(null)
const open = computed(() => rental.move_out_requests.find((r) => r.id === openId.value) ?? null)
const step = ref('view') // view | approve | decline
const note = ref('')
const busy = ref(false)
const error = ref('')
function show(r) {
  openId.value = r.id
  step.value = 'view'
  note.value = ''
  error.value = ''
}
async function decide(approve) {
  busy.value = true
  error.value = ''
  try {
    await rental.decideMoveOut(open.value.id, approve, note.value)
    openId.value = null
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <div class="mx-auto max-w-3xl">
    <AdminHeader
      eyebrow="Tenants"
      title="Requests to leave"
      :subtitle="`${rental.pendingMoveOuts.length} waiting for a decision`"
    />

    <div class="mb-4 grid w-full grid-cols-2 rounded-2xl bg-slate-100 p-1 text-sm sm:w-72">
      <button v-for="f in [['pending', 'Waiting'], ['all', 'All requests']]" :key="f[0]" type="button" class="h-10 rounded-xl font-medium transition" :class="filter === f[0] ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500'" @click="filter = f[0]">{{ f[1] }}</button>
    </div>

    <div class="sheet rise">
      <ul v-if="list.length" class="divide-y divide-slate-100">
        <li v-for="r in list" :key="r.id">
          <button type="button" class="flex w-full items-center gap-3.5 px-4 py-4 text-left transition-colors hover:bg-slate-50 active:bg-slate-100 sm:px-5" @click="show(r)">
            <span class="icon-tile" :class="r.status === 'pending' ? 'tile-amber' : r.status === 'approved' ? 'tile-teal' : 'tile-slate'"><DoorOpen class="size-[1.3rem]" /></span>
            <div class="min-w-0 flex-1">
              <p class="truncate font-medium text-slate-900">{{ tenantName(r.tenantId) }}</p>
              <p class="truncate text-xs text-slate-500">{{ place(r.propertyId) }} · {{ r.reason }}</p>
              <div class="mt-1 flex items-center gap-0.5">
                <Star v-for="n in 5" :key="n" class="size-3.5" :class="n <= (r.rating ?? 0) ? 'fill-amber-400 text-amber-400' : 'text-slate-200'" stroke-width="1.5" />
              </div>
            </div>
            <div class="shrink-0 text-right">
              <span class="inline-block rounded-md px-2 py-0.5 text-[11px] font-semibold" :class="STATUS[r.status][1]">{{ STATUS[r.status][0] }}</span>
              <p class="mt-1 text-[11px] text-slate-400">{{ formatDate(r.createdAt) }}</p>
            </div>
          </button>
        </li>
      </ul>
      <div v-else class="flex flex-col items-center px-6 py-14 text-center">
        <span class="icon-tile tile-teal size-12"><CheckCircle2 class="size-6" /></span>
        <p class="mt-3 font-semibold text-slate-900">{{ filter === 'pending' ? 'No requests waiting' : 'No requests yet' }}</p>
        <p class="mt-1 max-w-xs text-sm text-slate-500">When a tenant asks to leave their room, it appears here for you to approve.</p>
      </div>
    </div>

    <!-- Request -->
    <BaseModal :model-value="Boolean(open)" :title="step === 'approve' ? 'Approve move-out?' : step === 'decline' ? 'Decline request' : 'Request to leave'" width="max-w-md" @update:model-value="!$event && (openId = null)">
      <div v-if="open" class="space-y-5">
        <template v-if="step === 'view'">
          <div class="rounded-2xl bg-slate-50 p-4">
            <p class="text-lg font-semibold text-slate-900">{{ tenantName(open.tenantId) }}</p>
            <p class="text-sm text-slate-500">{{ place(open.propertyId) }}<template v-if="auth.isSuperadmin && landlordName(open.landlordId)"> · {{ landlordName(open.landlordId) }}</template></p>
            <div class="mt-3 flex items-center gap-1">
              <Star v-for="n in 5" :key="n" class="size-5" :class="n <= (open.rating ?? 0) ? 'fill-amber-400 text-amber-400' : 'text-slate-200'" stroke-width="1.5" />
              <span class="ml-1.5 text-sm font-medium text-slate-600">{{ open.rating }}/5</span>
            </div>
          </div>
          <dl class="space-y-4 text-sm">
            <div><dt class="text-xs font-semibold tracking-wider text-slate-400 uppercase">Reason</dt><dd class="mt-1 font-medium text-slate-900">{{ open.reason }}</dd></div>
            <div v-if="open.details"><dt class="text-xs font-semibold tracking-wider text-slate-400 uppercase">Details</dt><dd class="mt-1 leading-relaxed text-slate-700">{{ open.details }}</dd></div>
            <div v-if="open.review"><dt class="text-xs font-semibold tracking-wider text-slate-400 uppercase">Review</dt><dd class="mt-1 leading-relaxed text-slate-700">“{{ open.review }}”</dd></div>
            <div class="flex items-center gap-2 text-xs text-slate-500"><Clock class="size-3.5" /> Sent {{ formatDate(open.createdAt) }}<template v-if="open.decidedAt"> · decided {{ formatDate(open.decidedAt) }}</template></div>
            <p v-if="open.decisionNote" class="rounded-xl bg-slate-50 p-3 text-slate-600">Note: {{ open.decisionNote }}</p>
          </dl>
          <div v-if="open.status === 'pending' && auth.isLandlord" class="grid grid-cols-2 gap-2.5">
            <button type="button" class="btn-secondary h-12 rounded-2xl text-red-600" @click="step = 'decline'"><XCircle class="size-4" /> Decline</button>
            <button type="button" class="btn-primary h-12 rounded-2xl" @click="step = 'approve'"><CheckCircle2 class="size-4" /> Approve</button>
          </div>
        </template>

        <!-- Confirm approve -->
        <template v-else-if="step === 'approve'">
          <div class="flex items-start gap-3.5 rounded-2xl bg-amber-50 p-4">
            <span class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-amber-100 text-amber-700"><TriangleAlert class="size-5" /></span>
            <p class="text-sm leading-relaxed text-amber-900">
              <strong>{{ tenantName(open.tenantId) }}</strong>'s tenancy at <strong>{{ place(open.propertyId) }}</strong> ends now. The room becomes vacant, their history moves to Records, and their app signs them out.
            </p>
          </div>
          <p v-if="owedBy(open.tenantId)" class="text-sm text-slate-600">They still owe <strong class="text-slate-900">{{ formatUGX(owedBy(open.tenantId)) }}</strong>. It stays on their record.</p>
          <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
          <div class="flex justify-end gap-2">
            <button type="button" class="btn-secondary" @click="step = 'view'">Back</button>
            <button type="button" class="btn-primary" :data-busy="busy" :disabled="busy" @click="decide(true)">{{ busy ? 'Approving…' : 'Approve & end tenancy' }}</button>
          </div>
        </template>

        <!-- Decline -->
        <template v-else>
          <div>
            <label class="label" for="mo-note">Reason for declining <span class="font-normal text-slate-400">(sent to the tenant)</span></label>
            <textarea id="mo-note" v-model="note" rows="3" maxlength="300" class="input" placeholder="e.g. Please clear your balance first" />
          </div>
          <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
          <div class="flex justify-end gap-2">
            <button type="button" class="btn-secondary" @click="step = 'view'">Back</button>
            <button type="button" class="btn bg-red-600 text-white hover:bg-red-700" :data-busy="busy" :disabled="busy" @click="decide(false)">{{ busy ? 'Declining…' : 'Decline request' }}</button>
          </div>
        </template>
      </div>
    </BaseModal>
  </div>
</template>
