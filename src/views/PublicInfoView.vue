<script setup>
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { ArrowLeft } from '@lucide/vue'
import { SITE } from '@/lib/site'
import { LEGAL } from '@/lib/legal'
import Logo from '@/components/Logo.vue'

// Public pages the app stores ask for: Privacy policy, Terms, and how to delete an account.
// They open without signing in. The texts live in src/lib/legal.js (shared with Settings → Terms).
const route = useRoute()
const page = computed(() => LEGAL[route.meta.page] ?? LEGAL.privacy)
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
      <p class="mt-5 leading-relaxed text-slate-700">{{ page.intro }}</p>
      <section v-for="s in page.sections" :key="s.h" class="mt-8">
        <h2 class="text-lg font-bold text-slate-900">{{ s.h }}</h2>
        <p v-for="(t, i) in s.p" :key="i" class="mt-2 leading-relaxed text-slate-600">{{ t }}</p>
      </section>
      <nav class="mt-12 flex flex-wrap gap-x-5 gap-y-2 border-t border-slate-200 pt-6 text-sm text-slate-500">
        <RouterLink to="/privacy" class="hover:text-slate-900">Privacy</RouterLink>
        <RouterLink to="/terms" class="hover:text-slate-900">Terms</RouterLink>
        <RouterLink to="/delete-account" class="hover:text-slate-900">Delete account</RouterLink>
      </nav>
    </main>
  </div>
</template>
