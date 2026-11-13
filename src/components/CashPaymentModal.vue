<script setup>
import { computed, ref, watch } from 'vue'
import { Banknote, CheckCircle2 } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { formatUGX, formatDate, formatPeriod } from '@/utils/format'
import BaseModal from './BaseModal.vue'
import StatusBadge from './StatusBadge.vue'

// Landlord: record cash from a tenant. The amount is applied to their oldest unpaid rent first;
// the tenant is notified only when a month's rent is fully paid.
const props = defineProps({ tenantId: { type: String, default: null } }) // preselect a tenant
const open = defineModel({ type: Boolean, default: false })
const emit = defineEmits(['saved'])

const rental = useRentalStore()
const today = () => new Date().toLocaleDateString('en-CA')

const tenantId = ref('')
const amount = ref('')
const receivedAt = ref(today())
const note = ref('')
const busy = ref(false)
const error = ref('')
const result = ref(null)

watch(
  open,
  (v) => {
    if (!v) return
    tenantId.value = props.tenantId ?? ''
    amount.value = ''
    receivedAt.value = today()
    note.value = ''
    error.value = ''
    result.value = null
  },
  { immediate: true },
)

// Tenants who owe something, with their total balance
const owing = computed(() =>
  rental.tenants
    .map((t) => ({ ...t, owed: rental.duesForTenant(t.id).reduce((s, p) => s + p.balance, 0) }))
    .filter((t) => t.owed > 0)
    .sort((a, b) => a.name.localeCompare(b.name)),
)
const dues = computed(() => (tenantId.value ? rental.duesForTenant(tenantId.value) : []))
const total = computed(() => dues.value.reduce((s, p) => s + p.balance, 0))
const value = computed(() => Math.round(Number(String(amount.value).replace(/[^\d]/g, '')) || 0))

// Preview: how the amount will be split (oldest rent first), same rule as the database
const plan = computed(() => {
  let left = value.value
  return dues.value.map((p) => {
    const take = Math.min(left, p.balance)
    left -= take
    return { ...p, take, after: p.balance - take }
  })
})
const balanceAfter = computed(() => Math.max(0, total.value - value.value))
const tooMuch = computed(() => value.value > total.value)

async function save() {
  error.value = ''
  if (!value.value) return (error.value = 'Enter the amount received.')
  if (tooMuch.value) return (error.value = `That's more than the balance of ${formatUGX(total.value)}.`)
  busy.value = true
  try {
    result.value = await rental.recordCashPayment({
      tenantId: tenantId.value,
      amount: value.value,
      receivedAt: receivedAt.value,
      note: note.value,
    })
    emit('saved', result.value)
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <BaseModal v-model="open" title="Record cash payment">
    <!-- Done -->
    <div v-if="result" class="py-2 text-center">
      <CheckCircle2 class="mx-auto size-10 text-emerald-600" />
      <p class="mt-3 font-medium text-slate-900">{{ formatUGX(result.applied) }} recorded</p>
      <p class="mt-1 text-sm text-slate-600">
        <template v-if="result.balance_after === 0">All rent is now paid. The tenant has been sent a confirmation.</template>
        <template v-else>
          Remaining balance: <strong>{{ formatUGX(result.balance_after) }}</strong>.
          {{ result.parts.some((p) => p.paid_in_full) ? 'The tenant was notified about the month(s) now fully paid.' : 'The tenant will be notified once the month is fully paid.' }}
        </template>
      </p>
      <button class="btn-primary mt-6 w-full" @click="open = false">Done</button>
    </div>

    <form v-else class="space-y-4" @submit.prevent="save">
      <div>
        <label class="label" for="cash-tenant">Tenant</label>
        <select id="cash-tenant" v-model="tenantId" class="input" required>
          <option value="" disabled>{{ owing.length ? 'Select a tenant who owes rent' : 'Nobody owes rent right now' }}</option>
          <option v-for="t in owing" :key="t.id" :value="t.id">
            {{ t.name }} · owes {{ formatUGX(t.owed) }}{{ t.propertyId ? '' : ' (former tenant)' }}
          </option>
        </select>
      </div>

      <template v-if="tenantId">
        <!-- What they owe -->
        <div class="rounded-lg border border-slate-200">
          <div class="flex items-center justify-between border-b border-slate-100 px-3 py-2 text-xs text-slate-500">
            <span>Unpaid rent</span>
            <span>Total <strong class="text-slate-900">{{ formatUGX(total) }}</strong></span>
          </div>
          <ul class="divide-y divide-slate-100 text-sm">
            <li v-for="p in plan" :key="p.id" class="flex items-center justify-between gap-3 px-3 py-2">
              <div class="min-w-0">
                <p class="text-slate-900">{{ formatPeriod(p.period) }}</p>
                <p class="text-xs text-slate-500">due {{ formatDate(p.dueDate) }} · owes {{ formatUGX(p.balance) }}</p>
              </div>
              <div class="shrink-0 text-right text-xs">
                <template v-if="p.take">
                  <p class="font-medium text-emerald-700">+{{ formatUGX(p.take) }}</p>
                  <p :class="p.after ? 'text-amber-700' : 'text-emerald-700'">{{ p.after ? `${formatUGX(p.after)} left` : 'Paid in full' }}</p>
                </template>
                <StatusBadge v-else :status="p.status" />
              </div>
            </li>
          </ul>
        </div>

        <div class="grid grid-cols-2 gap-4">
          <div>
            <div class="flex items-center justify-between">
              <label class="label" for="cash-amount">Amount received (UGX)</label>
            </div>
            <input id="cash-amount" v-model="amount" type="text" inputmode="numeric" class="input" placeholder="e.g. 500000" required />
            <button type="button" class="mt-1 text-xs font-medium text-brand-600 hover:text-brand-700" @click="amount = String(total)">
              Full balance ({{ formatUGX(total) }})
            </button>
          </div>
          <div>
            <label class="label" for="cash-date">Date received</label>
            <input id="cash-date" v-model="receivedAt" type="date" class="input" :max="today()" required />
          </div>
        </div>

        <div>
          <label class="label" for="cash-note">Note <span class="font-normal text-slate-400">(optional)</span></label>
          <input id="cash-note" v-model="note" class="input" placeholder="e.g. Received by caretaker" maxlength="200" />
        </div>

        <p v-if="value && !tooMuch" class="rounded-lg bg-slate-50 p-3 text-sm text-slate-700">
          <template v-if="balanceAfter === 0">This clears everything they owe. They'll get a confirmation.</template>
          <template v-else>After this, they'll still owe <strong>{{ formatUGX(balanceAfter) }}</strong>.</template>
        </p>
      </template>

      <p v-if="error" class="text-sm text-red-600">{{ error }}</p>

      <div class="flex justify-end gap-2 pt-1">
        <button type="button" class="btn-secondary" @click="open = false">Cancel</button>
        <button type="submit" class="btn-primary" :disabled="busy || !tenantId || !value || tooMuch">
          <Banknote class="size-4" /> {{ busy ? 'Saving…' : 'Record payment' }}
        </button>
      </div>
    </form>
  </BaseModal>
</template>
