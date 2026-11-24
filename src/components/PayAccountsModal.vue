<script setup>
import { computed, reactive, ref, watch } from 'vue'
import { CheckCircle2, Trash2, Pencil, Plus, Smartphone } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { NETWORKS, NETWORK_IDS, prettyPhone, validUgPhone, sendSteps } from '@/lib/networks'
import BaseModal from './BaseModal.vue'
import { askConfirm } from '@/composables/useConfirm'

// Landlord: the numbers they receive rent on (one per network) and the name the network shows.
// Tenants see these when they pay, with steps written automatically for each network.
const open = defineModel({ type: Boolean, default: false })
const rental = useRentalStore()

const accounts = computed(() => rental.payAccountsOf())
const accountFor = (id) => accounts.value.find((a) => a.network === id)

const editing = ref(null) // network id being edited
const form = reactive({ phone: '', accountName: '', dialCode: '' })
const busy = ref(false)
const error = ref('')
const saved = ref('')

watch(open, (v) => {
  if (!v) return
  editing.value = accounts.value.length ? null : 'mtn'
  if (editing.value) start('mtn')
  saved.value = ''
})

function start(id) {
  const a = accountFor(id)
  editing.value = id
  error.value = ''
  Object.assign(form, { phone: a?.phone ?? '', accountName: a?.accountName ?? '', dialCode: a?.dialCode ?? NETWORKS[id].dial })
}
async function save() {
  error.value = ''
  if (!validUgPhone(form.phone)) return (error.value = 'Enter a valid number, e.g. 0772 123456.')
  if (form.accountName.trim().length < 3) return (error.value = 'Enter the name the network shows when money is sent to this number.')
  busy.value = true
  try {
    await rental.savePayAccount({ network: editing.value, ...form })
    saved.value = `${NETWORKS[editing.value].short} number saved.`
    editing.value = null
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}
async function remove(a) {
  await askConfirm({
    title: `Remove your ${NETWORKS[a.network].short} number?`,
    text: 'Tenants will no longer see it when they pay.',
    note: `${prettyPhone(a.phone)} · ${a.accountName}`,
    confirm: 'Remove',
    cancel: 'Keep it',
    working: 'Removing…',
    icon: Trash2,
    action: () => rental.deletePayAccount(a.id),
  })
}
const preview = computed(() =>
  editing.value && form.phone && form.accountName
    ? sendSteps({ network: editing.value, phone: form.phone, accountName: form.accountName, dialCode: form.dialCode }, { amount: 300000, code: 'JOHN427' })
    : [],
)
</script>

<template>
  <BaseModal v-model="open" center width="max-w-md" title="Mobile money numbers">
    <p class="text-sm text-slate-500">Tenants send rent straight to these numbers. Renta shows them the steps for their network, and you confirm each payment.</p>
    <p v-if="saved" class="mt-3 flex items-center gap-2 rounded-xl bg-emerald-50 p-3 text-sm text-emerald-800"><CheckCircle2 class="size-4" /> {{ saved }}</p>

    <ul class="mt-4 space-y-2.5">
      <li v-for="id in NETWORK_IDS" :key="id" class="overflow-hidden rounded-2xl ring-1" :class="editing === id ? 'ring-2 ring-brand-500' : 'ring-slate-200'">
        <div class="flex items-center gap-3 p-3">
          <span class="flex size-11 shrink-0 items-center justify-center rounded-xl text-[11px] font-extrabold" :style="{ background: NETWORKS[id].gradient, color: NETWORKS[id].ink }">
            {{ NETWORKS[id].short.toUpperCase() }}
          </span>
          <div class="min-w-0 flex-1">
            <p class="font-semibold text-slate-900">{{ NETWORKS[id].label }}</p>
            <p v-if="accountFor(id)" class="truncate text-xs text-slate-500">{{ prettyPhone(accountFor(id).phone) }} · {{ accountFor(id).accountName }}</p>
            <p v-else class="text-xs text-slate-400">Not added</p>
          </div>
          <template v-if="editing !== id">
            <button v-if="accountFor(id)" type="button" class="icon-btn" aria-label="Remove" @click="remove(accountFor(id))"><Trash2 class="size-4" /></button>
            <button type="button" class="icon-btn text-brand-700" :aria-label="accountFor(id) ? 'Edit' : 'Add'" @click="start(id)">
              <Pencil v-if="accountFor(id)" class="size-4" /><Plus v-else class="size-4.5" />
            </button>
          </template>
        </div>

        <form v-if="editing === id" class="space-y-3 border-t border-slate-100 bg-slate-50/60 p-3" @submit.prevent="save">
          <div>
            <label class="label" :for="`pa-phone-${id}`">Number you receive on</label>
            <div class="relative">
              <Smartphone class="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-slate-400" />
              <input :id="`pa-phone-${id}`" v-model="form.phone" type="tel" class="input pl-9" placeholder="0772 123456" data-cap="off" required />
            </div>
          </div>
          <div>
            <label class="label" :for="`pa-name-${id}`">Name the network shows</label>
            <input :id="`pa-name-${id}`" v-model="form.accountName" class="input" data-cap="words" placeholder="e.g. John Mukasa" required />
            <p class="mt-1 text-xs text-slate-500">Tenants check this name before they send.</p>
          </div>
          <div>
            <label class="label" :for="`pa-dial-${id}`">Dial code</label>
            <input :id="`pa-dial-${id}`" v-model="form.dialCode" class="input font-mono" :placeholder="NETWORKS[id].dial || 'e.g. *xxx#'" data-cap="off" />
            <p class="mt-1 text-xs text-slate-500">Usually {{ NETWORKS[id].dial }}.</p>
          </div>

          <details v-if="preview.length" class="disclosure rounded-xl bg-white p-3 text-xs text-slate-600 ring-1 ring-slate-200">
            <summary class="cursor-pointer font-medium text-slate-800">What tenants will see</summary>
            <ol class="mt-2 list-decimal space-y-1 pl-4">
              <li v-for="(s, i) in preview" :key="i">{{ s }}</li>
            </ol>
          </details>

          <p v-if="error" class="form-error" role="alert">{{ error }}</p>
          <div class="grid grid-cols-2 gap-2">
            <button type="button" class="btn-secondary h-10" @click="editing = null; error = ''">Cancel</button>
            <button type="submit" class="btn-primary h-10" :data-busy="busy" :disabled="busy">{{ busy ? 'Saving…' : 'Save' }}</button>
          </div>
        </form>
      </li>
    </ul>
  </BaseModal>
</template>

<style scoped>
.icon-btn {
  display: flex;
  width: 2.25rem;
  height: 2.25rem;
  align-items: center;
  justify-content: center;
  border-radius: 0.7rem;
  color: var(--color-slate-500);
  transition: background-color 0.15s ease;
}
.icon-btn:hover { background: var(--color-slate-100); }
</style>
