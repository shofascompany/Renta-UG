<script setup>
import { computed, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { CircleAlert, Eye, EyeOff, KeyRound } from '@lucide/vue'
import { useAuthStore } from '@/stores/auth'
import Logo from '@/components/Logo.vue'
import AuthBackground from '@/components/AuthBackground.vue'

// Step 2 of 2: opened from the emailed link (/reset-password?token=…). Save the new password for that
// account, then everything is signed out and they go back to the sign-in page.
const auth = useAuthStore()
const route = useRoute()
const router = useRouter()

const token = computed(() => (typeof route.query.token === 'string' ? route.query.token : ''))
const password = ref('')
const confirm = ref('')
const show = ref(false)
const error = ref('')
const busy = ref(false)

async function submit() {
  error.value = ''
  if (password.value.length < 8) return (error.value = 'Your password needs at least 8 characters.')
  if (password.value !== confirm.value) return (error.value = 'The two passwords do not match.')
  busy.value = true
  try {
    await auth.completePasswordReset(token.value, password.value)
    router.replace({ name: 'login', query: { reset: '1' } })
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

      <div v-if="!token" class="text-center">
        <div class="mx-auto mb-4 flex size-12 items-center justify-center rounded-full bg-red-50">
          <CircleAlert class="size-6 text-red-600" />
        </div>
        <h1 class="text-2xl font-semibold tracking-tight text-slate-900">This link isn't valid</h1>
        <p class="mt-2 text-sm text-slate-500">Open the link from your email again, or ask for a new one.</p>
        <RouterLink to="/forgot-password" class="btn-primary mt-6 w-full">Get a new link</RouterLink>
      </div>

      <template v-else>
        <h1 class="text-center text-2xl font-semibold tracking-tight text-slate-900">Choose a new password</h1>
        <p class="mt-2 text-center text-sm text-slate-500">Enter it twice. After saving, you'll sign in again with it.</p>

        <form class="mt-8 space-y-4" @submit.prevent="submit">
          <div>
            <label class="label" for="rp-new">New password</label>
            <div class="relative">
              <input id="rp-new" v-model="password" :type="show ? 'text' : 'password'" class="input pr-11" minlength="8" required autofocus autocomplete="new-password" />
              <button type="button" class="absolute inset-y-0 right-0 flex w-11 items-center justify-center text-slate-400" :aria-label="show ? 'Hide password' : 'Show password'" @click="show = !show">
                <EyeOff v-if="show" class="size-4.5" /><Eye v-else class="size-4.5" />
              </button>
            </div>
            <p class="mt-1 text-xs text-slate-500">At least 8 characters.</p>
          </div>
          <div>
            <label class="label" for="rp-confirm">Confirm new password</label>
            <input id="rp-confirm" v-model="confirm" :type="show ? 'text' : 'password'" class="input" minlength="8" required autocomplete="new-password" />
          </div>
          <p v-if="error" class="text-sm text-red-600">
            {{ error }}
            <RouterLink v-if="/expired|already used/i.test(error)" to="/forgot-password" class="font-semibold underline">Get a new link</RouterLink>
          </p>
          <button :data-busy="Boolean(busy)" type="submit" class="btn-primary w-full" :disabled="busy">
            <KeyRound class="size-4" /> {{ busy ? 'Saving…' : 'Save new password' }}
          </button>
        </form>
      </template>
    </div>
  </div>
</template>
