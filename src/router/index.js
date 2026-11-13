import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import AppShell from '@/layouts/AppShell.vue'

const routes = [
  { path: '/', redirect: () => useAuthStore().home },

  // Landlords and tenants sign in here; the app sends each to their own area.
  { path: '/login', name: 'login', component: () => import('@/views/LoginView.vue'), meta: { guest: true } },
  { path: '/signup', name: 'signup', component: () => import('@/views/SignupView.vue'), meta: { guest: true } },

  // Landlord's first sign-in: choose their own password (shown only until they do).
  { path: '/set-password', name: 'set-password', component: () => import('@/views/SetPasswordView.vue'), meta: { role: 'landlord' } },

  // Main admin (superadmin) only.
  { path: '/admin2026', name: 'admin-login', component: () => import('@/views/AdminLoginView.vue'), meta: { guest: true } },

  {
    path: '/tenant',
    component: AppShell,
    meta: { role: 'tenant' },
    children: [
      { path: '', name: 'tenant-dashboard', component: () => import('@/views/tenant/DashboardView.vue') },
      { path: 'home', name: 'tenant-home', component: () => import('@/views/tenant/MyHomeView.vue') },
      { path: 'payments', name: 'tenant-payments', component: () => import('@/views/tenant/PaymentsView.vue') },
      { path: 'notifications', name: 'tenant-notifications', component: () => import('@/views/tenant/NotificationsView.vue') },
    ],
  },

  {
    path: '/landlord',
    component: AppShell,
    meta: { role: 'landlord' },
    children: [
      { path: '', name: 'landlord-dashboard', component: () => import('@/views/landlord/DashboardView.vue') },
      { path: 'properties', name: 'landlord-properties', component: () => import('@/views/landlord/PropertiesView.vue') },
      { path: 'properties/:id', name: 'landlord-property', component: () => import('@/views/landlord/PropertyDetailView.vue'), props: true },
      { path: 'tenants', name: 'landlord-tenants', component: () => import('@/views/landlord/TenantsView.vue') },
      { path: 'records', name: 'landlord-records', component: () => import('@/views/landlord/RecordsView.vue') },
      { path: 'payments', name: 'landlord-payments', component: () => import('@/views/landlord/PaymentsView.vue') },
      { path: 'notifications', name: 'landlord-notifications', component: () => import('@/views/landlord/NotificationsView.vue') },
      { path: 'inbox', name: 'landlord-inbox', component: () => import('@/views/InboxView.vue') },
      { path: 'messages', redirect: '/landlord/notifications' },
    ],
  },

  {
    // Children use absolute paths so /admin2026 itself stays the login page.
    path: '/_admin',
    component: AppShell,
    meta: { role: 'superadmin' },
    children: [
      { path: '/admin2026/overview', name: 'super-overview', component: () => import('@/views/super/OverviewView.vue') },
      { path: '/admin2026/landlords', name: 'super-landlords', component: () => import('@/views/super/LandlordsView.vue') },
      { path: '/admin2026/landlords/:id', name: 'super-landlord', component: () => import('@/views/super/LandlordDetailView.vue'), props: true },
      { path: '/admin2026/tenants', name: 'super-tenants', component: () => import('@/views/super/TenantsView.vue') },
      { path: '/admin2026/inbox', name: 'super-inbox', component: () => import('@/views/InboxView.vue') },
    ],
  },

  { path: '/:pathMatch(.*)*', redirect: '/' },
]

const router = createRouter({
  history: createWebHistory(),
  routes,
  scrollBehavior: () => ({ top: 0 }),
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()
  await auth.init()
  if (to.meta.guest) return auth.isAuthenticated ? auth.home : true
  if (!auth.isAuthenticated) {
    const area = to.matched.find((r) => r.meta.role)?.meta.role
    return area === 'superadmin' ? { name: 'admin-login' } : { name: 'login', query: { redirect: to.fullPath } }
  }
  const role = to.matched.find((r) => r.meta.role)?.meta.role
  if (role && role !== auth.role) return auth.home

  // Landlord on a temporary password → must set their own before anything else
  if (auth.needsPassword && to.name !== 'set-password') return { name: 'set-password' }
  if (!auth.needsPassword && to.name === 'set-password') return auth.home
  return true
})

export default router
