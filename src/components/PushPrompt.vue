<script setup>
import { onMounted, ref } from 'vue'
import { BellRing, BellOff, Share, CheckCircle2 } from '@lucide/vue'
import { pushStatus, enablePush } from '@/lib/push'
import { useAuthStore } from '@/stores/auth'

// Card inviting the tenant to get notifications on their phone.
// `always` = also show the "on" / "blocked" state (used on the Notifications page).
defineProps({ always: Boolean })

const auth = useAuthStore()
const status = ref('loading')
const busy = ref(false)
const error = ref('')
const dismissed = ref(false)

onMounted(async () => {
  status.value = await pushStatus()
  try {
    dismissed.value = localStorage.getItem('renta-push-dismissed') === '1'
  } catch {
    /* storage blocked */
  }
})

async function turnOn() {
  busy.value = true
  error.value = ''
  try {
    await enablePush()
    status.value = 'on'
  } catch (e) {
    error.value = e.message
    status.value = await pushStatus()
  } finally {
    busy.value = false
  }
}

function dismiss() {
  dismissed.value = true
  try {
    localStorage.setItem('renta-push-dismissed', '1')
  } catch {
    /* storage blocked */
  }
}
</script>

<template>
  <!-- Offer to turn on -->
  <div
    v-if="status === 'off' && (always || !dismissed)"
    class="card flex flex-col gap-4 border-brand-200 p-5 sm:flex-row sm:items-center"
  >
    <div class="flex flex-1 items-start gap-4">
      <div class="flex size-10 shrink-0 items-center justify-center rounded-full bg-brand-50 text-brand-600">
        <BellRing class="size-5" />
      </div>
      <div>
        <p class="text-sm font-medium text-slate-900">Get notifications on this phone</p>
        <p class="mt-0.5 text-sm text-slate-500">
          {{ auth.isTenant ? 'Rent reminders, payment receipts and messages from your landlord' : 'Confirmations when tenants pay' }}, even when the app is closed.
        </p>
        <p v-if="error" class="mt-1 text-sm text-red-600">{{ error }}</p>
      </div>
    </div>
    <div class="flex shrink-0 gap-2">
      <button v-if="!always" class="btn-ghost" @click="dismiss">Not now</button>
      <button class="btn-primary" :disabled="busy" @click="turnOn">{{ busy ? 'Turning on…' : 'Turn on' }}</button>
    </div>
  </div>

  <!-- iPhone: must add to Home Screen first -->
  <div v-else-if="status === 'needs-install' && (always || !dismissed)" class="card flex items-start gap-4 border-brand-200 p-5">
    <div class="flex size-10 shrink-0 items-center justify-center rounded-full bg-brand-50 text-brand-600">
      <Share class="size-5" />
    </div>
    <div class="flex-1 text-sm">
      <p class="font-medium text-slate-900">Want notifications on your iPhone?</p>
      <p class="mt-0.5 text-slate-500">
        In Safari tap <strong>Share</strong> → <strong>Add to Home Screen</strong>, then open Renta from your Home Screen and turn notifications on.
      </p>
    </div>
    <button v-if="!always" class="btn-ghost shrink-0" @click="dismiss">Not now</button>
  </div>

  <!-- Status (Notifications page only) -->
  <p v-else-if="always && status === 'on'" class="flex items-center gap-2 text-sm text-emerald-700">
    <CheckCircle2 class="size-4" /> Notifications are on for this device.
  </p>
  <p v-else-if="always && status === 'denied'" class="flex items-start gap-2 text-sm text-slate-600">
    <BellOff class="mt-0.5 size-4 shrink-0" />
    Notifications are blocked for this site. Allow them in your browser or phone settings (Site settings → Notifications) to get alerts on this device.
  </p>
</template>
