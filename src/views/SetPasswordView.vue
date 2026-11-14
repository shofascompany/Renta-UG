<script setup>
import { computed, ref } from 'vue'
import { useRouter } from 'vue-router'
import { KeyRound } from '@lucide/vue'
import { useAuthStore } from '@/stores/auth'
import Logo from '@/components/Logo.vue'

// Landlord's first sign-in: replace the temporary password from the main admin.
const auth = useAuthStore()
const router = useRouter()

const password = ref('')
const confirm = ref('')
const error = ref('')
const busy = ref(false)

const mismatch = computed(() => confirm.value && password.value !== confirm.value)
const firstName = computed(() => auth.user?.name?.split(' ')[0] ?? '')

async function save() {
  error.value = ''
  if (password.value.length < 8) {
    error.value = 'Use at least 8 characters.'
    return
  }
  if (mismatch.value) {
    error.value = 'The passwords do not match.'
    return
  }
  busy.value = true
  try {
    await auth.setOwnPassword(password.value)
    router.replace(auth.home)
  } catch (e) {
    error.value = e.message
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
      <div class="mb-10 flex justify-center"><Logo /></div>

      <div class="mx-auto mb-5 flex size-12 items-center justify-center rounded-full bg-brand-50">
        <KeyRound class="size-6 text-brand-600" />
      </div>
      <h1 class="text-center text-2xl font-semibold tracking-tight text-slate-900">Welcome{{ firstName ? `, ${firstName}` : '' }}</h1>
      <p class="mt-2 text-center text-sm text-slate-500">
        Create your password to finish setting up your account. You'll use it with your email every time you sign in from now on.
      </p>

      <form class="mt-8 space-y-4" @submit.prevent="save">
        <div>
          <label class="label" for="np">New password</label>
          <input id="np" v-model="password" type="password" class="input" minlength="8" required autocomplete="new-password" />
          <p class="mt-1 text-xs text-slate-500">At least 8 characters.</p>
        </div>
        <div>
          <label class="label" for="cp">Confirm password</label>
          <input id="cp" v-model="confirm" type="password" class="input" required autocomplete="new-password" />
          <p v-if="mismatch" class="mt-1 text-xs text-red-600">Passwords do not match.</p>
        </div>
        <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
        <button :data-busy="Boolean(busy)" type="submit" class="btn-primary w-full" :disabled="busy">{{ busy ? 'Saving…' : 'Save password & continue' }}</button>
      </form>

      <p class="mt-8 text-center text-xs text-slate-400">
        Signed in as {{ auth.user?.email }} ·
        <button class="font-medium text-slate-500 hover:text-slate-700" @click="signOut">Sign out</button>
      </p>
    </div>
  </div>
</template>
