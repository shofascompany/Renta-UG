<script setup>
import { computed, onMounted, ref } from 'vue'
import { UserRound, KeyRound, Bell, Info, LogOut, ChevronRight } from '@lucide/vue'
import { useAuthStore } from '@/stores/auth'
import { pushStatus } from '@/lib/push'
import { useSignOut } from '@/composables/useSignOut'
import BaseModal from '@/components/BaseModal.vue'

const auth = useAuthStore()
const signOut = useSignOut()
const base = computed(() => `${auth.home}/settings`)

const push = ref('loading')
onMounted(async () => (push.value = await pushStatus()))

const pushLabel = computed(
  () => ({ on: 'On', off: 'Off', denied: 'Blocked', 'needs-install': 'Needs Home Screen', unsupported: 'Not available' })[push.value] ?? '',
)

const groups = computed(() => [
  {
    title: 'Account',
    items: [
      { to: 'account', icon: UserRound, label: 'Account details', hint: 'Your name, phone number and email' },
      { to: 'password', icon: KeyRound, label: 'Change password', hint: 'Keep your account secure' },
    ],
  },
  {
    title: 'Preferences',
    items: [
      { to: 'notifications', icon: Bell, label: 'Notifications', hint: 'Alerts on this phone or computer', value: pushLabel.value },
    ],
  },
  {
    title: 'Support',
    items: [{ to: 'about', icon: Info, label: 'About & help', hint: 'App version, install on your phone, tips' }],
  },
])

const initials = computed(() =>
  (auth.user?.name ?? '?').split(' ').map((p) => p[0]).slice(0, 2).join('').toUpperCase(),
)
const roleLabel = computed(() => (auth.isLandlord ? 'Landlord' : 'Tenant'))

const confirmOpen = ref(false)
const signingOut = ref(false)
async function doSignOut() {
  signingOut.value = true
  try {
    await signOut()
  } finally {
    signingOut.value = false
  }
}
</script>

<template>
  <div class="mx-auto max-w-2xl">
    <h1 class="mb-8 text-2xl font-semibold tracking-tight text-slate-900">Settings</h1>

    <!-- Who is signed in -->
    <RouterLink :to="`${base}/account`" class="card mb-8 flex items-center gap-4 p-5 transition-colors hover:bg-slate-50">
      <div class="flex size-14 shrink-0 items-center justify-center rounded-full bg-brand-50 text-lg font-semibold text-brand-700">
        {{ initials }}
      </div>
      <div class="min-w-0 flex-1">
        <p class="truncate text-base font-semibold text-slate-900">{{ auth.user?.name }}</p>
        <p class="truncate text-sm text-slate-500">{{ auth.user?.email }}</p>
        <span class="mt-1.5 inline-flex rounded-full bg-brand-50 px-2 py-0.5 text-xs font-medium text-brand-700">{{ roleLabel }}</span>
      </div>
      <ChevronRight class="size-5 shrink-0 text-slate-400" />
    </RouterLink>

    <!-- Each option opens its own page -->
    <section v-for="group in groups" :key="group.title" class="mb-8">
      <h2 class="mb-3 px-1 text-xs font-medium tracking-wide text-slate-400 uppercase">{{ group.title }}</h2>
      <div class="card divide-y divide-slate-100 overflow-hidden">
        <RouterLink
          v-for="item in group.items"
          :key="item.to"
          :to="`${base}/${item.to}`"
          class="flex items-center gap-4 px-5 py-4 transition-colors hover:bg-slate-50"
        >
          <div class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-slate-100 text-slate-600">
            <component :is="item.icon" class="size-5" />
          </div>
          <div class="min-w-0 flex-1">
            <p class="text-sm font-medium text-slate-900">{{ item.label }}</p>
            <p class="mt-0.5 text-sm text-slate-500">{{ item.hint }}</p>
          </div>
          <span v-if="item.value" class="hidden shrink-0 text-sm text-slate-500 sm:block">{{ item.value }}</span>
          <ChevronRight class="size-5 shrink-0 text-slate-400" />
        </RouterLink>
      </div>
    </section>

    <!-- Sign out -->
    <button
      class="card flex w-full cursor-pointer items-center gap-4 px-5 py-4 text-left transition-colors hover:bg-red-50"
      @click="confirmOpen = true"
    >
      <div class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-red-50 text-red-600">
        <LogOut class="size-5" />
      </div>
      <div class="flex-1">
        <p class="text-sm font-medium text-red-600">Sign out</p>
        <p class="mt-0.5 text-sm text-slate-500">Leave your account on this device</p>
      </div>
    </button>

    <BaseModal v-model="confirmOpen" title="Sign out?" width="max-w-sm">
      <p class="text-sm text-slate-600">You'll need your email and password to sign in again. Notifications to this device will stop.</p>
      <div class="mt-6 flex justify-end gap-2">
        <button class="btn-secondary" @click="confirmOpen = false">Cancel</button>
        <button class="btn bg-red-600 text-white hover:bg-red-700" :disabled="signingOut" @click="doSignOut">
          {{ signingOut ? 'Signing out…' : 'Sign out' }}
        </button>
      </div>
    </BaseModal>
  </div>
</template>
