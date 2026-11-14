<script setup>
import { computed, ref, watch } from 'vue'
import { Banknote, CheckCircle2, CalendarDays } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { formatUGX, formatDate, formatPeriod } from '@/utils/format'
import BaseModal from './BaseModal.vue'
import StatusBadge from './StatusBadge.vue'

// Landlord: record cash received from ANY current tenant, whether rent is due or not. It counts straight
// away: it pays unpaid rent first (oldest first), then the next months ahead at the tenant's monthly rent,
// and the tenant is notified once.
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

// Every current tenant (owing or not), with what they owe
const tenants = computed(() =>
  rental.currentTenants
    .map((t) => ({ ...t, owed: rental.duesForTenant(t.id).reduce((s, p) => s + p.balance, 0) }))
    .sort((a, b) => a.name.localeCompare(b.name)),
)
const dues = computed(() => (tenantId.value ? rental.duesForTenant(tenantId.value) : []))
const total = computed(() => dues.value.reduce((s, p) => s + p.balance, 0))
const value = computed(() => Math.round(Number(String(amount.value).replace(/[^\d]/g, '')) || 0))
const rent = computed(() => {
  const t = rental.tenantById(tenantId.value)
  return t ? rental.propertyById(t.propertyId)?.rent ?? 0 : 0
})

// Preview, same rule as the database: unpaid rent first (oldest first), then months ahead
const plan = computed(() => {
  let left = value.value
  return dues.value.map((p) => {
    const take = Math.min(left, p.balance)
    left -= take
    return { ...p, take, after: p.balance - take }
  })
})
const extra = computed(() => Math.max(0, value.value - total.value)) // goes to months ahead
const ahead = computed(() => {
  if (!extra.value || !rent.value) return []
  const periods = rental.paymentsForTenant(tenantId.value).map((p) => p.period).sort()
  const now = new Date().toLocaleDateString('en-CA').slice(0, 7)
  const next = (p) => {
    const [y, m] = p.split('-').map(Number)
    const d = new Date(y, m, 1)
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
  }
  let period = periods.length && periods.at(-1) >= now ? next(periods.at(-1)) : now
  let left = extra.value
  const out = []
  while (left > 0 && out.length < 24) {
    const take = Math.min(left, rent.value)
    out.push({ period, take, full: take >= rent.value })
    left -= take
    period = next(period)
  }
  return out
})
const balanceAfter = computed(() => Math.max(0, total.value - value.value))
const tooMuch = computed(() => rent.value > 0 && extra.value > rent.value * 24)
const noRent = computed(() => extra.value > 0 && !rent.value)

