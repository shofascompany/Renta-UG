<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  LayoutDashboard, Home, CreditCard, Bell, Building2, Users, Wallet, Send, LogOut, X,Briefcase, Archive, Inbox,
  Settings, BarChart3, History, UserCog, DoorOpen, Activity, Megaphone, Server, Download, Crown, ArrowRight, Lock, LifeBuoy,
} from '@lucide/vue'
import PageSkeleton from '@/components/PageSkeleton.vue'
import { useAuthStore } from '@/stores/auth'
import { useRentalStore } from '@/stores/rental'
import { useBillingStore } from '@/stores/billing'
import { formatDate } from '@/utils/format'
import { useSignOut } from '@/composables/useSignOut'
import Logo from '@/components/Logo.vue'
import ConnectLandlord from '@/components/ConnectLandlord.vue'
import MoveOutScreen from '@/components/MoveOutScreen.vue'
import NotificationToast from '@/components/NotificationToast.vue'
import EmptyState from '@/components/EmptyState.vue'

const auth = useAuthStore()
const rental = useRentalStore()
const billing = useBillingStore()
const route = useRoute()
const router = useRouter()
const mobileOpen = ref(false)

// Landlord subscription. No free trial: until a payment is confirmed by the main admin (or after it
// ends) the landlord can only open Subscription, Inbox and Settings.
const sub = computed(() => (auth.isLandlord && billing.loaded && !billing.unavailable ? billing.mine : null))
const locked = computed(() => Boolean(sub.value && !sub.value.active))
const OPEN_WHEN_LOCKED = ['/landlord/subscription', '/landlord/inbox', '/landlord/settings']
const allowedWhenLocked = (path) => OPEN_WHEN_LOCKED.some((p) => path.startsWith(p))
watch(
  () => locked.value && !allowedWhenLocked(route.path),
  (out) => out && router.replace('/landlord/subscription'),
  { immediate: true },
)
// Landlords wait for their subscription status before any page shows, so nothing flashes
const waitingForBilling = computed(() => auth.isLandlord && !billing.loaded)
// Setting up (no active subscription yet): business size → package → line → send → confirm → waiting,
// full screen, with no menus around it. Read from the profile, so it shows at once with no flash.
const setupMode = computed(
  () => auth.isLandlord && !billing.unavailable && !billing.mine.active && route.path.startsWith('/landlord/subscription'),
)
const subBanner = computed(() => {
  const s = sub.value
  if (!s || route.path.startsWith('/landlord/subscription')) return null
  if (s.state === 'none') return { tone: 'bad', text: 'Pay your subscription to start using Renta UG. Your account opens as soon as Renta UG confirms the payment.', cta: 'Pay now' }
  if (s.state === 'expired') return { tone: 'bad', text: 'Your subscription has ended. Renew it to open your account again.', cta: 'Renew now' }
  if (s.state === 'ending') return { tone: 'warn', text: `Your subscription ends ${s.daysLeft === 0 ? 'today' : s.daysLeft === 1 ? 'tomorrow' : `in ${s.daysLeft} days`} (${formatDate(s.until)}).`, cta: 'Renew' }
  return null
})

// Settings exist for landlords and tenants
const settingsPath = computed(() => (auth.isSuperadmin ? null : `${auth.home}/settings`))
const onSettings = computed(() => Boolean(settingsPath.value) && route.path.startsWith(settingsPath.value))

watch(() => route.fullPath, () => (mobileOpen.value = false))

// Pages open instantly: once the dashboard is up, quietly download the code of this account's other
// pages while the phone is idle (a few at a time, so it never competes with what's on screen).
function prefetchPages() {
  const base = auth.home
  const loaders = router
    .getRoutes()
    .filter((r) => r.path.startsWith(base) && !r.path.includes(':') && typeof r.components?.default === 'function')
    .map((r) => r.components.default)
  const idle = window.requestIdleCallback ?? ((fn) => setTimeout(fn, 400))
  const next = () => {
    const batch = loaders.splice(0, 3)
    if (!batch.length) return
    Promise.allSettled(batch.map((load) => load())).then(() => idle(next))
  }
  idle(next)
}

