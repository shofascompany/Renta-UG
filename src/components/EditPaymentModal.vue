<script setup>
import { computed, ref, watch } from 'vue'
import { CalendarDays, Wallet, Info, Save } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { formatUGX, formatPeriod } from '@/utils/format'
import { isoDay } from '@/utils/rentCycle'
import BaseModal from './BaseModal.vue'
import BaseSelect from './BaseSelect.vue'

// Landlord: correct a payment of a tenant without a smartphone (amount, date, method, note).
// The database recalculates the rent month and the rental time, so every page and receipt stays in step.
const props = defineProps({ receipt: { type: Object, default: null } }) // a row of rental.payment_receipts
const open = defineModel({ type: Boolean, default: false })
const emit = defineEmits(['saved'])

const rental = useRentalStore()
const METHODS = ['Cash', 'MTN Mobile Money', 'Airtel Money', 'Bank transfer']
const amount = ref('')
const date = ref('')
const method = ref('Cash')
const note = ref('')
const saving = ref(false)
const error = ref('')
const today = () => isoDay(new Date())

const charge = computed(() => (props.receipt ? rental.payments.find((p) => p.id === props.receipt.paymentId) : null))
// The most this payment can be: what is left on its rent month once this payment is taken out
const maxAmount = computed(() => (charge.value && props.receipt ? charge.value.amount - (charge.value.amountPaid - props.receipt.amount) : 0))
const value = computed(() => Math.round(Number(String(amount.value).replace(/[^\d]/g, '')) || 0))
const methodOptions = computed(() => {
  const list = [...METHODS]
  if (props.receipt?.method && !list.includes(props.receipt.method)) list.unshift(props.receipt.method)
  return list.map((m) => ({ value: m, label: m }))
})

watch(
  () => [open.value, props.receipt?.id],
  ([isOpen]) => {
    if (!isOpen || !props.receipt) return
    error.value = ''
    amount.value = String(props.receipt.amount)
    date.value = isoDay(props.receipt.receivedAt)
    method.value = props.receipt.method || 'Cash'
    note.value = props.receipt.note ?? ''
  },
  { immediate: true },
)

async function save() {
  error.value = ''
  if (!value.value) return (error.value = 'Enter the amount received.')
  if (maxAmount.value && value.value > maxAmount.value) return (error.value = `That is more than the rent for this month. The most you can enter is ${formatUGX(maxAmount.value)}.`)
  if (!date.value) return (error.value = 'Choose the date it was received.')
  if (date.value > today()) return (error.value = 'The payment date cannot be in the future.')
  saving.value = true
  try {
    await rental.editReceipt({ id: props.receipt.id, amount: value.value, receivedAt: date.value, method: method.value, note: note.value.trim() })
    open.value = false
    emit('saved')
  } catch (e) {
    error.value = e.message
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <BaseModal v-model="open" center title="Edit payment" width="max-w-md">
    <form v-if="receipt" class="space-y-4" @submit.prevent="save">
      <p v-if="charge" class="flex items-start gap-2.5 rounded-2xl bg-slate-50 p-3 text-xs leading-relaxed text-slate-600">
        <Info class="mt-0.5 size-4 shrink-0 text-brand-600" />
        <span>Rent for <strong class="text-slate-900">{{ formatPeriod(charge.period) }}</strong> is {{ formatUGX(charge.amount) }}. Changing this payment updates that month and the tenant's rental time.</span>
      </p>

      <div>
        <label class="label" for="ep-amount">Amount received (UGX)</label>
        <div class="relative">
          <Wallet class="pointer-events-none absolute top-1/2 left-3.5 size-4.5 -translate-y-1/2 text-slate-400" />
          <input id="ep-amount" v-model="amount" inputmode="numeric" class="input h-12 pl-10 text-lg font-semibold tabular-nums" data-cap="off" autocomplete="off" required />
        </div>
        <p v-if="maxAmount" class="mt-1 text-xs text-slate-500">Up to {{ formatUGX(maxAmount) }} for this month.</p>
      </div>

      <div class="grid grid-cols-2 gap-3">
        <div>
          <label class="label" for="ep-date">Date received</label>
          <div class="relative">
            <CalendarDays class="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-slate-400" />
            <input id="ep-date" v-model="date" type="date" class="input pl-9" :max="today()" required />
          </div>
        </div>
        <div>
          <label class="label" for="ep-method">Paid by</label>
          <BaseSelect id="ep-method" v-model="method" :options="methodOptions" />
        </div>
      </div>

      <div>
        <label class="label" for="ep-note">Note (optional)</label>
        <input id="ep-note" v-model="note" class="input" maxlength="300" placeholder="e.g. Paid through a relative" data-cap="off" />
      </div>

      <p v-if="error" class="form-error" role="alert">{{ error }}</p>

      <div class="grid grid-cols-2 gap-2 pt-1">
        <button type="button" class="btn-secondary h-11" @click="open = false">Cancel</button>
        <button type="submit" class="btn-primary h-11" :data-busy="saving" :disabled="saving"><Save class="size-4" /> {{ saving ? 'Saving…' : 'Save changes' }}</button>
      </div>
    </form>
  </BaseModal>
</template>
