<script setup>
import { computed, onMounted, ref } from 'vue'
import {
  Briefcase, Building2, Users, Wallet, TriangleAlert, Banknote, DoorOpen, Inbox, Megaphone, UserPlus, ArrowDownLeft,
  ShieldCheck, Smartphone, Activity, ChevronRight, CircleCheck, BarChart3,
} from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { usePlatformStats } from '@/composables/usePlatformStats'
import { compactUGX } from '@/composables/useRentAnalytics'
import { formatUGX, formatDate } from '@/utils/format'
import { api } from '@/lib/api'
import SuperHero from '@/components/super/SuperHero.vue'
import StatTile from '@/components/super/StatTile.vue'
import Panel from '@/components/admin/Panel.vue'
import ListRow from '@/components/admin/ListRow.vue'
import ColumnChart from '@/components/charts/ColumnChart.vue'
import RankBars from '@/components/charts/RankBars.vue'

// Main admin home: the whole platform at a glance, what needs attention, and shortcuts to act.
const rental = useRentalStore()
const p = usePlatformStats()

const activeLandlords = computed(() => rental.landlords.filter((l) => l.active).length)
const currentTenants = computed(() => rental.tenants.filter((t) => t.propertyId))
const connected = computed(() => currentTenants.value.filter((t) => t.userId).length)
const unread = computed(() => rental.staff_notifications.filter((n) => !n.read).length)

const attention = computed(() =>
  [
    { to: '/admin2026/tenants?show=overdue', icon: TriangleAlert, tone: 'disc-red', n: p.overdueTenants.value, title: 'Tenants overdue', sub: `${formatUGX(p.outstanding.value)} unpaid in total` },
    { to: '/admin2026/landlords?show=suspended', icon: Briefcase, tone: 'disc-slate', n: rental.landlords.length - activeLandlords.value, title: 'Suspended landlords', sub: 'Cannot sign in' },
    { to: '/admin2026/inbox', icon: Inbox, tone: 'disc-brand', n: unread.value, title: 'Unread in inbox', sub: 'Sign-in alerts and messages' },
    {
      to: '/admin2026/landlords', icon: Building2, tone: 'disc-sky',
      n: rental.landlords.filter((l) => l.active && !rental.properties.some((x) => x.landlordId === l.id)).length,
      title: 'Landlords not set up', sub: 'Registered but no properties yet',
    },
    { to: '/admin2026/system', icon: Smartphone, tone: 'disc-amber', n: pay.value && !pay.value.enabled ? 1 : 0, title: 'Online payments are off', sub: 'Tenants can only pay cash' },
  ].filter((a) => a.n > 0),
)

const quick = [
  { to: '/admin2026/landlords?new=1', icon: UserPlus, label: 'Register landlord', tile: 'tile-teal' },
  { to: '/admin2026/broadcast', icon: Megaphone, label: 'Send announcement', tile: 'tile-violet' },
  { to: '/admin2026/transactions', icon: Wallet, label: 'All transactions', tile: 'tile-sky' },
  { to: '/admin2026/reports', icon: BarChart3, label: 'Statistics', tile: 'tile-amber' },
  { to: '/admin2026/properties', icon: Building2, label: 'All properties', tile: 'tile-slate' },
  { to: '/admin2026/activity', icon: Activity, label: 'Activity log', tile: 'tile-teal' },
]

const methodLabel = (m) => (/cash/i.test(m ?? '') ? 'Cash' : m || 'Mobile money')
const tenantName = (id) => rental.tenantById(id)?.name ?? 'Tenant'

// Online payments: on / test / off
const pay = ref(null)
onMounted(async () => {
  try {
    pay.value = await api('/api/payments/info')
  } catch {
    pay.value = { enabled: false, provider: 'unreachable' }
  }
})
const payText = computed(() => {
  if (!pay.value) return 'Checking…'
  if (pay.value.provider === 'unreachable') return 'Server not reachable'
  if (!pay.value.enabled) return 'Off'
  return pay.value.testMode ? 'Test mode' : `On · ${pay.value.provider === 'relworx' ? 'Relworx' : 'Flutterwave'}`
})