// A thin bar at the top while a page is opening (only if it takes more than a moment), so a tap
// always shows that something is happening, even on a slow connection.
const navigating = ref(false)
let navTimer = null
const stopHooks = [
  router.beforeEach(() => {
    clearTimeout(navTimer)
    navTimer = setTimeout(() => (navigating.value = true), 120)
  }),
  router.afterEach(() => {
    clearTimeout(navTimer)
    navigating.value = false
  }),
  router.onError(() => {
    clearTimeout(navTimer)
    navigating.value = false
  }),
]
onBeforeUnmount(() => stopHooks.forEach((stop) => stop()))

onMounted(async () => {
  rental.subscribe()
  setTimeout(prefetchPages, 1500)
  if (auth.isLandlord || auth.isSuperadmin) {
    billing.subscribe()
    billing.load().catch(() => {})
  }
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

// Stable names for menu items (nav-overview, nav-properties, nav-settings…), handy for tests
const navTag = (to) =>
  to === auth.home ? 'nav-overview' : to === settingsPath.value ? 'nav-settings' : `nav-${to.split('/').pop()}`

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
      { group: 'Money', to: '/admin2026/subscriptions', label: 'Subscriptions', icon: Crown, badge: billing.pending.length },
      { group: 'Money', to: '/admin2026/reports', label: 'Statistics', icon: BarChart3 },
      { group: 'Communicate', to: '/admin2026/broadcast', label: 'Announcements', icon: Megaphone },
      { group: 'Communicate', to: '/admin2026/inbox', label: 'Inbox', icon: Inbox, badge: staffUnread.value },
      { group: 'System', to: '/admin2026/downloads', label: 'Downloads', icon: Download },
      { group: 'System', to: '/admin2026/system', label: 'Health & settings', short: 'System', icon: Server, also: ['/admin2026/archives'] },
    ]
  if (auth.isLandlord && locked.value)
    return [
      { to: '/landlord/subscription', label: 'Subscription', icon: Crown, badge: '!' },
      { to: '/landlord/inbox', label: 'Inbox', icon: Inbox, badge: staffUnread.value },
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
      { to: '/landlord/subscription', label: 'Subscription', icon: Crown, badge: sub.value && !sub.value.active ? '!' : 0 },
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
  if (route.meta.focus || setupMode.value) return [] // full-screen pages: no tabs
  if (auth.isSuperadmin) {
    const keep = ['/admin2026/overview', '/admin2026/landlords', '/admin2026/tenants', '/admin2026/transactions', '/admin2026/system']
    return withActive(keep.map((to) => nav.value.find((i) => i.to === to)))
  }
  if (auth.isLandlord) {
    const keep = locked.value ? ['/landlord/subscription'] : ['/landlord', '/landlord/properties', '/landlord/tenants', '/landlord/payments']
    return [...withActive(nav.value.filter((i) => keep.includes(i.to))), settingsTab.value]
  }
  if (!auth.isTenant || unlinked.value) return []
  return [...withActive(nav.value.filter((item) => item.icon !== Bell)), settingsTab.value]
})

