<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { ShieldCheck } from '@lucide/vue'
import { useAuthStore } from '@/stores/auth'
import { isConfigured } from '@/lib/supabase'

// Main admin sign-in at /admin2026. Only the superadmin account (ADMIN_* in .env) can get in.
const auth = useAuthStore()
const router = useRouter()

const email = ref('')
const password = ref('')
const error = ref('')
const busy = ref(false)

async function signIn() {
  error.value = ''
  busy.value = true
  try {
    await auth.signIn(email.value.trim(), password.value, 'admin')
    router.push(auth.home)
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <div class="flex min-h-screen items-center justify-center bg-white px-4 py-12">
    <div class="w-full max-w-sm">
      <div class="mx-auto mb-6 flex size-12 items-center justify-center rounded-xl bg-slate-900">
        <ShieldCheck class="size-6 text-white" />
      </div>
      <p class="text-center text-xs font-semibold tracking-widest text-slate-400 uppercase">Renta UG</p>
      <h1 class="mt-1 text-center text-2xl font-semibold tracking-tight text-slate-900">Admin console</h1>
      <p class="mt-2 text-center text-sm text-slate-500">Restricted area. Main administrator only.</p>

      <p v-if="!isConfigured" class="mt-6 rounded-lg bg-amber-50 p-3 text-sm text-amber-800">
        Supabase isn't configured. Add your project keys to <code>.env</code> and restart the dev server.
      </p>

      <form class="card mt-8 space-y-4 p-6" @submit.prevent="signIn">
        <div>
          <label class="label" for="aemail">Admin email</label>
          <input id="aemail" v-model="email" type="email" class="input" required autocomplete="username" />
        </div>
        <div>
          <label class="label" for="apass">Password</label>
          <input id="apass" v-model="password" type="password" class="input" required autocomplete="current-password" />
        </div>
        <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
        <button type="submit" class="btn w-full bg-slate-900 text-white hover:bg-slate-800" :disabled="busy">
          {{ busy ? 'Signing in…' : 'Sign in to console' }}
        </button>
      </form>
    </div>
  </div>
</template>
