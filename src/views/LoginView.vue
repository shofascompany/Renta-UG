<script setup>
import { ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { isConfigured } from '@/lib/supabase'
import Logo from '@/components/Logo.vue'

const auth = useAuthStore()
const router = useRouter()
const route = useRoute()

const email = ref('')
const password = ref('')
const error = ref('')
const info = ref('')
const busy = ref(false)

// In the background: is this a landlord signing in for the first time? If so, hide the password.
const firstLogin = ref(false)
let checkTimer = null
let checkSeq = 0
watch(email, (value) => {
  clearTimeout(checkTimer)
  firstLogin.value = false
  const addr = value.trim().toLowerCase()
  if (!/^\S+@\S+\.\S+$/.test(addr)) return
  const seq = ++checkSeq
  checkTimer = setTimeout(async () => {
    const result = await auth.isFirstLogin(addr)
    if (seq === checkSeq) firstLogin.value = result
  }, 400)
})

async function signIn() {
  error.value = ''
  info.value = ''
  busy.value = true
  try {
    const addr = email.value.trim()
    // Re-check on submit in case the background check hadn't finished yet
    if (firstLogin.value || (!password.value && (await auth.isFirstLogin(addr)))) {
      await auth.firstLoginSignIn(addr)
      router.push(auth.home) // the router sends them to "set your password"
      return
    }
    await auth.signIn(addr, password.value)
    const redirect = route.query.redirect
    router.push(typeof redirect === 'string' && redirect.startsWith('/') ? redirect : auth.home)
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}

async function forgot() {
  error.value = ''
  if (!email.value.trim()) {
    error.value = 'Enter your email first.'
    return
  }
  try {
    await auth.resetPassword(email.value.trim())
    info.value = 'Check your email for a password reset link.'
  } catch (e) {
    error.value = e.message
  }
}
</script>

<template>
  <div class="flex min-h-screen items-center justify-center bg-white px-4 py-12">
    <div class="w-full max-w-sm">
      <div class="mb-10 flex justify-center"><Logo /></div>

      <h1 class="text-center text-2xl font-semibold tracking-tight text-slate-900">Welcome back</h1>
      <p class="mt-2 text-center text-sm text-slate-500">Landlords and tenants sign in here.</p>

      <p v-if="!isConfigured" class="mt-6 rounded-lg bg-amber-50 p-3 text-sm text-amber-800">
        Supabase isn't configured. Add your project keys to <code>.env</code> and restart the dev server.
      </p>

      <form class="mt-8 space-y-4" @submit.prevent="signIn">
        <div>
          <label class="label" for="email">Email</label>
          <input id="email" v-model="email" type="email" class="input" placeholder="you@example.com" required autocomplete="email" />
        </div>
        <!-- Hidden for a landlord's first sign-in (they set their password on the next page) -->
        <div v-if="!firstLogin">
          <div class="flex items-center justify-between">
            <label class="label" for="password">Password</label>
            <button type="button" class="mb-1.5 text-xs font-medium text-brand-600 hover:text-brand-700" @click="forgot">Forgot password?</button>
          </div>
          <input id="password" v-model="password" type="password" class="input" placeholder="••••••••" required autocomplete="current-password" />
        </div>
        <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
        <p v-if="info" class="text-sm text-emerald-700">{{ info }}</p>
        <button type="submit" class="btn-primary w-full" :disabled="busy">{{ busy ? 'Signing in…' : 'Sign in' }}</button>
      </form>

      <p class="mt-8 text-center text-sm text-slate-500">
        New tenant?
        <RouterLink to="/signup" class="font-medium text-brand-600 hover:text-brand-700">Create an account</RouterLink>
      </p>
    </div>
  </div>
</template>
