<script setup>
import { computed, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { CheckCircle2, XCircle, Loader2, KeyRound } from '@lucide/vue'
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

// ── Live email check ──
// As soon as the email is complete (e.g. ends in @gmail.com) we look it up:
// ✓ tenant / landlord, ✗ no account, or a first-time landlord (no password needed yet).
const status = ref('idle') // idle | checking | first_login | landlord | tenant | suspended | not_found | unknown
let timer = null
let seq = 0
const complete = (v) => /^[^\s@]+@[^\s@]+\.[a-z]{2,}$/i.test(v)

watch(email, (value) => {
  clearTimeout(timer)
  error.value = ''
  const addr = value.trim().toLowerCase()
  if (!complete(addr)) {
    status.value = 'idle'
    return
  }
  status.value = 'checking'
  const mine = ++seq
  timer = setTimeout(async () => {
    const result = await auth.emailStatus(addr)
    if (mine === seq) status.value = result
  }, 350)
})

const firstLogin = computed(() => status.value === 'first_login')
const blocked = computed(() => status.value === 'not_found' || status.value === 'suspended')
const found = computed(() => ['first_login', 'landlord', 'tenant'].includes(status.value))

const hint = computed(
  () =>
    ({
      first_login: { ok: true, text: 'Landlord account found: first sign-in' },
      landlord: { ok: true, text: 'Landlord account found' },
      tenant: { ok: true, text: 'Tenant account found' },
      suspended: { ok: false, text: 'This account has been suspended. Please contact Renta UG.' },
      not_found: { ok: false, text: 'No account uses this email. Check it for typos, or create an account.' },
    })[status.value],
)

async function signIn() {
  error.value = ''
  info.value = ''
  if (blocked.value) {
    error.value = hint.value.text
    return
  }
  busy.value = true
  try {
    const addr = email.value.trim().toLowerCase()
    if (firstLogin.value) {
      await auth.firstLoginSignIn(addr)
      router.push(auth.home) // the router sends them to "Create your password"
      return
    }
    await auth.signIn(addr, password.value)
    const redirect = route.query.redirect
    router.push(typeof redirect === 'string' && redirect.startsWith('/') ? redirect : auth.home)
  } catch (e) {
    error.value = /invalid login/i.test(e.message) && found.value ? 'Incorrect password. Please try again.' : e.message
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
        <!-- Email with live ✓ / ✗ -->
        <div>
          <label class="label" for="email">Email</label>
          <div class="relative">
            <input
              id="email"
              v-model="email"
              type="email"
              class="input pr-10"
              :class="{
                'border-emerald-500 focus:border-emerald-500': found,
                'border-red-500 focus:border-red-500': blocked,
              }"
              placeholder="you@gmail.com"
              required
              autocomplete="email"
              inputmode="email"
              aria-describedby="email-hint"
            />
            <span class="pointer-events-none absolute inset-y-0 right-3 flex items-center">
              <Loader2 v-if="status === 'checking'" class="size-4.5 animate-spin text-slate-400" />
              <CheckCircle2 v-else-if="found" class="size-5 text-emerald-600" aria-label="Account found" />
              <XCircle v-else-if="blocked" class="size-5 text-red-600" aria-label="No account" />
            </span>
          </div>
          <p v-if="status === 'checking'" id="email-hint" class="mt-1.5 text-xs text-slate-500">Checking…</p>
          <p
            v-else-if="hint"
            id="email-hint"
            class="mt-1.5 flex items-center gap-1.5 text-xs font-medium"
            :class="hint.ok ? 'text-emerald-700' : 'text-red-600'"
          >
            {{ hint.text }}
            <RouterLink v-if="status === 'not_found'" to="/signup" class="underline">Create account</RouterLink>
          </p>
        </div>

        <!-- Password: blurred and not needed for a landlord's first sign-in -->
        <div class="relative">
          <div :class="firstLogin && 'pointer-events-none blur-[3px] select-none'" :aria-hidden="firstLogin">
            <div class="flex items-center justify-between">
              <label class="label" for="password">Password</label>
              <button type="button" class="mb-1.5 text-xs font-medium text-brand-600 hover:text-brand-700" :tabindex="firstLogin ? -1 : 0" @click="forgot">
                Forgot password?
              </button>
            </div>
            <input
              id="password"
              v-model="password"
              type="password"
              class="input"
              placeholder="••••••••"
              :required="!firstLogin"
              :disabled="firstLogin"
              autocomplete="current-password"
            />
          </div>
          <div v-if="firstLogin" class="absolute inset-0 flex items-center justify-center">
            <p class="flex items-center gap-2 rounded-lg border border-brand-200 bg-brand-50 px-3 py-2 text-xs font-medium text-brand-700 shadow-sm">
              <KeyRound class="size-4 shrink-0" /> No password yet. Just tap Continue below.
            </p>
          </div>
        </div>

        <p v-if="firstLogin" class="text-sm text-slate-600">
          Welcome to Renta! As this is your first sign-in, you'll create your own password on the next page.
        </p>
        <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
        <p v-if="info" class="text-sm text-emerald-700">{{ info }}</p>
        <button type="submit" class="btn-primary w-full" :disabled="busy || blocked || status === 'checking'">
          {{ busy ? (firstLogin ? 'Opening…' : 'Signing in…') : firstLogin ? 'Continue: create my password' : 'Sign in' }}
        </button>
      </form>

      <p class="mt-8 text-center text-sm text-slate-500">
        New tenant?
        <RouterLink to="/signup" class="font-medium text-brand-600 hover:text-brand-700">Create an account</RouterLink>
      </p>
    </div>
  </div>
</template>
