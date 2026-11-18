<script setup>
import { ref } from 'vue'
import { useRoute } from 'vue-router'
import { ArrowLeft, Mail, MailCheck, Send } from '@lucide/vue'
import { useAuthStore } from '@/stores/auth'
import Logo from '@/components/Logo.vue'
import AuthBackground from '@/components/AuthBackground.vue'

// Step 1 of 2: enter the email, the app emails a reset link (step 2 is /reset-password).
const auth = useAuthStore()
const route = useRoute()

const email = ref(typeof route.query.email === 'string' && route.query.email.includes('@') ? route.query.email : '')
const error = ref('')
const busy = ref(false)
const sent = ref(false)

async function submit() {
  error.value = ''
  busy.value = true
  try {
    await auth.requestPasswordReset(email.value.trim())
    sent.value = true
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

      <div v-if="sent" class="text-center">
        <div class="mx-auto mb-4 flex size-12 items-center justify-center rounded-full bg-brand-50">
          <MailCheck class="size-6 text-brand-600" />
        </div>
        <h1 class="text-2xl font-semibold tracking-tight text-slate-900">Check your email</h1>
        <p class="mt-2 text-sm text-slate-500">
          If an account uses <strong class="text-slate-700">{{ email }}</strong>, we've sent a link to reset the password. It works for 1 hour.
        </p>
        <p class="mt-3 text-xs text-slate-500">Nothing there? Look in Spam or Junk, or try again.</p>
        <button type="button" class="btn-secondary mt-6 w-full" @click="sent = false">Use a different email</button>
        <RouterLink to="/login" class="mt-3 inline-block text-sm font-medium text-brand-600 hover:text-brand-700">Back to sign in</RouterLink>
      </div>

      <template v-else>
        <h1 class="text-center text-2xl font-semibold tracking-tight text-slate-900">Forgot your password?</h1>
        <p class="mt-2 text-center text-sm text-slate-500">Enter your email and we'll send you a link to choose a new one.</p>

        <form class="mt-8 space-y-4" @submit.prevent="submit">
          <div>
            <label class="label" for="fp-email">Email</label>
            <div class="relative">
              <Mail class="pointer-events-none absolute top-1/2 left-3.5 size-4.5 -translate-y-1/2 text-slate-400" />
              <input
                id="fp-email"
                v-model="email"
                type="email"
                class="input pl-10"
                placeholder="you@gmail.com"
                required
                autofocus
                autocomplete="email"
                autocapitalize="off"
                spellcheck="false"
              />
            </div>
          </div>
          <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
          <button :data-busy="Boolean(busy)" type="submit" class="btn-primary w-full" :disabled="busy">
            <Send class="size-4" /> {{ busy ? 'Sending…' : 'Send reset link' }}
          </button>
        </form>

        <p class="mt-8 text-center text-sm text-slate-500">
          <RouterLink to="/login" class="inline-flex items-center gap-1 font-medium text-brand-600 hover:text-brand-700"><ArrowLeft class="size-4" /> Back to sign in</RouterLink>
        </p>
      </template>
    </div>
  </div>
</template>
