<script setup>
import { computed, nextTick, ref } from 'vue'
import { useRouter } from 'vue-router'
import { Mail, KeyRound, Eye, EyeOff, CheckCircle2, ArrowLeft, ArrowRight, Loader2 } from '@lucide/vue'
import { useAuthStore } from '@/stores/auth'
import Logo from '@/components/Logo.vue'

// Tenant's first sign-in after their landlord gave them app access (signed in with their phone):
// step 1 add their email, step 2 choose a password. Then straight into the app.
const auth = useAuthStore()
const router = useRouter()

const step = ref(1)
const email = ref('')
const password = ref('')
const confirm = ref('')
const show = ref(false)
const busy = ref(false)
const error = ref('')
const done = ref(false)
const pwInput = ref(null)

const firstName = computed(() => auth.profile?.full_name?.split(' ')[0] ?? '')
const emailOk = computed(() => /^[^\s@]+@[^\s@]+\.[a-z]{2,}$/i.test(email.value.trim()))
const rules = computed(() => [
  { ok: password.value.length >= 8, label: 'At least 8 characters' },
  { ok: /[A-Za-z]/.test(password.value) && /\d/.test(password.value), label: 'Letters and numbers' },
])
const mismatch = computed(() => confirm.value && password.value !== confirm.value)
const passwordOk = computed(() => rules.value.every((r) => r.ok) && password.value === confirm.value)

async function next() {
  error.value = ''
  if (!emailOk.value) return (error.value = 'Enter a valid email address.')
  step.value = 2
  await nextTick()
  pwInput.value?.focus()
}

async function finish() {
  error.value = ''
  if (!passwordOk.value) {
    error.value = mismatch.value ? 'The passwords do not match.' : 'Your password needs at least 8 characters, with letters and numbers.'
    return
  }
  busy.value = true
  try {
    await auth.completeTenantAccount({ email: email.value.trim(), password: password.value })
    done.value = true
    setTimeout(() => router.replace(auth.home), 1400)
  } catch (e) {
    error.value = e.message
    if (/email/i.test(e.message)) step.value = 1
  } finally {
    busy.value = false
  }
}

async function signOut() {
  await auth.signOut()
  router.push('/login')
}
</script>

<template>
  <div class="flex min-h-screen items-center justify-center bg-white px-4 py-12">
    <div class="w-full max-w-sm">
      <div class="mb-8 flex justify-center"><Logo /></div>

      <!-- Done -->
      <div v-if="done" class="text-center">
        <div class="pop mx-auto flex size-16 items-center justify-center rounded-full bg-emerald-50">
          <CheckCircle2 class="size-8 text-emerald-600" />
        </div>
        <h1 class="mt-5 text-2xl font-semibold tracking-tight text-slate-900">You're all set</h1>
        <p class="mt-2 text-sm text-slate-500">From now on, sign in with your email or phone number and your new password.</p>
        <Loader2 class="mx-auto mt-6 size-5 animate-spin text-slate-400" />
      </div>

      <template v-else>
        <h1 class="text-center text-2xl font-semibold tracking-tight text-slate-900">Welcome{{ firstName ? `, ${firstName}` : '' }}</h1>
        <p class="mt-2 text-center text-sm text-slate-500">Your landlord has set up your Renta account. Two quick steps to finish.</p>

        <!-- Steps -->
        <ol class="mt-7 grid grid-cols-2 gap-2" aria-label="Progress">
          <li v-for="(s, i) in ['Your email', 'Your password']" :key="s">
            <div class="h-1 rounded-full transition-colors duration-300" :class="step > i ? 'bg-brand-600' : 'bg-slate-200'" />
            <p class="mt-2 text-xs font-medium" :class="step === i + 1 ? 'text-slate-900' : 'text-slate-400'">{{ i + 1 }}. {{ s }}</p>
          </li>
        </ol>

        <!-- Step 1: email -->
        <form v-if="step === 1" class="mt-6 space-y-4" @submit.prevent="next">
          <div>
            <label class="label" for="ca-email">Email address</label>
            <div class="relative">
              <Mail class="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-slate-400" />
              <input
                id="ca-email"
                v-model="email"
                type="email"
                class="input pl-9"
                placeholder="you@gmail.com"
                autocomplete="email"
                autocapitalize="off"
                required
                autofocus
              />
            </div>
            <p class="mt-1.5 text-xs text-slate-500">Used to sign in and to reset your password if you forget it.</p>
          </div>
          <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
          <button type="submit" class="btn-primary h-11 w-full" :disabled="!emailOk">
            Continue <ArrowRight class="size-4" />
          </button>
        </form>

        <!-- Step 2: password -->
        <form v-else class="mt-6 space-y-4" @submit.prevent="finish">
          <button type="button" class="-mt-1 inline-flex items-center gap-1 text-xs font-medium text-slate-500 hover:text-slate-800" @click="step = 1; error = ''">
            <ArrowLeft class="size-3.5" /> {{ email }}
          </button>
          <div>
            <label class="label" for="ca-pw">Create a password</label>
            <div class="relative">
              <KeyRound class="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-slate-400" />
              <input
                id="ca-pw"
                ref="pwInput"
                v-model="password"
                :type="show ? 'text' : 'password'"
                class="input pr-10 pl-9"
                autocomplete="new-password"
                required
              />
              <button
                type="button"
                class="absolute inset-y-0 right-0 flex items-center px-3 text-slate-400 hover:text-slate-700"
                :aria-label="show ? 'Hide password' : 'Show password'"
                @click="show = !show"
              >
                <component :is="show ? EyeOff : Eye" class="size-4" />
              </button>
            </div>
            <ul class="mt-2 flex flex-wrap gap-x-4 gap-y-1">
              <li v-for="r in rules" :key="r.label" class="flex items-center gap-1.5 text-xs" :class="r.ok ? 'text-emerald-700' : 'text-slate-400'">
                <CheckCircle2 class="size-3.5" /> {{ r.label }}
              </li>
            </ul>
          </div>
          <div>
            <label class="label" for="ca-pw2">Confirm password</label>
            <input id="ca-pw2" v-model="confirm" :type="show ? 'text' : 'password'" class="input" autocomplete="new-password" required />
            <p v-if="mismatch" class="mt-1 text-xs text-red-600">Passwords do not match.</p>
          </div>
          <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
          <button :data-busy="Boolean(busy)" type="submit" class="btn-primary h-11 w-full" :disabled="busy || !passwordOk">
            <Loader2 v-if="busy" class="size-4 animate-spin" />
            {{ busy ? 'Finishing…' : 'Finish setup' }}
          </button>
        </form>

        <p class="mt-8 text-center text-xs text-slate-400">
          Not you?
          <button class="font-medium text-slate-500 hover:text-slate-700" @click="signOut">Sign out</button>
        </p>
      </template>
    </div>
  </div>
</template>

<style scoped>
.pop {
  animation: pop 0.45s cubic-bezier(0.34, 1.56, 0.64, 1) both;
}
@keyframes pop {
  from { opacity: 0; transform: scale(0.6); }
}
@media (prefers-reduced-motion: reduce) {
  .pop { animation: none; }
}
</style>
