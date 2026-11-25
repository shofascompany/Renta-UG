<script setup>
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { ArrowLeft } from '@lucide/vue'
import { useAuthStore } from '@/stores/auth'
import { SITE } from '@/lib/site'
import { AUDIENCES, legalFor } from '@/lib/legal'
import Logo from '@/components/Logo.vue'

// Public pages the app stores ask for: Privacy policy, Terms, and how to delete an account.
// They open without signing in. The texts live in src/lib/legal.js (shared with Settings → Terms).
// Someone signed in only ever sees the text of their own kind of account. A link with ?for=tenant or ?for=landlord
// (sign-up, setting a password) shows only that one. A visitor chooses which they are.
const route = useRoute()
const auth = useAuthStore()
const asked = computed(() => (route.query.for in AUDIENCES ? route.query.for : null))
const own = computed(() => (auth.isLandlord ? 'landlord' : auth.isTenant ? 'tenant' : null))
const audience = computed(() => own.value ?? asked.value ?? 'tenant')
const choose = computed(() => !own.value && route.query.only !== '1')
const page = computed(() => legalFor(route.meta.page, audience.value))
const keep = computed(() => (own.value ? {} : { for: audience.value, ...(choose.value ? {} : { only: '1' }) }))
</script>

<template>
  <div class="min-h-dvh bg-white">
    <header class="border-b border-slate-200/70">
      <div class="mx-auto flex h-16 max-w-3xl items-center justify-between px-4 sm:px-6">
        <Logo />
        <RouterLink to="/" class="inline-flex items-center gap-1.5 text-sm font-medium text-slate-600 hover:text-slate-900"><ArrowLeft class="size-4" /> Home</RouterLink>
      </div>
    </header>
    <main class="mx-auto max-w-3xl px-4 py-10 sm:px-6 sm:py-14">
      <h1 class="text-3xl font-extrabold tracking-tight text-slate-900 sm:text-4xl">{{ page.title }}</h1>
      <p class="mt-2 text-sm text-slate-500">Updated {{ SITE.updated }}</p>
      <div v-if="choose" class="mt-5 grid grid-cols-2 rounded-2xl bg-slate-100 p-1 text-sm sm:w-80" role="group" aria-label="Who are you?">
        <RouterLink v-for="(label, key) in AUDIENCES" :key="key" :to="{ path: route.path, query: { for: key } }" replace class="flex h-10 items-center justify-center rounded-xl font-medium transition" :class="audience === key ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500'" :aria-current="audience === key ? 'true' : undefined">{{ label }}</RouterLink>
      </div>
      <p class="mt-5 leading-relaxed text-slate-700">{{ page.intro }}</p>
      <section v-for="s in page.sections" :key="s.h" class="mt-8">
        <h2 class="text-lg font-bold text-slate-900">{{ s.h }}</h2>
        <p v-for="(t, i) in s.p" :key="i" class="mt-2 leading-relaxed text-slate-600">{{ t }}</p>
      </section>
      <nav class="mt-12 flex flex-wrap gap-x-5 gap-y-2 border-t border-slate-200 pt-6 text-sm text-slate-500">
        <RouterLink :to="{ path: '/privacy', query: keep }" class="hover:text-slate-900">Privacy</RouterLink>
        <RouterLink :to="{ path: '/terms', query: keep }" class="hover:text-slate-900">Terms</RouterLink>
        <RouterLink :to="{ path: '/delete-account', query: keep }" class="hover:text-slate-900">Delete account</RouterLink>
      </nav>
    </main>
  </div>
</template>
