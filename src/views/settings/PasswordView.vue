<script setup>
import { computed, ref } from 'vue'
import { KeyRound, Eye, EyeOff, CheckCircle2 } from '@lucide/vue'
import { useAuthStore } from '@/stores/auth'
import SettingsSubpage from '@/components/SettingsSubpage.vue'

const auth = useAuthStore()

const current = ref('')
const next = ref('')
const confirm = ref('')
const show = ref(false)
const busy = ref(false)
const error = ref('')
const done = ref(false)

const rules = computed(() => [
  { ok: next.value.length >= 8, label: 'At least 8 characters' },
  { ok: /[A-Za-z]/.test(next.value) && /\d/.test(next.value), label: 'Contains letters and numbers' },
  { ok: Boolean(next.value) && next.value !== current.value, label: 'Different from your current password' },
])
const mismatch = computed(() => confirm.value && next.value !== confirm.value)
const valid = computed(() => current.value && rules.value.every((r) => r.ok) && next.value === confirm.value)

async function save() {
  error.value = ''
  if (!valid.value) {
    error.value = mismatch.value ? 'The new passwords do not match.' : 'Please complete all the requirements below.'
    return
  }
  busy.value = true
  try {
    await auth.changePassword(current.value, next.value)
    done.value = true
    current.value = next.value = confirm.value = ''
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <SettingsSubpage title="Change password" subtitle="Use a password you don't use anywhere else." :icon="KeyRound">
    <div v-if="done" class="card flex items-start gap-4 border-emerald-200 bg-emerald-50 p-5">
      <CheckCircle2 class="mt-0.5 size-5 shrink-0 text-emerald-700" />
      <div class="flex-1 text-sm">
        <p class="font-medium text-emerald-700">Password changed</p>
        <p class="mt-0.5 text-slate-600">Use your new password the next time you sign in.</p>
      </div>
      <button class="btn-ghost shrink-0" @click="done = false">Change again</button>
    </div>

    <form v-else class="card space-y-5 p-6" @submit.prevent="save">
      <div>
        <label class="label" for="pw-current">Current password</label>
        <input id="pw-current" v-model="current" :type="show ? 'text' : 'password'" class="input" required autocomplete="current-password" />
      </div>

      <div>
        <label class="label" for="pw-new">New password</label>
        <input id="pw-new" v-model="next" :type="show ? 'text' : 'password'" class="input" required autocomplete="new-password" />
        <ul class="mt-2 space-y-1">
          <li v-for="r in rules" :key="r.label" class="flex items-center gap-2 text-xs" :class="r.ok ? 'text-emerald-700' : 'text-slate-500'">
            <CheckCircle2 class="size-3.5" :class="r.ok ? '' : 'opacity-40'" /> {{ r.label }}
          </li>
        </ul>
      </div>

      <div>
        <label class="label" for="pw-confirm">Confirm new password</label>
        <input id="pw-confirm" v-model="confirm" :type="show ? 'text' : 'password'" class="input" required autocomplete="new-password" />
        <p v-if="mismatch" class="mt-1 text-xs text-red-600">Passwords do not match.</p>
      </div>

      <button type="button" class="inline-flex cursor-pointer items-center gap-2 text-sm text-slate-500 hover:text-slate-800" @click="show = !show">
        <component :is="show ? EyeOff : Eye" class="size-4" /> {{ show ? 'Hide passwords' : 'Show passwords' }}
      </button>

      <p v-if="error" class="text-sm text-red-600">{{ error }}</p>

      <div class="flex justify-end pt-1">
        <button type="submit" class="btn-primary" :disabled="busy || !valid">{{ busy ? 'Saving…' : 'Update password' }}</button>
      </div>
    </form>

    <p class="px-1 text-xs text-slate-400">
      Forgot your current password? Sign out, then use <strong>Forgot password</strong> on the sign-in page.
    </p>
  </SettingsSubpage>
</template>
