<script setup>
import { ref } from 'vue'
import { KeyRound } from '@lucide/vue'
import { useAuthStore } from '@/stores/auth'
import { useRentalStore } from '@/stores/rental'

// Tenant: shown until their account is connected to a rental via the landlord's code.
const auth = useAuthStore()
const rental = useRentalStore()

const code = ref('')
const busy = ref(false)
const error = ref('')

function onInput(e) {
  code.value = e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 6)
}

async function submit() {
  busy.value = true
  error.value = ''
  try {
    await rental.redeemConnectCode(code.value)
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <div class="mx-auto max-w-md py-12">
    <div class="mx-auto mb-5 flex size-12 items-center justify-center rounded-full bg-brand-50">
      <KeyRound class="size-6 text-brand-600" />
    </div>
    <h1 class="text-center text-2xl font-semibold tracking-tight text-slate-900">Connect to your landlord</h1>
    <p class="mt-2 text-center text-sm text-slate-500">
      Hi {{ auth.user?.name?.split(' ')[0] }}, ask your landlord for your 6-character connection code and enter it below.
      Codes expire after 20 minutes.
    </p>

    <form class="card mt-8 p-6" @submit.prevent="submit">
      <label class="label" for="code">Connection code</label>
      <input
        id="code"
        :value="code"
        class="input text-center font-mono text-2xl tracking-[0.4em] uppercase"
        placeholder="ABC123"
        autocomplete="one-time-code"
        inputmode="text"
        maxlength="6"
        required
        @input="onInput"
      />
      <p v-if="error" class="mt-3 text-sm text-red-600">{{ error }}</p>
      <button type="submit" class="btn-primary mt-5 w-full" :disabled="busy || code.length !== 6">
        {{ busy ? 'Connecting…' : 'Connect' }}
      </button>
    </form>

    <p class="mt-6 text-center text-xs text-slate-400">Signed in as {{ auth.user?.email }}</p>
  </div>
</template>
