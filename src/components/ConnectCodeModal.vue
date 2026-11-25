<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { Copy, Check, RefreshCw, CircleCheckBig, MessageCircle } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useAuthStore } from '@/stores/auth'
import { copyText } from '@/lib/clipboard'
import AppLink from './AppLink.vue'
import BaseModal from './BaseModal.vue'

// Owner: shows a tenant's 20-minute connection code, generating one if needed.
const props = defineProps({ tenantId: String })
const open = defineModel({ type: Boolean, default: false })

const rental = useRentalStore()
const tenant = computed(() => rental.tenantById(props.tenantId))
const now = ref(Date.now())
const busy = ref(false)
const error = ref('')
const copied = ref(false)

const secondsLeft = computed(() => {
  const exp = tenant.value?.connectCodeExpiresAt
  return exp ? Math.max(0, Math.floor((new Date(exp).getTime() - now.value) / 1000)) : 0
})
const countdown = computed(() => {
  const s = secondsLeft.value
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`
})
const code = computed(() => (secondsLeft.value > 0 ? tenant.value?.connectCode : null))

async function generate() {
  busy.value = true
  error.value = ''
  try {
    await rental.newConnectCode(props.tenantId)
    now.value = Date.now()
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}

// The whole message: who registered them, where, the key, and the two warnings. No link. Sent on WhatsApp (the
// landlord picks who to send it to) and copied by "Copy message".
const auth = useAuthStore()
const message = computed(() => {
  const home = tenant.value?.propertyId ? rental.placeName(tenant.value.propertyId) : ''
  return [
    `${auth.user?.name?.trim() || 'Your landlord'} has registered you${home && home !== '—' ? ` in ${home}` : ''}`,
    '',
    `Your one time connection key: ${code.value ?? ''}`,
    '',
    'Do not share with anyone',
    '',
    'This code lasts 20 minutes',
  ].join('\n')
})
async function copy() {
  if (!code.value || !(await copyText(message.value))) return
  copied.value = true
  setTimeout(() => (copied.value = false), 2000)
}

// Runs after everything above is defined (it uses secondsLeft and generate).
let timer = null
watch(
  open,
  (v) => {
    clearInterval(timer)
    if (!v) return
    timer = setInterval(() => (now.value = Date.now()), 1000)
    error.value = ''
    // Reuse a still-valid code; otherwise make a fresh one
    if (tenant.value && !tenant.value.userId && secondsLeft.value <= 0) generate()
  },
  { immediate: true },
)
onBeforeUnmount(() => clearInterval(timer))
</script>

<template>
  <BaseModal v-model="open" title="Connection code" width="max-w-md">
    <div v-if="tenant?.userId" class="py-4 text-center">
      <CircleCheckBig class="mx-auto size-10 text-emerald-600" />
      <p class="mt-3 font-medium text-slate-900">{{ tenant.name }} is connected</p>
      <p class="mt-1 text-sm text-slate-500">They can now see their dashboard, payments and notices.</p>
      <button class="btn-primary mt-6 w-full" @click="open = false">Done</button>
    </div>

    <div v-else-if="tenant">
      <p class="text-sm text-slate-600">
        Share this code with <strong>{{ tenant.name }}</strong>. They create an account, enter the code, and are connected to
        this rental automatically.
      </p>

      <div class="mt-5 rounded-xl border border-slate-200 p-5 text-center">
        <template v-if="code">
          <p class="font-mono text-4xl font-semibold tracking-[0.3em] text-slate-900">{{ code }}</p>
          <p class="mt-2 text-sm" :class="secondsLeft < 120 ? 'text-red-600' : 'text-slate-500'">Expires in {{ countdown }}</p>
        </template>
        <div v-else-if="busy" class="flex flex-col items-center gap-3" aria-label="Generating code">
          <div class="skeleton h-10 w-56" />
          <div class="skeleton h-4 w-28" />
        </div>
        <p v-else class="text-sm text-slate-500">This code has expired. Click <strong>New code</strong>.</p>
      </div>

      <p v-if="error" class="form-error mt-3" role="alert">{{ error }}</p>

      <template v-if="code">
        <AppLink :text="message" class="btn mt-5 h-12 w-full bg-[#25D366] text-white hover:bg-[#1fb957]"><MessageCircle class="size-5" /> Share code on WhatsApp</AppLink>
      </template>

      <div class="mt-5 flex gap-2">
        <button class="btn-secondary flex-1" :disabled="busy" @click="generate">
          <RefreshCw class="size-4" /> New code
        </button>
        <button class="btn-primary flex-1" :disabled="!code" @click="copy">
          <component :is="copied ? Check : Copy" class="size-4" /> {{ copied ? 'Copied' : 'Copy message' }}
        </button>
      </div>
      <p class="mt-3 text-center text-xs text-slate-400">This window updates automatically when they connect.</p>
    </div>
  </BaseModal>
</template>