const greeting = (() => {
  const h = new Date().getHours()
  return h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening'
})()
</script>

<template>
  <div>
    <SuperHero eyebrow="Renta UG · Control centre" :title="greeting" subtitle="Everything happening on the platform, and what needs you now.">
      <RouterLink to="/admin2026/landlords?new=1" class="btn-primary"><UserPlus class="size-4" /> Register landlord</RouterLink>
      <RouterLink to="/admin2026/broadcast" class="btn-secondary"><Megaphone class="size-4" /> Announce</RouterLink>
      <template #stats>
        <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <StatTile glass label="Collected (all time)" :value="formatUGX(p.totalCollected.value)" hint="Rent paid by tenants" :icon="Wallet" to="/admin2026/transactions" />
          <StatTile glass label="This month" :value="formatUGX(p.monthCollected.value)" :hint="p.monthBilled.value ? `of ${formatUGX(p.monthBilled.value)} billed` : 'No rent billed yet'" :icon="ArrowDownLeft" tile="tile-sky" to="/admin2026/transactions" />
          <StatTile glass label="Unpaid rent" :value="formatUGX(p.outstanding.value)" :hint="`${p.overdueTenants.value} tenant${p.overdueTenants.value === 1 ? '' : 's'} overdue`" :icon="TriangleAlert" tile="tile-amber" :alert="p.overdueTenants.value > 0" to="/admin2026/tenants?show=overdue" />
          <StatTile glass label="Occupancy" :value="`${p.occupancy.value.rate}%`" :hint="`${p.occupancy.value.vacant} vacant of ${p.occupancy.value.total}`" :icon="Building2" tile="tile-violet" to="/admin2026/properties" />
        </div>
      </template>
    </SuperHero>

    <!-- People -->
    <div class="mb-6 grid grid-cols-2 gap-3 lg:grid-cols-4">
      <StatTile label="Landlords" :value="rental.landlords.length" :hint="`${activeLandlords} active`" :icon="Briefcase" to="/admin2026/landlords" />
      <StatTile label="Properties" :value="rental.properties.length" :hint="`${rental.rentals.length} rental business${rental.rentals.length === 1 ? '' : 'es'}`" :icon="Building2" tile="tile-sky" to="/admin2026/properties" />
      <StatTile label="Tenants" :value="currentTenants.length" :hint="`${connected} use the app`" :icon="Users" tile="tile-violet" to="/admin2026/tenants" />
      <StatTile label="Online payments" :value="payText" hint="MTN & Airtel" :icon="Smartphone" tile="tile-amber" to="/admin2026/system" />
    </div>

    <div class="grid gap-6 lg:grid-cols-5">
      <!-- Needs attention -->
      <section class="lg:col-span-2">
        <h2 class="section-title">Needs your attention</h2>
        <div class="sheet">
          <ul v-if="attention.length" class="divide-y divide-slate-100">
            <ListRow v-for="a in attention" :key="a.to" :to="a.to" :title="a.title" :subtitle="a.sub">
              <template #icon><span class="icon-disc" :class="a.tone"><component :is="a.icon" class="size-5" /></span></template>
              <template #value><span class="flex size-8 items-center justify-center rounded-full bg-slate-900 text-sm font-bold text-white">{{ a.n }}</span></template>
            </ListRow>
          </ul>
          <div v-else class="flex items-center gap-3.5 px-5 py-6">
            <span class="icon-disc disc-emerald"><CircleCheck class="size-5" /></span>
            <div>
              <p class="font-semibold text-slate-900">All clear</p>
              <p class="text-sm text-slate-500">Nothing is waiting for you right now.</p>
            </div>
          </div>
        </div>

        <h2 class="section-title mt-6">Quick actions</h2>
        <div class="grid grid-cols-2 gap-3">
          <RouterLink v-for="q in quick" :key="q.to" :to="q.to" class="quick group flex flex-col gap-3 rounded-2xl border border-slate-200 bg-white p-4 transition">
            <span class="icon-tile size-10 rounded-xl" :class="q.tile"><component :is="q.icon" class="size-5" /></span>
            <span class="flex items-center justify-between text-sm font-semibold text-slate-900">{{ q.label }} <ChevronRight class="size-4 text-slate-300 transition group-hover:translate-x-0.5" /></span>
          </RouterLink>
        </div>
      </section>

      <!-- Money -->
      <div class="space-y-6 lg:col-span-3">
        <Panel title="Money received" subtitle="Last 6 months, by the day it came in">
          <ColumnChart :data="p.byMonth.value" value-label="Received" :format="formatUGX" :tick="compactUGX" />
        </Panel>

        <div class="grid gap-6 sm:grid-cols-2">
          <Panel title="Top landlords" subtitle="Rent collected, all time">
            <RankBars :rows="p.byLandlord.value" :format="formatUGX" :limit="5" />
          </Panel>
          <Panel title="How tenants pay" subtitle="All payments received">
            <div class="space-y-3">
              <div v-for="(c, i) in p.channels.value" :key="c.label" class="rounded-2xl bg-slate-50 p-4">
                <p class="flex items-center gap-2 text-sm font-medium text-slate-700">
                  <span class="size-2.5 rounded-sm" :style="{ background: i ? 'var(--series-2)' : 'var(--series-1)' }" /> {{ c.label }}
                  <span class="ml-auto text-xs text-slate-500">{{ c.share }}%</span>
                </p>
                <p class="mt-1.5 text-lg font-bold text-slate-900 tabular-nums">{{ formatUGX(c.value) }}</p>
                <p class="text-xs text-slate-500">{{ c.count }} payment{{ c.count === 1 ? '' : 's' }}</p>
              </div>
            </div>
          </Panel>
        </div>
      </div>
    </div>

    <!-- Latest money + latest admin actions -->
    <div class="mt-6 grid gap-6 lg:grid-cols-2">
      <section>
        <div class="flex items-center justify-between">
          <h2 class="section-title">Latest money in</h2>
          <RouterLink to="/admin2026/transactions" class="mb-2.5 text-xs font-semibold text-brand-700">All transactions</RouterLink>
        </div>
        <div class="sheet">
          <ul v-if="p.recentReceipts.value.length" class="divide-y divide-slate-100">
            <ListRow
              v-for="r in p.recentReceipts.value.slice(0, 6)"
              :key="r.id"
              :to="`/admin2026/tenants/${r.tenantId}`"
              :title="tenantName(r.tenantId)"
              :subtitle="`${methodLabel(r.method)} · ${p.landlordName(r.landlordId)} · ${formatDate(r.receivedAt)}`"
              :value="formatUGX(r.amount)"
              value-class="text-emerald-700"
            >
              <template #icon>
                <span class="icon-disc" :class="/cash/i.test(r.method ?? '') ? 'disc-amber' : 'disc-emerald'">
                  <Banknote v-if="/cash/i.test(r.method ?? '')" class="size-5" />
                  <ArrowDownLeft v-else class="size-5" />
                </span>
              </template>
            </ListRow>
          </ul>
          <p v-else class="px-5 py-10 text-center text-sm text-slate-500">No payments yet.</p>
        </div>
      </section>

      <section>
        <div class="flex items-center justify-between">
          <h2 class="section-title">Your latest actions</h2>
          <RouterLink to="/admin2026/activity" class="mb-2.5 text-xs font-semibold text-brand-700">Activity log</RouterLink>
        </div>
        <div class="sheet">
          <ul v-if="rental.audit.length" class="divide-y divide-slate-100">
            <ListRow v-for="a in rental.audit.slice(0, 6)" :key="a.id" to="/admin2026/activity" :title="a.summary" :subtitle="formatDate(a.createdAt)" :chevron="false">
              <template #icon><span class="icon-disc disc-brand"><ShieldCheck class="size-5" /></span></template>
            </ListRow>
          </ul>
          <p v-else class="px-5 py-10 text-center text-sm text-slate-500">Changes you make appear here.</p>
        </div>
      </section>
    </div>
  </div>
</template>

<style scoped>
.quick { box-shadow: 0 1px 2px rgb(15 23 42 / 0.04); }
.quick:hover { transform: translateY(-2px); box-shadow: 0 14px 30px -20px rgb(15 23 42 / 0.4); }
.quick:active { transform: scale(0.98); }
</style>