async function save() {
  error.value = ''
  if (!value.value) return (error.value = 'Enter the amount received.')
  if (tooMuch.value) return (error.value = 'That covers more than 2 years ahead. Enter a smaller amount.')
  if (noRent.value) return (error.value = "This tenant's house has no monthly rent set, so the extra can't go to months ahead.")
  busy.value = true
  try {
    await rental.submitCash({
      tenantId: tenantId.value,
      amount: value.value,
      paidOn: receivedAt.value,
      note: note.value,
    })
    result.value = { amount: value.value, name: rental.tenantById(tenantId.value)?.name }
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
      <p class="mt-3 font-medium text-slate-900">{{ formatUGX(result.amount) }} recorded</p>
      <p class="mt-1 text-sm text-slate-600">
        The cash from {{ result.name }} has been added to their rent and they've been notified.
      </p>
      <button class="btn-primary mt-6 w-full" @click="open = false">Done</button>
    </div>

    <form v-else class="space-y-4" @submit.prevent="save">
      <div>
        <label class="label" for="cash-tenant">Tenant</label>
        <select id="cash-tenant" v-model="tenantId" class="input" required>
          <option value="" disabled>{{ tenants.length ? 'Select a tenant' : 'No tenants yet' }}</option>
          <option v-for="t in tenants" :key="t.id" :value="t.id">
            {{ t.name }} · {{ t.owed ? `owes ${formatUGX(t.owed)}` : 'paid up' }}
          </option>
        </select>
      </div>

      <template v-if="tenantId">
        <!-- Where the money goes -->
        <div class="overflow-hidden rounded-xl border border-slate-200">
          <div class="flex items-center justify-between border-b border-slate-100 bg-slate-50/70 px-3 py-2 text-xs text-slate-500">
            <span>{{ dues.length ? 'Unpaid rent' : 'Rent' }}</span>
            <span v-if="dues.length">Total <strong class="text-slate-900">{{ formatUGX(total) }}</strong></span>
            <span v-else>{{ formatUGX(rent) }} a month</span>
          </div>
          <ul class="divide-y divide-slate-100 text-sm">
            <li v-if="!dues.length && !ahead.length" class="px-3 py-3 text-xs text-slate-500">
              Nothing is owed. Any amount you enter pays the next months ahead.
            </li>
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
            <li v-for="m in ahead" :key="m.period" class="flex items-center justify-between gap-3 bg-sky-50/50 px-3 py-2">
              <div class="min-w-0">
                <p class="text-slate-900">{{ formatPeriod(m.period) }}</p>
                <p class="text-xs text-sky-700">paid ahead</p>
              </div>
              <div class="shrink-0 text-right text-xs">
                <p class="font-medium text-emerald-700">+{{ formatUGX(m.take) }}</p>
                <p :class="m.full ? 'text-emerald-700' : 'text-amber-700'">{{ m.full ? 'Paid in full' : `${formatUGX(rent - m.take)} left` }}</p>
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
            <button v-if="total" type="button" class="mt-1 text-xs font-medium text-brand-600 hover:text-brand-700" @click="amount = String(total)">
              Full balance ({{ formatUGX(total) }})
            </button>
            <button v-else-if="rent" type="button" class="mt-1 text-xs font-medium text-brand-600 hover:text-brand-700" @click="amount = String(rent)">
              One month ({{ formatUGX(rent) }})
            </button>
          </div>
          <div>
            <p class="label">Date received</p>
            <p class="flex h-[2.875rem] items-center gap-2 rounded-[0.875rem] bg-slate-50 px-3 text-sm font-medium text-slate-700 ring-1 ring-slate-200 ring-inset">
              <CalendarDays class="size-4 text-slate-400" /> Today, {{ formatDate(new Date()) }}
            </p>          </div>
        </div>

        <div>
          <label class="label" for="cash-note">Note <span class="font-normal text-slate-400">(optional)</span></label>
          <input id="cash-note" v-model="note" class="input" placeholder="e.g. Received by caretaker" maxlength="200" />
        </div>

        <p v-if="value && !tooMuch" class="rounded-lg bg-slate-50 p-3 text-sm text-slate-700">
          <template v-if="ahead.length">This {{ total ? 'clears what they owe and ' : '' }}pays <strong>{{ ahead.filter((m) => m.full).length }} month{{ ahead.filter((m) => m.full).length === 1 ? '' : 's' }} ahead</strong>.</template>
          <template v-else-if="balanceAfter === 0">This clears everything they owe.</template>
          <template v-else>They'll still owe <strong>{{ formatUGX(balanceAfter) }}</strong>.</template>
          It's added to their rent as soon as you save.
        </p>
      </template>

      <p v-if="error" class="text-sm text-red-600">{{ error }}</p>

      <div class="flex justify-end gap-2 pt-1">
        <button type="button" class="btn-secondary" @click="open = false">Cancel</button>
        <button :data-busy="Boolean(busy)" type="submit" class="btn-primary" :disabled="busy || !tenantId || !value || tooMuch || noRent">
          <Banknote class="size-4" /> {{ busy ? 'Recording…' : 'Record cash' }}
        </button>
      </div>
    </form>
  </BaseModal>
</template>
