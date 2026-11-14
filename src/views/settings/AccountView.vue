<script setup>
import { computed, ref, watch } from 'vue'
import { UserRound, Mail, ShieldCheck, CalendarDays, CheckCircle2, KeyRound, ChevronRight } from '@lucide/vue'
import { useAuthStore } from '@/stores/auth'
import { formatDate } from '@/utils/format'
import SettingsSubpage from '@/components/SettingsSubpage.vue'

const auth = useAuthStore()

const name = ref('')
const phone = ref('')
const reset = () => {
  name.value = auth.profile?.full_name ?? ''
  phone.value = auth.profile?.phone ?? ''
}
watch(() => auth.profile, reset, { immediate: true })

const dirty = computed(
  () => name.value.trim() !== (auth.profile?.full_name ?? '') || phone.value.trim() !== (auth.profile?.phone ?? ''),
)
const busy = ref(false)
const error = ref('')
const saved = ref(false)

async function save() {
  error.value = ''
  saved.value = false
  if (name.value.trim().length < 2) {
    error.value = 'Please enter your full name.'
    return
  }
  if (phone.value.trim() && !/^\+?[\d\s-]{9,15}$/.test(phone.value.trim())) {
    error.value = 'Enter a valid phone number, e.g. 0772 123456 or +256 772 123456.'
    return
  }
  busy.value = true
  try {
    await auth.updateProfile({ name: name.value, phone: phone.value })
    saved.value = true
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}

const details = computed(() => [
  { icon: Mail, label: 'Email', value: auth.user?.email },
  { icon: ShieldCheck, label: 'Account type', value: auth.isLandlord ? 'Landlord' : 'Tenant' },
  { icon: CalendarDays, label: 'Member since', value: formatDate(auth.profile?.created_at) },
])
</script>

<template>
  <SettingsSubpage title="Account details" subtitle="Your personal details on Renta." :icon="UserRound">
    <!-- Editable -->
    <form class="card space-y-5 p-6" @submit.prevent="save">
      <h2 class="text-base font-semibold text-slate-900">Personal information</h2>
      <div>
        <label class="label" for="acc-name">Full name</label>
        <input id="acc-name" v-model="name" class="input" autocomplete="name" required @input="saved = false" />
      </div>
      <div>
        <label class="label" for="acc-phone">Phone number</label>
        <input
          id="acc-phone"
          v-model="phone"
          type="tel"
          class="input"
          placeholder="e.g. 0772 123456"
          autocomplete="tel"
          @input="saved = false"
        />
        <p class="mt-1 text-xs text-slate-500">Optional. Used so {{ auth.isLandlord ? 'tenants' : 'your landlord' }} can reach you.</p>
      </div>

      <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
      <p v-if="saved" class="flex items-center gap-2 text-sm text-emerald-700">
        <CheckCircle2 class="size-4" /> Your details were saved.
      </p>

      <div class="flex justify-end gap-2 pt-1">
        <button v-if="dirty" type="button" class="btn-secondary" @click="reset">Cancel</button>
        <button :data-busy="Boolean(busy)" type="submit" class="btn-primary" :disabled="busy || !dirty">{{ busy ? 'Saving…' : 'Save changes' }}</button>
      </div>
    </form>

    <!-- Read-only -->
    <div class="card divide-y divide-slate-100">
      <div v-for="d in details" :key="d.label" class="flex items-center gap-4 px-6 py-4">
        <component :is="d.icon" class="size-5 shrink-0 text-slate-400" />
        <p class="w-32 shrink-0 text-sm text-slate-500">{{ d.label }}</p>
        <p class="min-w-0 flex-1 truncate text-sm font-medium text-slate-900">{{ d.value }}</p>
      </div>
    </div>
    <p class="px-1 text-xs text-slate-400">
      To change your email address, contact {{ auth.isLandlord ? 'Renta UG support' : 'your landlord' }}.
    </p>

    <!-- Password -->
    <section>
      <h2 class="mb-3 px-1 text-xs font-medium tracking-wide text-slate-400 uppercase">Password</h2>
      <RouterLink
        :to="`${auth.home}/settings/password`"
        class="card flex items-center gap-4 px-5 py-4 transition-colors hover:bg-slate-50"
      >
        <div class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-slate-100 text-slate-600">
          <KeyRound class="size-5" />
        </div>
        <div class="min-w-0 flex-1">
          <p class="text-sm font-medium text-slate-900">Change password</p>
          <p class="mt-0.5 text-sm text-slate-500">Keep your account secure</p>
        </div>
        <ChevronRight class="size-5 shrink-0 text-slate-400" />
      </RouterLink>
    </section>
  </SettingsSubpage>
</template>
