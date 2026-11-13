<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  LayoutDashboard, Home, CreditCard, Bell, Building2, Users, Wallet, Send, LogOut, Menu, X, Briefcase, Archive, Inbox,
} from '@lucide/vue'
import PageSkeleton from '@/components/PageSkeleton.vue'
import { useAuthStore } from '@/stores/auth'
import { useRentalStore } from '@/stores/rental'
import Logo from '@/components/Logo.vue'
import ConnectLandlord from '@/components/ConnectLandlord.vue'

const auth = useAuthStore()
const rental = useRentalStore()
const route = useRoute()
const router = useRouter()
const mobileOpen = ref(false)

watch(() => route.fullPath, () => (mobileOpen.value = false))

onMounted(() => {
  rental.load()
  rental.subscribe()
})

const myTenant = computed(() => (auth.isTenant ? rental.tenantForUser(auth.user?.id) : null))
const tenantId = computed(() => myTenant.value?.id)
// Tenant without a current rental → must connect with their landlord's code first
const unlinked = computed(() => auth.isTenant && rental.loaded && !myTenant.value?.propertyId)
const unread = computed(() =>
  tenantId.value ? rental.notificationsForTenant(tenantId.value).filter((n) => !n.read).length : 0,
)

const staffUnread = computed(() => rental.staff_notifications.filter((n) => !n.read).length)

const nav = computed(() => {
  if (auth.isSuperadmin)
    return [
      { to: '/admin2026/overview', label: 'Overview', icon: LayoutDashboard },
      { to: '/admin2026/landlords', label: 'Landlords', icon: Briefcase },
      { to: '/admin2026/tenants', label: 'All tenants', icon: Users },
      { to: '/admin2026/inbox', label: 'Inbox', icon: Inbox, badge: staffUnread.value },
    ]
  if (auth.isLandlord)
    return [
      { to: '/landlord', label: 'Overview', icon: LayoutDashboard, exact: true },
      { to: '/landlord/properties', label: 'Properties', icon: Building2 },
      { to: '/landlord/tenants', label: 'Tenants', icon: Users },
      { to: '/landlord/records', label: 'Records', icon: Archive },
      { to: '/landlord/payments', label: 'Payments', icon: Wallet },
      { to: '/landlord/notifications', label: 'Notifications', icon: Send },
      { to: '/landlord/inbox', label: 'Inbox', icon: Inbox, badge: staffUnread.value },
    ]
  return [
    { to: '/tenant', label: 'Dashboard', icon: LayoutDashboard, exact: true },
    { to: '/tenant/home', label: 'My home', icon: Home },
    { to: '/tenant/payments', label: 'Payments', icon: CreditCard },
    { to: '/tenant/notifications', label: 'Notifications', icon: Bell, badge: unread.value },
  ]
})

const roleLabel = computed(() => ({ superadmin: 'Main admin', landlord: 'Landlord' })[auth.role] ?? 'Tenant')

const isActive = (item) => (item.exact ? route.path === item.to : route.path.startsWith(item.to))

const initials = computed(() =>
  (auth.user?.name ?? '?').split(' ').map((p) => p[0]).slice(0, 2).join('').toUpperCase(),
)

async function logout() {
  const back = auth.isSuperadmin ? '/admin2026' : '/login'
  rental.clear()
  await auth.signOut()
  router.push(back)
}
</script>

<template>
  <div class="min-h-screen bg-white">
    <!-- Mobile top bar -->
    <header class="sticky top-0 z-30 flex h-14 items-center justify-between border-b border-slate-200 bg-white px-4 lg:hidden">
      <Logo />
      <button class="btn-ghost -mr-2 px-2" aria-label="Open menu" @click="mobileOpen = true">
        <Menu class="size-5" />
      </button>
    </header>

    <!-- Mobile overlay -->
    <div v-if="mobileOpen" class="fixed inset-0 z-40 bg-slate-900/20 lg:hidden" @click="mobileOpen = false" />

    <!-- Sidebar -->
    <aside
      class="fixed inset-y-0 left-0 z-50 flex w-64 flex-col border-r border-slate-200 bg-white"
      :class="mobileOpen ? 'flex' : 'hidden lg:flex'"
    >
      <div class="flex h-16 items-center justify-between px-5">
        <Logo />
        <button class="btn-ghost -mr-2 px-2 lg:hidden" aria-label="Close menu" @click="mobileOpen = false">
          <X class="size-5" />
        </button>
      </div>

      <p class="px-5 pt-2 pb-2 text-xs font-medium tracking-wide text-slate-400 uppercase">
        {{ roleLabel }}
      </p>

      <nav class="flex-1 space-y-0.5 px-3">
        <RouterLink
          v-for="item in nav"
          :key="item.to"
          :to="item.to"
          class="flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors"
          :class="isActive(item) ? 'bg-brand-50 text-brand-700' : 'text-slate-600 hover:bg-slate-50 hover:text-slate-900'"
        >
          <component :is="item.icon" class="size-4.5" />
          <span class="flex-1">{{ item.label }}</span>
          <span
            v-if="item.badge"
            class="rounded-full bg-brand-600 px-1.5 py-0.5 text-[11px] leading-none font-semibold text-white"
          >{{ item.badge }}</span>
        </RouterLink>
      </nav>

      <div class="border-t border-slate-200 p-3">
        <div class="flex items-center gap-3 rounded-lg px-2 py-2">
          <div class="flex size-9 items-center justify-center rounded-full bg-brand-50 text-sm font-semibold text-brand-700">
            {{ initials }}
          </div>
          <div class="min-w-0 flex-1">
            <p class="truncate text-sm font-medium text-slate-900">{{ auth.user?.name }}</p>
            <p class="truncate text-xs text-slate-500">{{ auth.user?.email }}</p>
          </div>
          <button class="btn-ghost px-2" title="Sign out" aria-label="Sign out" @click="logout">
            <LogOut class="size-4" />
          </button>
        </div>
      </div>
    </aside>

    <main class="lg:pl-64">
      <div class="mx-auto max-w-6xl px-4 py-6 sm:px-6 lg:px-8 lg:py-10">
        <div v-if="rental.error" class="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          Couldn't load your data: {{ rental.error }}
          <button class="ml-2 font-medium underline" @click="rental.load()">Retry</button>
        </div>
        <PageSkeleton v-else-if="!rental.loaded" />
        <ConnectLandlord v-else-if="unlinked" />
        <RouterView v-else />
      </div>
    </main>
  </div>
</template>
