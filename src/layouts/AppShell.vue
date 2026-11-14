<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import {
  LayoutDashboard, Home, CreditCard, Bell, Building2, Users, Wallet, Send, LogOut, Menu, X, Briefcase, Archive, Inbox,
  Settings, Banknote, BarChart3, History, UserCog, DoorOpen, Activity, Megaphone, Server,
} from '@lucide/vue'
import PageSkeleton from '@/components/PageSkeleton.vue'
import { useAuthStore } from '@/stores/auth'
import { useRentalStore } from '@/stores/rental'
import { useSignOut } from '@/composables/useSignOut'
import Logo from '@/components/Logo.vue'
import ConnectLandlord from '@/components/ConnectLandlord.vue'
import MoveOutScreen from '@/components/MoveOutScreen.vue'

const auth = useAuthStore()
const rental = useRentalStore()
const route = useRoute()
const mobileOpen = ref(false)

// Settings exist for landlords and tenants
const settingsPath = computed(() => (auth.isSuperadmin ? null : `${auth.home}/settings`))
const onSettings = computed(() => Boolean(settingsPath.value) && route.path.startsWith(settingsPath.value))

watch(() => route.fullPath, () => (mobileOpen.value = false))

onMounted(async () => {
  rental.subscribe()
  await rental.load()
  // Tenant opened the app: today's rent status (at most once a day; sign-in sends its own)
  if (auth.isTenant && !rental.error) rental.checkRentStatus()
})

const myTenant = computed(() => (auth.isTenant ? rental.tenantForUser(auth.user?.id) : null))
const tenantId = computed(() => myTenant.value?.id)
// Tenant without a current rental → must connect with their landlord's code first
const unlinked = computed(() => auth.isTenant && rental.loaded && !myTenant.value?.propertyId)
const unread = computed(() =>
  tenantId.value ? rental.notificationsForTenant(tenantId.value).filter((n) => !n.read && !n.tenantHidden).length : 0,
)

// Tenant asked to leave: waiting screen while pending; a goodbye (then sign-out) once approved
const moveOut = computed(() => (auth.isTenant ? rental.myMoveOut(auth.user?.id) : null))
const ackKey = (id) => `renta:moveout-seen:${id}`
const seenAck = ref(0) // bump to re-read storage
const acked = (id) => {
  void seenAck.value
  try { return localStorage.getItem(ackKey(id)) === '1' } catch { return false }
}
const moveOutMode = computed(() => {
  const r = moveOut.value
  if (!r || !rental.loaded) return null
  if (r.status === 'pending') return 'waiting'
  if (r.status === 'approved' && unlinked.value && !acked(r.id)) return 'approved'
  return null
})
const moveOutHouse = computed(() => (moveOut.value?.propertyId && rental.propertyById(moveOut.value.propertyId) ? rental.placeName(moveOut.value.propertyId) : ''))
function moveOutDone() {
  try { localStorage.setItem(ackKey(moveOut.value.id), '1') } catch { /* private mode */ }
  seenAck.value++
}

const staffUnread = computed(() => rental.staff_notifications.filter((n) => !n.read).length)