// Larger screens: links in the top bar
const topLinks = computed(() => {
  if (auth.isLandlord) {
    const order = locked.value
      ? ['/landlord/subscription']
      : ['/landlord', '/landlord/properties', '/landlord/tenants', '/landlord/payments', '/landlord/notifications', '/landlord/records']
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
  auth.isSuperadmin ? { to: '/admin2026/broadcast', label: 'Send an announcement' } : auth.isLandlord && !locked.value ? { to: '/landlord/notifications', label: 'Send a notice' } : null,
)

const initials = computed(() =>
  (auth.user?.name ?? '?').split(' ').map((p) => p[0]).slice(0, 2).join('').toUpperCase(),
)

const logout = useSignOut()
</script>

<template>
  <div class="app-root min-h-screen bg-white">
    <!-- Tenants + landlords: no sidebar. Top bar with the bell (pages are in the tabs / top links). -->
    <header
      v-if="topNav && !setupMode"
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
          data-tour="menu"
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
            :data-tour="navTag(item.to)"
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
            data-tour="quick-send"
            class="top-icon lg:hidden"
            :class="route.path.startsWith(quickSend.to) && 'top-icon-on'"
            :aria-label="quickSend.label"
          >
            <Send class="size-[1.15rem]" />
          </RouterLink>

          <RouterLink
            v-if="!unlinked"
            :to="bell.to"
            data-tour="bell"
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
      <div v-if="mobileOpen && !auth.isTenant && !setupMode" class="fixed inset-0 z-40 bg-slate-900/40 backdrop-blur-[2px] lg:hidden" @click="mobileOpen = false" />
    </Transition>

    <!-- Sidebar: always on computers; on phones it slides in when the logo is tapped -->
    <aside
      v-if="!auth.isTenant && !setupMode"
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
            :data-tour="navTag(item.to)"
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
          data-tour="nav-settings"
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

    <!-- Setting up: a slim bar instead of the menus (help and sign out stay within reach) -->
    <header v-if="setupMode" class="setup-bar sticky top-0 z-30">
      <div class="mx-auto flex h-16 max-w-3xl items-center justify-between gap-3 px-4 sm:px-6">
        <Logo />
        <div class="flex items-center gap-1">
          <RouterLink to="/landlord/settings/help" class="setup-link"><LifeBuoy class="size-4" /> Help</RouterLink>
          <RouterLink to="/landlord/inbox" class="setup-link relative" aria-label="Inbox">
            <Inbox class="size-4" /><span class="max-sm:hidden">Inbox</span>
            <span v-if="staffUnread" class="absolute -top-0.5 right-0 size-2 rounded-full bg-red-600" />
          </RouterLink>
          <button type="button" class="setup-link" @click="logout"><LogOut class="size-4" /><span class="max-sm:hidden">Sign out</span></button>
        </div>
      </div>
    </header>

    <main :class="[!auth.isTenant && !setupMode && 'lg:pl-64', setupMode ? 'setup-bg' : 'console-bg', 'min-h-screen']">
      <div
        class="mx-auto px-4 py-6 sm:px-6 lg:px-8 lg:py-10"
        :class="[tabs.length && 'pb-32 lg:pb-10', setupMode ? 'max-w-3xl pb-16' : 'max-w-6xl']"
      >
        <div v-if="rental.error" class="sheet" role="alert">
          <EmptyState kind="missing" title="Your data couldn't be loaded" :text="rental.error">
            <button type="button" class="btn-primary mt-5 h-11 rounded-2xl px-6" @click="rental.load()">Try again</button>
          </EmptyState>
        </div>
        <PageSkeleton v-else-if="!rental.loaded || waitingForBilling || (locked && !allowedWhenLocked(route.path))" />
        <ConnectLandlord v-else-if="unlinked && !onSettings" />
        <template v-else>
          <!-- Landlord subscription ending / ended -->
          <RouterLink
            v-if="subBanner"
            to="/landlord/subscription"
            class="sub-banner mb-5 flex items-center gap-3 rounded-2xl px-4 py-3 text-sm"
            :class="subBanner.tone === 'bad' ? 'sub-bad' : 'sub-warn'"
          >
            <span class="sub-ico flex size-9 shrink-0 items-center justify-center rounded-xl">
              <component :is="subBanner.tone === 'bad' ? Lock : Crown" class="size-4.5" />
            </span>
            <span class="min-w-0 flex-1 leading-snug">{{ subBanner.text }}</span>
            <span class="sub-cta hidden shrink-0 items-center gap-1 rounded-xl px-3 py-2 text-xs font-semibold sm:inline-flex">{{ subBanner.cta }} <ArrowRight class="size-3.5" /></span>
            <ArrowRight class="size-4 shrink-0 sm:hidden" />
          </RouterLink>
          <RouterView />
        </template>
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
        :class="tabs.length === 5 ? 'grid-cols-5' : tabs.length === 2 ? 'grid-cols-2' : 'grid-cols-4'"
      >
        <RouterLink
          v-for="item in tabs"
          :key="item.to"
          :to="item.to"
          :data-tour="navTag(item.to)"
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
    <Transition name="navbar">
      <div v-if="navigating" class="nav-progress" role="progressbar" aria-label="Opening page" />
    </Transition>
    <NotificationToast />
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
.side-admin .nav-link:hover { color: #fff; background: rgb(var(--glass) / 0.07); }
.side-admin .nav-on {
  color: #fff !important;
  background: linear-gradient(135deg, rgb(20 184 166 / 0.45), rgb(15 118 110 / 0.35)) !important;
  box-shadow: inset 0 0 0 1px rgb(94 234 212 / 0.25);
}
.side-admin .nav-badge { background: #f59e0b; }
.side-admin .border-t { border-color: rgb(255 255 255 / 0.1); }
.side-admin .btn-ghost { color: rgb(255 255 255 / 0.75); }
.side-admin .btn-ghost:hover { background: rgb(var(--glass) / 0.08); color: #fff; }
.side-admin .bg-brand-50 { background: rgb(var(--glass) / 0.12); }
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
/* Setting up (full screen): a calm page with a soft teal light at the top */
.setup-bg {
  background:
    radial-gradient(90% 420px at 50% -60px, rgb(45 212 191 / 0.16), transparent 70%),
    radial-gradient(60% 300px at 100% 100%, rgb(250 204 21 / 0.07), transparent 70%),
    var(--color-slate-50);
}
.setup-bar { background: rgb(255 255 255 / 0.8); backdrop-filter: blur(16px); box-shadow: inset 0 -1px 0 var(--color-slate-200); }
.setup-link {
  display: inline-flex; height: 2.5rem; align-items: center; gap: 0.4rem; border-radius: 0.8rem; padding: 0 0.75rem;
  font-size: 0.85rem; font-weight: 600; color: var(--color-slate-600); transition: background-color 0.15s ease, color 0.15s ease;
}
.setup-link:hover { color: var(--color-slate-900); background: var(--color-slate-100); }
html.dark .setup-bg { background: transparent; }
html.dark .setup-bar { background: rgb(0 0 0 / 0.85); box-shadow: inset 0 -1px 0 #1f1f1f; }
/* Dark mode: let the page's black background (with its soft top light) show through */
html.dark .console-bg,
html.dark .app-root { background: transparent; }
/* Side menu (landlords): a dark panel with a hairline edge */
html.dark .side:not(.side-admin) { background: #0b0b0b; border-color: rgb(var(--glass) / 0.08); }

/* Subscription banner */
.sub-banner { transition: transform 0.15s ease, box-shadow 0.15s ease; }
.sub-banner:hover { transform: translateY(-1px); }
.sub-warn { color: var(--color-amber-800); background: var(--color-amber-50); box-shadow: inset 0 0 0 1px var(--color-amber-200); }
.sub-warn .sub-ico { color: var(--color-amber-700); background: var(--color-amber-100); }
.sub-warn .sub-cta { color: #fff; background: #d97706; }
.sub-bad { color: var(--color-red-700); background: var(--color-red-50); box-shadow: inset 0 0 0 1px var(--color-red-200); }
.sub-bad .sub-ico { color: #fff; background: #dc2626; }
.sub-bad .sub-cta { color: #fff; background: #dc2626; }

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
/* Page-opening bar: slides across while the next page loads */
.nav-progress {
  position: fixed; inset: 0 0 auto; z-index: 90; height: 3px; overflow: hidden; pointer-events: none;
  background: rgb(20 184 166 / 0.18);
}
.nav-progress::after {
  content: ''; position: absolute; inset: 0; width: 40%;
  background: linear-gradient(90deg, transparent, #14b8a6, #0f766e);
  animation: nav-slide 0.9s ease-in-out infinite;
}
@keyframes nav-slide { from { transform: translateX(-100%); } to { transform: translateX(260%); } }
.navbar-enter-active, .navbar-leave-active { transition: opacity 0.2s ease; }
.navbar-enter-from, .navbar-leave-to { opacity: 0; }
.fade-enter-from, .fade-leave-to { opacity: 0; }
@media (prefers-reduced-motion: reduce) {
  .side { transition: none; }
}
</style>
