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

// ── Live email / phone check ──
// One box takes an email OR a phone number. As soon as either is complete we look it up:
// ✓ tenant / landlord, ✗ no account, or a first-time landlord (no password needed yet).
const status = ref('idle') // idle | checking | first_login | landlord | tenant | suspended | not_found | unknown
let timer = null
let seq = 0
const complete = (v) => /^[^\s@]+@[^\s@]+\.[a-z]{2,}$/i.test(v)
// Ugandan style numbers: 0772123456, 772123456, +256772123456, 256 772 123 456
const completePhone = (v) => /^(?:\+?256|0)?[1-9]\d{8}$/.test(v.replace(/[\s\-().]/g, ''))
const isPhone = computed(() => !email.value.includes('@') && /^[+\d\s\-().]+$/.test(email.value.trim()))
const identifier = () => (isPhone.value ? email.value.replace(/[\s\-().]/g, '') : email.value.trim().toLowerCase())

watch(email, (value) => {
  clearTimeout(timer)
  error.value = ''
  const phone = isPhone.value
  const addr = identifier()
  if (phone ? !completePhone(value) : !complete(addr)) {
    status.value = 'idle'
    return
  }
  status.value = 'checking'
  const mine = ++seq
  timer = setTimeout(async () => {
    const result = phone ? await auth.phoneStatus(addr) : await auth.emailStatus(addr)
    if (mine === seq) status.value = result
  }, 350)
})

// ── Sign-in pace ──
// Signing in always takes at least SIGN_IN_MS, with a staged loader in the button.
const SIGN_IN_MS = 8_000
const stages = ['Verifying your details', 'Securing your session', 'Loading your account', 'Almost there']
const stage = ref(0)
const progress = ref(0)
let stageTimer = null

function startLoader() {
  stage.value = 0
  progress.value = 0
  requestAnimationFrame(() => requestAnimationFrame(() => (progress.value = 100))) // CSS transition fills the bar
  const started = Date.now()
  stageTimer = setInterval(() => {
    stage.value = Math.min(stages.length - 1, Math.floor(((Date.now() - started) / SIGN_IN_MS) * stages.length))
  }, 250)
  return new Promise((resolve) => setTimeout(resolve, SIGN_IN_MS))
}

function stopLoader() {
  clearInterval(stageTimer)
  progress.value = 0
}

const tenantFirst = computed(() => status.value === 'tenant_first_login') // app access just given by their landlord
const firstLogin = computed(() => status.value === 'first_login' || tenantFirst.value)
const blocked = computed(() => status.value === 'not_found' || status.value === 'suspended')
const found = computed(() => ['first_login', 'tenant_first_login', 'landlord', 'tenant'].includes(status.value))

// Tenant's first sign-in: nothing to type, go straight on to setting up the account
let autoTimer = null
watch(tenantFirst, (yes) => {
  clearTimeout(autoTimer)
  if (yes) autoTimer = setTimeout(() => !busy.value && tenantFirst.value && signIn(), 1200)
})

const hint = computed(
  () =>
    ({
      // The account type is never shown; only whether it's a first sign-in
      first_login: { ok: true, text: 'First sign-in: no password needed yet' },
      tenant_first_login: { ok: true, text: 'First sign-in: no password needed yet' },
      suspended: { ok: false, text: 'This account has been suspended. Please contact Renta UG.' },
      not_found: {
        ok: false,
        text: isPhone.value
          ? 'No account uses this phone number. Check it, try your email, or create an account.'
          : 'No account uses this email. Check it for typos, or create an account.',
      },
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
  const minimum = startLoader()
  try {
    const addr = identifier()
    const phone = isPhone.value
    if (firstLogin.value) {
      await (phone ? auth.firstLoginPhoneSignIn(addr) : auth.firstLoginSignIn(addr))
      await minimum
      router.push(auth.home) // the router sends them to "Create your password"
      return
    }
    await (phone ? auth.phoneSignIn(addr, password.value) : auth.signIn(addr, password.value))
    await minimum
    const redirect = route.query.redirect
    router.push(typeof redirect === 'string' && redirect.startsWith('/') ? redirect : auth.home)
  } catch (e) {
    error.value = /invalid login/i.test(e.message) && found.value ? 'Incorrect password. Please try again.' : e.message
  } finally {
    stopLoader()
    busy.value = false
  }
}

async function forgot() {
  error.value = ''
  if (!email.value.trim()) {
    error.value = 'Enter your email first.'
    return
  }
  if (isPhone.value) {
    error.value = 'To reset your password, enter your email address instead of your phone number.'
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
        <!-- Email or phone number with live ✓ / ✗ -->
        <div>
          <label class="label" for="email">Email or phone number</label>
          <div class="relative">
            <input
              id="email"
              v-model="email"
              type="text"
              class="input pr-10"
              :class="{
                'border-emerald-500 focus:border-emerald-500': found,
                'border-red-500 focus:border-red-500': blocked,
              }"
              placeholder="you@gmail.com or 0772 123456"
              required
              :disabled="busy"
              autocomplete="username"
              autocapitalize="off"
              spellcheck="false"
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
              <KeyRound class="size-4 shrink-0" />
              {{ tenantFirst ? 'No password yet. Setting up your account…' : 'No password yet. Just tap Continue below.' }}
            </p>
          </div>
        </div>

        <p v-if="firstLogin" class="text-sm text-slate-600">
          <template v-if="tenantFirst">Welcome to Renta! Your landlord has set up your account. Next, add your email and create your password.</template>
          <template v-else>Welcome to Renta! As this is your first sign-in, you'll create your own password on the next page.</template>
        </p>
        <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
        <p v-if="info" class="text-sm text-emerald-700">{{ info }}</p>
        <button
          type="submit"
          class="btn-primary relative w-full overflow-hidden"
          :class="busy && 'cursor-wait disabled:opacity-100'"
          :disabled="busy || blocked || status === 'checking'"
          :aria-busy="busy"
        >
          <span v-if="busy" class="flex items-center justify-center gap-2.5" role="status" aria-live="polite">
            <Loader2 class="size-4.5 animate-spin" aria-hidden="true" />
            <Transition
              mode="out-in"
              enter-active-class="transition duration-300 ease-out"
              enter-from-class="translate-y-1.5 opacity-0"
              leave-active-class="transition duration-200 ease-in"
              leave-to-class="-translate-y-1.5 opacity-0"
            >
              <span :key="stage">{{ stages[stage] }}…</span>
            </Transition>
          </span>
          <template v-else>{{ tenantFirst ? 'Continue: set up my account' : firstLogin ? 'Continue: create my password' : 'Sign in' }}</template>
          <!-- Progress line along the bottom of the button -->
          <span
            v-if="busy"
            class="absolute inset-x-0 bottom-0 h-0.5 bg-white/20"
            aria-hidden="true"
          >
            <span
              class="block h-full bg-white/80 ease-linear"
              :style="{ width: progress + '%', transitionProperty: 'width', transitionDuration: progress ? SIGN_IN_MS + 'ms' : '0ms' }"
            />
          </span>
        </button>
      </form>

      <p class="mt-8 text-center text-sm text-slate-500">
        New tenant?
        <RouterLink to="/signup" class="font-medium text-brand-600 hover:text-brand-700">Create an account</RouterLink>
      </p>
    </div>
  </div>
</template>