const nav = computed(() => {
  if (auth.isSuperadmin)
    return [
      { group: 'Monitor', to: '/admin2026/overview', label: 'Overview', icon: LayoutDashboard },
      { group: 'Monitor', to: '/admin2026/activity', label: 'Activity', icon: Activity },
      { group: 'People & places', to: '/admin2026/landlords', label: 'Landlords', icon: Briefcase },
      { group: 'People & places', to: '/admin2026/tenants', label: 'Tenants', icon: Users },
      { group: 'People & places', to: '/admin2026/properties', label: 'Properties', icon: Building2 },
      { group: 'Money', to: '/admin2026/transactions', label: 'Transactions', short: 'Money', icon: History },
      { group: 'Money', to: '/admin2026/reports', label: 'Statistics', icon: BarChart3 },
      { group: 'Communicate', to: '/admin2026/broadcast', label: 'Announcements', icon: Megaphone },
      { group: 'Communicate', to: '/admin2026/inbox', label: 'Inbox', icon: Inbox, badge: staffUnread.value },
      { group: 'System', to: '/admin2026/system', label: 'Health & settings', short: 'System', icon: Server, also: ['/admin2026/archives'] },
    ]
  if (auth.isLandlord)
    return [
      { to: '/landlord', label: 'Overview', icon: LayoutDashboard, exact: true },
      { to: '/landlord/revenue', label: 'Transactions', icon: History },
      { to: '/landlord/reports', label: 'Reports', icon: BarChart3 },
      { to: '/landlord/properties', label: 'Properties', icon: Building2, also: ['/landlord/rentals'] },
      { to: '/landlord/tenants', label: 'Tenants', icon: Users },
      { to: '/landlord/managed', label: 'No-smartphone accounts', short: 'Managed', icon: UserCog },
      { to: '/landlord/payments', label: 'Payments', icon: Wallet, badge: rental.pendingCash.length },
      { to: '/landlord/move-outs', label: 'Requests to leave', icon: DoorOpen, badge: rental.pendingMoveOuts.length },
      { to: '/landlord/records', label: 'Records', icon: Archive },
      { to: '/landlord/notifications', label: 'Notices', icon: Send },
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

const isActive = (item) =>
  item.exact ? route.path === item.to : [item.to, ...(item.also ?? [])].some((p) => route.path.startsWith(p))

// Everyone: top bar + floating bottom tab bar on phones. Landlords and the main admin also get the side
// menu (always open on computers; on phones the logo opens it).
const topNav = computed(() => auth.isTenant || auth.isLandlord || auth.isSuperadmin)
const hasSide = computed(() => auth.isLandlord || auth.isSuperadmin)
const settingsTab = computed(() => ({ to: settingsPath.value, label: 'Settings', icon: Settings, active: onSettings.value }))
const withActive = (items) => items.map((item) => ({ ...item, active: isActive(item) }))

// Phones: bottom tabs. Tenant notifications / landlord inbox live behind the bell in the top bar.
const tabs = computed(() => {
  if (route.meta.focus) return [] // full-screen detail pages: just a back button
  if (auth.isSuperadmin) {
    const keep = ['/admin2026/overview', '/admin2026/landlords', '/admin2026/tenants', '/admin2026/transactions', '/admin2026/system']
    return withActive(keep.map((to) => nav.value.find((i) => i.to === to)))
  }
  if (auth.isLandlord) {
    const keep = ['/landlord', '/landlord/properties', '/landlord/tenants', '/landlord/payments']
    return [...withActive(nav.value.filter((i) => keep.includes(i.to))), settingsTab.value]
  }
  if (!auth.isTenant || unlinked.value) return []
  return [...withActive(nav.value.filter((item) => item.icon !== Bell)), settingsTab.value]
})

// Larger screens: links in the top bar
const topLinks = computed(() => {
  if (auth.isLandlord) {
    const order = ['/landlord', '/landlord/properties', '/landlord/tenants', '/landlord/payments', '/landlord/notifications', '/landlord/records']
    const short = { '/landlord/notifications': 'Notices' }
    return [
      ...withActive(order.map((to) => nav.value.find((i) => i.to === to)).map((i) => ({ ...i, label: short[i.to] ?? i.label }))),
      settingsTab.value,
    ]
  }
  return tabs.value
})

// The bell: tenant → notifications, landlord → inbox
const bell = computed(() =>
  auth.isSuperadmin
    ? { to: '/admin2026/inbox', count: staffUnread.value, label: 'Inbox' }
    : auth.isLandlord
      ? { to: '/landlord/inbox', count: staffUnread.value, label: 'Inbox' }
      : { to: '/tenant/notifications', count: unread.value, label: 'Notifications' },
)
// Quick action in the phone top bar: landlord → send a notice, main admin → announcement
const quickSend = computed(() =>
  auth.isSuperadmin ? { to: '/admin2026/broadcast', label: 'Send an announcement' } : auth.isLandlord ? { to: '/landlord/notifications', label: 'Send a notice' } : null,
)

const initials = computed(() =>
  (auth.user?.name ?? '?').split(' ').map((p) => p[0]).slice(0, 2).join('').toUpperCase(),
)

const logout = useSignOut()
</script>

<template>
  <div class="min-h-screen bg-white">
    <!-- Tenants + landlords: no sidebar. Top bar with the bell (pages are in the tabs / top links). -->
    <header
      v-if="topNav"
      class="topbar sticky top-0 z-30 border-b border-slate-200/70 bg-white/85 backdrop-blur-xl"
      :class="[hasSide && 'lg:hidden', route.meta.focus && 'max-lg:hidden']"
    >
      <div class="mx-auto flex h-16 max-w-6xl items-center justify-between gap-4 px-4 sm:px-6 lg:px-8">
        <!-- Landlord / main admin: the logo opens the side menu -->
        <button
          v-if="hasSide"
          type="button"
          class="flex items-center rounded-xl"
          aria-label="Open menu"
          :aria-expanded="mobileOpen"
          @click="mobileOpen = true"
        >
          <Logo />
        </button>
        <RouterLink v-else :to="auth.home" aria-label="Home" class="flex items-center gap-2.5">
          <Logo />
        </RouterLink>

        <nav v-if="topLinks.length" class="hidden items-center gap-0.5 lg:flex" aria-label="Main">
          <RouterLink
            v-for="item in topLinks"
            :key="item.to"
            :to="item.to"
            class="relative rounded-lg px-3 py-2 text-sm font-medium transition-colors"
            :class="item.active ? 'bg-brand-50 text-brand-700' : 'text-slate-600 hover:bg-slate-50 hover:text-slate-900'"
          >
            {{ item.label }}
            <span v-if="item.badge" class="ml-1 rounded-full bg-amber-500 px-1.5 py-0.5 text-[10px] leading-none font-bold text-white">{{ item.badge }}</span>
          </RouterLink>
        </nav>

        <div class="flex items-center gap-2">
          <!-- Landlord: "send a notice" · main admin: "announcement" -->
          <RouterLink
            v-if="quickSend"
            :to="quickSend.to"
            class="top-icon lg:hidden"
            :class="route.path.startsWith(quickSend.to) && 'top-icon-on'"
            :aria-label="quickSend.label"
          >
            <Send class="size-[1.15rem]" />
          </RouterLink>

          <RouterLink
            v-if="!unlinked"
            :to="bell.to"
            class="top-icon relative"
            :class="route.path.startsWith(bell.to) && 'top-icon-on'"
            :aria-label="bell.count ? `${bell.label}, ${bell.count} unread` : bell.label"
          >
            <Bell class="size-5" />
            <span
              v-if="bell.count"
              class="absolute -top-0.5 -right-0.5 flex min-w-5 items-center justify-center rounded-full bg-red-600 px-1 py-0.5 text-[11px] leading-none font-semibold text-white ring-2 ring-white"
            >{{ bell.count > 9 ? '9+' : bell.count }}</span>
          </RouterLink>
          <RouterLink v-else-if="settingsPath" :to="settingsPath" class="btn-ghost size-11 rounded-full p-0" aria-label="Settings">
            <Settings class="size-5" />
          </RouterLink>

        </div>
      </div>
    </header>

    <!-- Mobile overlay -->
    <Transition name="fade">
      <div v-if="mobileOpen && !auth.isTenant" class="fixed inset-0 z-40 bg-slate-900/40 backdrop-blur-[2px] lg:hidden" @click="mobileOpen = false" />
    </Transition>

    <!-- Sidebar: always on computers; on phones it slides in when the logo is tapped -->
    <aside
      v-if="!auth.isTenant"
      class="side fixed inset-y-0 left-0 z-50 flex w-[17rem] max-w-[85vw] flex-col border-r lg:w-64 lg:translate-x-0"
      :class="[mobileOpen ? 'translate-x-0 shadow-2xl' : '-translate-x-full', auth.isSuperadmin ? 'side-admin border-transparent' : 'border-slate-200 bg-white']"
    >
      <div class="side-head flex h-16 shrink-0 items-center justify-between px-5">
        <RouterLink :to="auth.home" aria-label="Overview" class="rounded-lg"><Logo /></RouterLink>
        <button class="btn-ghost -mr-2 px-2 lg:hidden" aria-label="Close menu" @click="mobileOpen = false">
          <X class="size-5" />
        </button>
      </div>

      <p class="px-5 pt-2 pb-2 text-xs font-medium tracking-wide text-slate-400 uppercase">
        {{ roleLabel }}
      </p>

      <nav class="flex-1 space-y-0.5 overflow-y-auto px-3 pb-2">
        <template v-for="(item, i) in nav" :key="item.to">
          <p v-if="item.group && item.group !== nav[i - 1]?.group" class="nav-group px-3 pt-4 pb-1.5 text-[10px] font-bold tracking-[0.16em] uppercase">{{ item.group }}</p>
          <RouterLink
            :to="item.to"
            class="nav-link flex items-center gap-3 rounded-xl px-3 py-2.5 text-[15px] font-medium transition-colors lg:rounded-lg lg:py-2 lg:text-sm"
            :class="isActive(item) ? 'nav-on bg-brand-50 text-brand-700' : 'text-slate-600 hover:bg-slate-50 hover:text-slate-900'"
          >
            <component :is="item.icon" class="size-4.5" />
            <span class="flex-1">{{ item.label }}</span>
            <span
              v-if="item.badge"
              class="nav-badge rounded-full bg-brand-600 px-1.5 py-0.5 text-[11px] leading-none font-semibold text-white"
            >{{ item.badge }}</span>
          </RouterLink>
        </template>
      </nav>

      <!-- Settings -->
      <div v-if="settingsPath" class="px-3 pb-3">
        <RouterLink
          :to="settingsPath"
          class="flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors"
          :class="onSettings ? 'bg-brand-50 text-brand-700' : 'text-slate-600 hover:bg-slate-50 hover:text-slate-900'"
        >
          <Settings class="size-4.5" />
          <span class="flex-1">Settings</span>
        </RouterLink>
      </div>

      <div class="border-t border-slate-200 p-3">
        <div class="flex items-center gap-3 rounded-lg px-2 py-2">
          <component
            :is="settingsPath ? 'RouterLink' : 'div'"
            :to="settingsPath ? `${settingsPath}/account` : undefined"
            class="flex min-w-0 flex-1 items-center gap-3 rounded-lg"
            :title="settingsPath ? 'Account details' : undefined"
          >
            <div class="flex size-9 shrink-0 items-center justify-center rounded-full bg-brand-50 text-sm font-semibold text-brand-700">
              {{ initials }}
            </div>
            <div class="min-w-0 flex-1">
              <p class="truncate text-sm font-medium text-slate-900">{{ auth.user?.name }}</p>
              <p class="truncate text-xs text-slate-500">{{ auth.user?.email }}</p>
            </div>
          </component>
          <!-- Landlords sign out from Settings; the main admin has no Settings page, so keeps this -->
          <button v-if="auth.isSuperadmin" class="btn-ghost px-2" title="Sign out" aria-label="Sign out" @click="logout">
            <LogOut class="size-4" />
          </button>
        </div>
      </div>
    </aside>

    <main :class="[!auth.isTenant && 'lg:pl-64', 'console-bg min-h-screen']">
      <div
        class="mx-auto max-w-6xl px-4 py-6 sm:px-6 lg:px-8 lg:py-10"
        :class="tabs.length && 'pb-32 lg:pb-10'"
      >
        <div v-if="rental.error" class="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          Couldn't load your data: {{ rental.error }}
          <button class="ml-2 font-medium underline" @click="rental.load()">Retry</button>
        </div>
        <PageSkeleton v-else-if="!rental.loaded" />
        <ConnectLandlord v-else-if="unlinked && !onSettings" />
        <RouterView v-else />
      </div>
    </main>

    <MoveOutScreen v-if="moveOutMode" :key="moveOutMode" :request="moveOut" :mode="moveOutMode" :house="moveOutHouse" @done="moveOutDone" />

    <!-- Phones: floating tab bar at the bottom, within thumb reach -->
    <nav
      v-if="tabs.length"
      class="pointer-events-none fixed inset-x-0 bottom-0 z-30 px-3 pb-[max(0.625rem,env(safe-area-inset-bottom))] lg:hidden"
      aria-label="Main"
    >
      <div
        class="tabbar pointer-events-auto mx-auto grid max-w-md gap-1 rounded-[1.6rem] border border-slate-200/80 bg-white/90 p-1.5 backdrop-blur-xl"
        :class="tabs.length === 5 ? 'grid-cols-5' : 'grid-cols-4'"
      >
        <RouterLink
          v-for="item in tabs"
          :key="item.to"
          :to="item.to"
          class="relative flex h-[3.6rem] flex-col items-center justify-center gap-1 rounded-[1.15rem] text-[11px] font-semibold transition-all duration-200 active:scale-95"
          :class="item.active ? 'tab-on text-white' : 'text-slate-500 active:bg-slate-100'"
          :aria-current="item.active ? 'page' : undefined"
        >
          <span class="relative">
            <component :is="item.icon" class="size-[1.35rem]" :stroke-width="item.active ? 2.25 : 1.8" />
            <span
              v-if="item.badge"
              class="absolute -top-1.5 -right-2.5 min-w-4.5 rounded-full bg-amber-500 px-1 py-0.5 text-center text-[10px] leading-none font-semibold text-white ring-2 ring-white"
            >{{ item.badge }}</span>
          </span>
          <span class="max-w-full truncate px-0.5">{{ item.short ?? item.label }}</span>
        </RouterLink>
      </div>
    </nav>
  </div>
</template>

<style scoped>
/* Side menu slides in on phones; fixed open on computers */
.side {
  transition: transform 0.28s cubic-bezier(0.22, 1, 0.36, 1), box-shadow 0.28s ease;
}
@media (min-width: 1024px) {
  .side { transform: none; box-shadow: none; }
}
/* Main admin: deep gradient sidebar */
.side-admin {
  --color-white: #fff;
  background: linear-gradient(180deg, #0b1324 0%, #0a2a2c 55%, #0a3b38 100%);
  color: #fff;
}
.side-admin .side-head { background: linear-gradient(120deg, rgb(45 212 191 / 0.14), transparent 75%); }
.side-admin :deep(.text-slate-900), .side-admin .text-slate-900 { color: #fff; }
.side-admin .text-slate-400, .side-admin .text-slate-500, .side-admin .nav-group { color: rgb(255 255 255 / 0.45); }
.side-admin .nav-link { color: rgb(255 255 255 / 0.72); }
.side-admin .nav-link:hover { color: #fff; background: rgb(255 255 255 / 0.07); }
.side-admin .nav-on {
  color: #fff !important;
  background: linear-gradient(135deg, rgb(20 184 166 / 0.45), rgb(15 118 110 / 0.35)) !important;
  box-shadow: inset 0 0 0 1px rgb(94 234 212 / 0.25);
}
.side-admin .nav-badge { background: #f59e0b; }
.side-admin .border-t { border-color: rgb(255 255 255 / 0.1); }
.side-admin .btn-ghost { color: rgb(255 255 255 / 0.75); }
.side-admin .btn-ghost:hover { background: rgb(255 255 255 / 0.08); color: #fff; }
.side-admin .bg-brand-50 { background: rgb(255 255 255 / 0.12); }
.side-admin .text-brand-700 { color: #5eead4; }
/* soft brand tint behind the logo */
.side-head {
  background: linear-gradient(120deg, var(--color-brand-50), transparent 75%);
}
/* Top bar buttons */
.top-icon {
  display: flex;
  width: 2.75rem;
  height: 2.75rem;
  align-items: center;
  justify-content: center;
  border-radius: 1rem;
  color: var(--color-slate-600);
  background: var(--color-slate-100);
  transition: background-color 0.15s ease, color 0.15s ease, transform 0.15s ease;
}
.top-icon:hover { color: var(--color-slate-900); background: var(--color-slate-200); }
.top-icon:active { transform: scale(0.94); }
.top-icon-on { color: var(--color-brand-700); background: var(--color-brand-50); }
.top-avatar {
  --color-white: #fff;
  display: flex;
  width: 2.75rem;
  height: 2.75rem;
  align-items: center;
  justify-content: center;
  border-radius: 1rem;
  font-size: 0.8125rem;
  font-weight: 700;
  color: #fff;
  background: linear-gradient(140deg, #2dd4bf, #0f766e 55%, #0a3b38);
  box-shadow: 0 6px 14px -8px rgb(15 118 110 / 0.8);
}
.top-avatar:active { transform: scale(0.94); }
/* Landlord and tenant pages: a soft teal wash at the top, then light grey */
.console-bg {
  background:
    radial-gradient(120% 340px at 100% 0%, rgb(45 212 191 / 0.1), transparent 70%),
    linear-gradient(180deg, rgb(239 250 248 / 0.55), transparent 420px),
    var(--color-slate-50);
}
@media (min-width: 1024px) {
  .console-bg { background: rgb(248 250 252 / 0.6); }
}
:global(html.dark) .console-bg {
  background: radial-gradient(120% 340px at 100% 0%, rgb(45 212 191 / 0.08), transparent 70%), var(--color-white);
}

/* Floating tab bar */
.tabbar {
  box-shadow: 0 12px 32px -12px rgb(15 23 42 / 0.28), 0 2px 6px rgb(15 23 42 / 0.06);
}
.tab-on {
  --color-white: #fff;
  background: linear-gradient(135deg, #14918a, #0f766e 60%, #0a3b38);
  box-shadow: 0 8px 18px -8px rgb(15 118 110 / 0.7);
}
.fade-enter-active, .fade-leave-active { transition: opacity 0.2s ease; }
.fade-enter-from, .fade-leave-to { opacity: 0; }
@media (prefers-reduced-motion: reduce) {
  .side { transition: none; }
}
</style>
