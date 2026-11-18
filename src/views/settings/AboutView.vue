<script setup>
import { computed } from 'vue'
import { Info, Download, ShieldCheck, Lightbulb } from '@lucide/vue'
import { version } from '../../../package.json'
import { useAuthStore } from '@/stores/auth'
import Logo from '@/components/Logo.vue'
import SettingsSubpage from '@/components/SettingsSubpage.vue'

const auth = useAuthStore()

const tips = computed(() =>
  auth.isLandlord
    ? [
        'Give each new tenant their connection code so they can connect to their house.',
        'Add your MTN or Airtel number in Payments → Mobile money numbers so tenants can pay you.',
        'Confirm payments from the Payments page: the tenant gets a notification and an SMS.',
        'Use Records to look back at former tenants and their payment history.',
      ]
    : [
        'Pay rent with MTN or Airtel Mobile Money from the Payments page, straight to your landlord.',
        'Use your own payment word as the reason, so your landlord knows it is you.',
        'Every confirmed payment is kept in your payment history.',
        'Turn on notifications so you never miss a rent reminder.',
      ],
)
</script>

<template>
  <SettingsSubpage title="About & help" subtitle="Information about the app and how to get the most from it." :icon="Info">
    <div class="card flex items-center justify-between gap-4 p-6">
      <Logo />
      <span class="rounded-full bg-slate-100 px-2.5 py-1 text-xs font-medium text-slate-600">Version {{ version }}</span>
    </div>

    <div class="card p-6">
      <div class="mb-4 flex items-center gap-3">
        <Download class="size-5 text-brand-600" />
        <h2 class="text-base font-semibold text-slate-900">Install Renta on your phone</h2>
      </div>
      <div class="space-y-4 text-sm text-slate-600">
        <div>
          <p class="font-medium text-slate-900">Android (Chrome)</p>
          <p class="mt-1">Tap the <strong>⋮</strong> menu, then <strong>Add to Home screen</strong> or <strong>Install app</strong>.</p>
        </div>
        <div>
          <p class="font-medium text-slate-900">iPhone (Safari)</p>
          <p class="mt-1">Tap <strong>Share</strong>, then <strong>Add to Home Screen</strong>.</p>
        </div>
      </div>
    </div>

    <div class="card p-6">
      <div class="mb-4 flex items-center gap-3">
        <Lightbulb class="size-5 text-brand-600" />
        <h2 class="text-base font-semibold text-slate-900">Tips</h2>
      </div>
      <ul class="list-disc space-y-2 pl-5 text-sm text-slate-600">
        <li v-for="t in tips" :key="t">{{ t }}</li>
      </ul>
    </div>

    <div class="card flex items-start gap-4 p-6 text-sm">
      <ShieldCheck class="mt-0.5 size-5 shrink-0 text-brand-600" />
      <p class="text-slate-600">
        Your account is protected by your password. Never share it with anyone, including people claiming to be from Renta UG.
      </p>
    </div>
  </SettingsSubpage>
</template>
