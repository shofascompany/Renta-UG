<script setup>
import { onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { CircleAlert, Eye, Loader2 } from '@lucide/vue'
import { api } from '@/lib/api'
import { useAuthStore } from '@/stores/auth'
import { deviceId, insideApp, isAndroid, setAppOnly } from '@/lib/installApp'
import Logo from '@/components/Logo.vue'
import AuthBackground from '@/components/AuthBackground.vue'

// The one-time link from a landlord's WhatsApp message: /i/<random>. It carries nothing about the tenant. When it
// works it goes on to the landing site; from there, signing in on Android needs the app (see the router).
const route = useRoute()
const router = useRouter()
const auth = useAuthStore()
const state = ref('checking') // checking | preview | expired | used | invalid | error

const PROBLEM = {
  expired: ['This link has expired', 'Ask your landlord to send you a fresh one.'],
  used: ['This link has already been used', 'It works once. If you have set up your account, sign in; otherwise ask your landlord for a fresh link.'],
  invalid: ["This link isn't valid", 'Ask your landlord to send it again.'],
  error: ["The link couldn't be opened", 'Check your internet connection and try again.'],
}

async function open() {
  // A landlord looking at their own link must not use it up
  if (auth.isAuthenticated && (auth.isLandlord || auth.isSuperadmin)) return (state.value = 'preview')
  state.value = 'checking'
  try {
    const res = await api('/api/invite/open', { token: String(route.params.token ?? ''), device: deviceId() })
    if (res.status !== 'ok') return (state.value = PROBLEM[res.status] ? res.status : 'error')
  } catch {
    return (state.value = 'error')
  }
  if (isAndroid() && !insideApp()) setAppOnly()
  router.replace(insideApp() ? { name: 'login' } : { name: 'landing' })
}
onMounted(open)
</script>

<template>
  <div class="relative flex min-h-screen items-center justify-center px-4 py-12">
    <AuthBackground />
    <div class="relative z-10 w-full max-w-sm text-center">
      <div class="mb-8 flex justify-center"><Logo :link="false" /></div>

      <div v-if="state === 'checking'" role="status">
        <Loader2 class="mx-auto size-8 animate-spin text-brand-600" />
        <p class="mt-4 font-medium text-slate-900">Opening Renta UG…</p>
      </div>

      <div v-else-if="state === 'preview'">
        <span class="mx-auto flex size-12 items-center justify-center rounded-full bg-brand-50"><Eye class="size-6 text-brand-600" /></span>
        <h1 class="mt-4 text-2xl font-semibold tracking-tight text-slate-900">This is your tenant's link</h1>
        <p class="mt-2 text-sm text-slate-500">You are signed in as a landlord, so it was not used up. It still works for your tenant.</p>
        <RouterLink :to="auth.home" class="btn-primary mt-6 w-full">Back to my dashboard</RouterLink>
      </div>

      <div v-else>
        <span class="mx-auto flex size-12 items-center justify-center rounded-full bg-amber-50"><CircleAlert class="size-6 text-amber-600" /></span>
        <h1 class="mt-4 text-2xl font-semibold tracking-tight text-slate-900">{{ PROBLEM[state][0] }}</h1>
        <p class="mt-2 text-sm text-slate-500">{{ PROBLEM[state][1] }}</p>
        <button v-if="state === 'error'" type="button" class="btn-primary mt-6 w-full" @click="open">Try again</button>
        <RouterLink v-else to="/" class="btn-secondary mt-6 w-full">Go to Renta UG</RouterLink>
      </div>
    </div>
  </div>
</template>
