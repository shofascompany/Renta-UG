<script setup>
import { computed, onMounted, ref } from 'vue'
import { Bell, Info, LogOut, FileText } from '@lucide/vue'
import { useAuthStore } from '@/stores/auth'
import { pushStatus } from '@/lib/push'
import { useSignOut } from '@/composables/useSignOut'
import BaseModal from '@/components/BaseModal.vue'
import AdminHeader from '@/components/admin/AdminHeader.vue'
import ListRow from '@/components/admin/ListRow.vue'

// Settings for landlords and tenants, built from the same pieces as the landlord pages:
// gradient header, white sheets, coloured icon tiles and tappable rows.
const auth = useAuthStore()
const signOut = useSignOut()
const base = computed(() => `${auth.home}/settings`)

const push = ref('loading')
onMounted(async () => (push.value = await pushStatus()))

const pushLabel = computed(
  () => ({ on: 'On', off: 'Off', denied: 'Blocked', 'needs-install': 'Needs Home Screen', unsupported: 'Not available' })[push.value] ?? '',
)

// The original options; only the look is new. Account details + Change password open from the profile card.
const groups = computed(() => [
  {
    title: 'Preferences',
    items: [{ to: 'notifications', icon: Bell, tile: 'tile-amber', label: 'Notifications', hint: 'Alerts on this phone or computer', value: pushLabel.value }],
  },
  {
    title: 'Support',
    items: [{ to: 'about', icon: Info, tile: 'tile-sky', label: 'About & help', hint: 'App version, install on your phone, tips' }],
  },
  {
    title: 'Legal',
    items: [{ to: 'terms', icon: FileText, tile: 'tile-slate', label: 'Terms & conditions', hint: 'How Renta UG works, payments and your information' }],
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
    <AdminHeader eyebrow="Your account" title="Settings" subtitle="Your details, alerts and help, all in one place." />

    <!-- Who is signed in -->
    <RouterLink :to="`${base}/account`" class="sheet rise group mb-6 flex items-center gap-4 p-5 transition-colors hover:bg-slate-50" style="--d: 0ms">
      <span class="avatar flex size-14 shrink-0 items-center justify-center rounded-2xl text-lg font-bold text-white">{{ initials }}</span>
      <div class="min-w-0 flex-1">
        <p class="truncate text-base font-semibold text-slate-900">{{ auth.user?.name }}</p>
        <p class="truncate text-sm text-slate-500">{{ auth.user?.email }}</p>
        <span class="mt-1.5 inline-flex rounded-full bg-brand-50 px-2 py-0.5 text-xs font-semibold text-brand-700">{{ roleLabel }}</span>
      </div>
    </RouterLink>

    <!-- Each option opens its own page -->
    <section v-for="(group, gi) in groups" :key="group.title" class="rise mb-6" :style="{ '--d': `${60 + gi * 50}ms` }">
      <h2 class="section-title">{{ group.title }}</h2>
      <div class="sheet">
        <ul class="divide-y divide-slate-100">
          <ListRow
            v-for="item in group.items"
            :key="item.to"
            :to="`${base}/${item.to}`"
            :title="item.label"
            :subtitle="item.hint"
            :value="item.value"
            value-class="text-slate-500 font-medium"
          >
            <template #icon>
              <span class="icon-tile" :class="item.tile"><component :is="item.icon" class="size-[1.3rem]" /></span>
            </template>
          </ListRow>
        </ul>
      </div>
    </section>

    <!-- Sign out -->
    <section class="rise" style="--d: 220ms">
      <div class="sheet">
        <ul>
          <ListRow title="Sign out" subtitle="Leave your account on this device" :chevron="false" @click="confirmOpen = true">
            <template #title><span class="text-red-600">Sign out</span></template>
            <template #icon><span class="icon-disc disc-red size-11 rounded-2xl"><LogOut class="size-5" /></span></template>
          </ListRow>
        </ul>
      </div>
    </section>

    <BaseModal v-model="confirmOpen" title="Sign out?" width="max-w-sm">
      <p class="text-sm text-slate-600">You'll need your email and password to sign in again. Notifications to this device will stop.</p>
      <div class="mt-6 flex justify-end gap-2">
        <button class="btn-secondary" @click="confirmOpen = false">Cancel</button>
        <button :data-busy="Boolean(signingOut)" class="btn bg-red-600 text-white hover:bg-red-700" :disabled="signingOut" @click="doSignOut">
          {{ signingOut ? 'Signing out…' : 'Sign out' }}
        </button>
      </div>
    </BaseModal>
  </div>
</template>

<style scoped>
.avatar {
  --color-white: #fff;
  background: linear-gradient(140deg, #2dd4bf, #0f766e 55%, #0a3b38);
  box-shadow: 0 8px 18px -10px rgb(15 118 110 / 0.8);
}
.rise {
  animation: rise 0.5s cubic-bezier(0.22, 1, 0.36, 1) backwards;
  animation-delay: var(--d, 0ms);
}
@keyframes rise {
  from { opacity: 0; transform: translateY(10px); }
}
@media (prefers-reduced-motion: reduce) {
  .rise { animation: none; }
}
</style>
