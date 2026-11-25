<script setup>
import { computed } from 'vue'
import { FileText } from '@lucide/vue'
import { useAuthStore } from '@/stores/auth'
import SettingsSubpage from '@/components/SettingsSubpage.vue'
import { legalFor } from '@/lib/legal'
import { SITE } from '@/lib/site'

// Terms & conditions shown in Settings: the same text as the public /terms page (src/lib/legal.js), only the one for
// this kind of account.
const auth = useAuthStore()
const terms = computed(() => legalFor('terms', auth.isLandlord ? 'landlord' : 'tenant'))
</script>

<template>
  <SettingsSubpage title="Terms & conditions" :subtitle="`Last updated ${SITE.updated}`" :icon="FileText">
    <div class="card divide-y divide-slate-100">
      <p class="px-5 py-5 text-sm leading-relaxed text-slate-700 sm:px-6">{{ terms.intro }}</p>
      <section v-for="s in terms.sections" :key="s.h" class="px-5 py-5 sm:px-6">
        <h2 class="text-sm font-semibold text-slate-900">{{ s.h }}</h2>
        <p v-for="(p, i) in s.p" :key="i" class="mt-2 text-sm leading-relaxed text-slate-600">{{ p }}</p>
      </section>
    </div>
    <p class="px-1 text-xs text-slate-400">
      Also read the <RouterLink to="/privacy" class="font-medium text-brand-700">Privacy policy</RouterLink> and how to
      <RouterLink to="/delete-account" class="font-medium text-brand-700">delete your account</RouterLink>.
    </p>
  </SettingsSubpage>
</template>
