<script setup>
import { computed, onMounted, ref } from 'vue'
import { Bell, BellRing, BellOff, Share, Smartphone } from '@lucide/vue'
import { useAuthStore } from '@/stores/auth'
import { pushStatus, enablePush, disablePush } from '@/lib/push'
import SettingsSubpage from '@/components/SettingsSubpage.vue'

const auth = useAuthStore()
const status = ref('loading')
const busy = ref(false)
const error = ref('')

onMounted(async () => (status.value = await pushStatus()))

const on = computed(() => status.value === 'on')
const canToggle = computed(() => status.value === 'on' || status.value === 'off')

async function toggle() {
  busy.value = true
  error.value = ''
  try {
    if (on.value) await disablePush()
    else await enablePush()
  } catch (e) {
    error.value = e.message
  } finally {
    status.value = await pushStatus()
    busy.value = false
  }
}

const whatYouGet = computed(() =>
  auth.isLandlord
    ? ['When a tenant pays rent', 'Payment confirmations']
    : ['Rent due reminders', 'Payment receipts', 'Messages from your landlord'],
)
</script>

<template>
  <SettingsSubpage title="Notifications" subtitle="Get alerts on this device, even when Renta is closed." :icon="Bell">
    <!-- Main switch -->
    <div class="card p-6">
      <div class="flex items-center gap-4">
        <div class="flex size-11 shrink-0 items-center justify-center rounded-lg" :class="on ? 'bg-brand-50 text-brand-600' : 'bg-slate-100 text-slate-500'">
          <component :is="on ? BellRing : BellOff" class="size-5" />
        </div>
        <div class="flex-1">
          <p class="text-sm font-medium text-slate-900">Notifications on this device</p>
          <p class="mt-0.5 text-sm text-slate-500">
            <template v-if="status === 'loading'">Checking…</template>
            <template v-else-if="on">On: you'll get alerts here.</template>
            <template v-else-if="status === 'off'">Off</template>
            <template v-else-if="status === 'denied'">Blocked by your browser</template>
            <template v-else-if="status === 'needs-install'">Add Renta to your Home Screen first</template>
            <template v-else>Not available in this browser</template>
          </p>
        </div>
        <button
          v-if="canToggle"
          role="switch"
          :aria-checked="on"
          aria-label="Notifications on this device"
          class="relative h-7 w-12 shrink-0 cursor-pointer rounded-full transition-colors disabled:cursor-wait disabled:opacity-60"
          :class="on ? 'bg-brand-600' : 'bg-slate-300'"
          :disabled="busy"
          @click="toggle"
        >
          <span class="absolute top-1 left-1 size-5 rounded-full bg-[#fff] shadow transition-transform" :class="on ? 'translate-x-5' : ''" />
        </button>
      </div>
      <p v-if="error" class="mt-4 text-sm text-red-600">{{ error }}</p>
    </div>

    <!-- Help for blocked / iPhone -->
    <div v-if="status === 'denied'" class="card flex items-start gap-4 p-5 text-sm">
      <BellOff class="mt-0.5 size-5 shrink-0 text-slate-400" />
      <p class="text-slate-600">
        Notifications were blocked for this site. To allow them, open your browser's <strong>Site settings → Notifications</strong>,
        set Renta to <strong>Allow</strong>, then come back to this page.
      </p>
    </div>
    <div v-else-if="status === 'needs-install'" class="card flex items-start gap-4 p-5 text-sm">
      <Share class="mt-0.5 size-5 shrink-0 text-brand-600" />
      <p class="text-slate-600">
        On iPhone, open Renta in Safari, tap <strong>Share → Add to Home Screen</strong>, then open Renta from your Home Screen and
        come back here to turn notifications on.
      </p>
    </div>

    <!-- What you'll receive -->
    <div class="card p-6">
      <h2 class="mb-4 text-base font-semibold text-slate-900">What you'll be notified about</h2>
      <ul class="space-y-3">
        <li v-for="w in whatYouGet" :key="w" class="flex items-center gap-3 text-sm text-slate-700">
          <Smartphone class="size-4 shrink-0 text-brand-600" /> {{ w }}
        </li>
      </ul>
    </div>
    <p class="px-1 text-xs text-slate-400">This setting applies to this device only. Turn it on separately on each phone or computer you use.</p>
  </SettingsSubpage>
</template>
