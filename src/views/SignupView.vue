<script setup>
import { reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { Eye, EyeOff, ShieldCheck, Mail } from '@lucide/vue'
import { useAuthStore } from '@/stores/auth'
import { saveVerification } from '@/lib/verification'
import Logo from '@/components/Logo.vue'
import AuthBackground from '@/components/AuthBackground.vue'

const auth = useAuthStore()
const router = useRouter()

// Nothing is filled in for them
const form = reactive({ name: '', email: '', phone: '', password: '' })
const error = ref('')
const busy = ref(false)
const show = ref(false)

// Email: step 1 of 2. We email a 6-character code; the account is created when they enter it.
// Phone number: no email to verify, so the account is created straight away.
async function submit() {
  error.value = ''
  busy.value = true
  try {
    const email = form.email.trim().toLowerCase()
    const phone = form.phone.trim()
    if (!email || !phone) throw new Error('Enter both your email and your phone number.')
    if (phone.replace(/\D/g, '').length < 9) throw new Error('Enter a valid phone number.')
    const taken = await auth.phoneStatus(phone)
    if (taken !== 'not_found' && taken !== 'unknown') {
      throw new Error('This phone number is already used by another Renta account.')
    }
    const res = await auth.startSignUp({ name: form.name.trim(), email, password: form.password, phone })
    saveVerification({ email, expiresAt: Date.now() + res.expiresInMinutes * 60_000, resendAt: Date.now() + res.resendAfterSeconds * 1000 })
    router.push({ name: 'verify-email' })
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <div class="relative flex min-h-screen items-center justify-center px-4 py-12">
    <AuthBackground />
    <div class="relative z-10 w-full max-w-sm">
      <div class="mb-10 flex justify-center"><Logo /></div>

      <div>
        <h1 class="text-center text-2xl font-semibold tracking-tight text-slate-900">Create your account</h1>
        <p class="mt-2 text-center text-sm text-slate-500">
          Enter your email and phone number; you can sign in with either. After signing up, you'll connect to your landlord with the code they give you.
        </p>

        <form class="mt-8 space-y-4" @submit.prevent="submit">
          <div>
            <label class="label" for="name">Full name</label>
            <input id="name" v-model="form.name" class="input" required autocomplete="name" />
          </div>
          <div>
            <label class="label" for="email">Email</label>
            <input id="email" v-model="form.email" type="email" class="input" placeholder="you@gmail.com" required autocomplete="email" />
          </div>
          <div>
            <label class="label" for="phone">Phone number</label>
            <input id="phone" v-model="form.phone" type="tel" inputmode="tel" class="input" placeholder="0772 123456" required autocomplete="tel" />
            <p class="mt-1 text-xs text-slate-500">You can sign in with your email or this number.</p>
          </div>
          <div>
            <label class="label" for="password">Password</label>
            <div class="relative">
              <input id="password" v-model="form.password" :type="show ? 'text' : 'password'" class="input pr-11" minlength="8" required autocomplete="new-password" />
              <button type="button" class="absolute inset-y-0 right-0 flex w-11 items-center justify-center text-slate-400" :aria-label="show ? 'Hide password' : 'Show password'" @click="show = !show">
                <EyeOff v-if="show" class="size-4.5" /><Eye v-else class="size-4.5" />
              </button>
            </div>
            <p class="mt-1 text-xs text-slate-500">At least 8 characters, with letters and numbers.</p>
          </div>
          <p v-if="error" class="form-error" role="alert">
            {{ error }}
            <RouterLink v-if="/already exists/i.test(error)" to="/login" class="font-semibold underline">Sign in</RouterLink>
          </p>
          <button :data-busy="Boolean(busy)" type="submit" class="btn-primary w-full" :disabled="busy">
            <Mail class="size-4.5" />
            {{ busy ? 'Sending your code…' : 'Email me a code' }}
          </button>
        </form>

        <p class="mt-5 flex items-center justify-center gap-1.5 text-xs text-slate-500">
          <ShieldCheck class="size-3.5" /> Your account is only created after you verify
        </p>
      </div>

      <p class="mt-8 text-center text-sm text-slate-500">
        Already have an account?
        <RouterLink to="/login" class="font-medium text-brand-600 hover:text-brand-700">Sign in</RouterLink>
      </p>
    </div>
  </div>
</template>
