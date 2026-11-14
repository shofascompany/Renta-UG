<script setup>
import { reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { MailCheck } from '@lucide/vue'
import { useAuthStore } from '@/stores/auth'
import Logo from '@/components/Logo.vue'

const auth = useAuthStore()
const router = useRouter()

const form = reactive({ name: '', email: '', password: '' })
const error = ref('')
const busy = ref(false)
const checkEmail = ref(false)

async function submit() {
  error.value = ''
  busy.value = true
  try {
    const signedIn = await auth.signUp({ name: form.name.trim(), email: form.email.trim(), password: form.password })
    if (signedIn) router.push(auth.home)
    else checkEmail.value = true
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
      <div class="mb-10 flex justify-center"><Logo /></div>

      <div v-if="checkEmail" class="text-center">
        <div class="mx-auto mb-4 flex size-12 items-center justify-center rounded-full bg-brand-50">
          <MailCheck class="size-6 text-brand-600" />
        </div>
        <h1 class="text-xl font-semibold text-slate-900">Confirm your email</h1>
        <p class="mt-2 text-sm text-slate-500">We sent a link to <strong>{{ form.email }}</strong>. Click it, then sign in.</p>
        <RouterLink to="/login" class="btn-secondary mt-6 w-full">Back to sign in</RouterLink>
      </div>

      <template v-else>
        <h1 class="text-center text-2xl font-semibold tracking-tight text-slate-900">Create your account</h1>
        <p class="mt-2 text-center text-sm text-slate-500">After signing up, you'll connect to your landlord with the code they give you.</p>

        <form class="mt-8 space-y-4" @submit.prevent="submit">
          <div>
            <label class="label" for="name">Full name</label>
            <input id="name" v-model="form.name" class="input" required autocomplete="name" />
          </div>
          <div>
            <label class="label" for="email">Email</label>
            <input id="email" v-model="form.email" type="email" class="input" placeholder="you@example.com" required autocomplete="email" />
          </div>
          <div>
            <label class="label" for="password">Password</label>
            <input id="password" v-model="form.password" type="password" class="input" minlength="8" required autocomplete="new-password" />
            <p class="mt-1 text-xs text-slate-500">At least 8 characters.</p>
          </div>
          <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
          <button :data-busy="Boolean(busy)" type="submit" class="btn-primary w-full" :disabled="busy">{{ busy ? 'Creating account…' : 'Create account' }}</button>
        </form>

        <p class="mt-8 text-center text-sm text-slate-500">
          Already have an account?
          <RouterLink to="/login" class="font-medium text-brand-600 hover:text-brand-700">Sign in</RouterLink>
        </p>
      </template>
    </div>
  </div>
</template>
