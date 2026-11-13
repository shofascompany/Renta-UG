<script setup>
import { computed } from 'vue'
import { ChevronLeft } from '@lucide/vue'
import { useAuthStore } from '@/stores/auth'

// Frame for one settings screen: "← Settings" back link, title, description, roomy content.
defineProps({ title: String, subtitle: String, icon: [Object, Function] })

const auth = useAuthStore()
const back = computed(() => `${auth.home}/settings`)
</script>

<template>
  <div class="mx-auto max-w-2xl">
    <RouterLink
      :to="back"
      class="-ml-2 mb-6 inline-flex items-center gap-1 rounded-lg px-2 py-1.5 text-sm font-medium text-slate-500 transition-colors hover:bg-slate-50 hover:text-slate-900"
    >
      <ChevronLeft class="size-4" /> Settings
    </RouterLink>

    <div class="mb-8 flex items-start gap-4">
      <div v-if="icon" class="flex size-12 shrink-0 items-center justify-center rounded-xl bg-brand-50 text-brand-600">
        <component :is="icon" class="size-6" />
      </div>
      <div>
        <h1 class="text-2xl font-semibold tracking-tight text-slate-900">{{ title }}</h1>
        <p v-if="subtitle" class="mt-1 text-sm text-slate-500">{{ subtitle }}</p>
      </div>
    </div>

    <div class="space-y-6">
      <slot />
    </div>
  </div>
</template>
