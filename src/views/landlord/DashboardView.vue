<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import {
  Wallet, Building2, Banknote, CalendarCheck, DoorOpen, ChevronRight, CalendarClock, ArrowDownLeft, BarChart3, Plus, History, Trophy,
  Smartphone, House, UserCog, Send, AlertCircle,
} from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useAuthStore } from '@/stores/auth'
import { useRentAnalytics, compactUGX, longMonth } from '@/composables/useRentAnalytics'
import { formatUGX, formatDate } from '@/utils/format'
import Panel from '@/components/admin/Panel.vue'
import ListRow from '@/components/admin/ListRow.vue'
import ColumnChart from '@/components/charts/ColumnChart.vue'
import RankBars from '@/components/charts/RankBars.vue'

// Landlord overview: total revenue, the best house, cash vs mobile money, properties,
// how long each tenant has left, and what needs action. Every row opens its details.
const rental = useRentalStore()
const auth = useAuthStore()
const a = useRentAnalytics()

const fullName = computed(() => auth.profile?.full_name?.trim() ?? '')

// Subtitle under the greeting: a new sentence every few seconds, built from the landlord's own numbers
const lines = computed(() => {
  const out = ['Here is how things are doing today.']
  const tenants = rental.currentTenants.length
  const vacant = a.occupancy.value.vacant
  const owing = a.topDebtors.value.length
  const month = a.thisMonth.value
  if (month.collected) out.push(`You have collected ${formatUGX(month.collected)} this month.`)
  if (month.billed) out.push(`${month.rate}% of this month's rent is already in.`)
  if (tenants) out.push(`${tenants} tenant${tenants === 1 ? ' is' : 's are'} renting from you right now.`)
  if (owing) out.push(`${owing} tenant${owing === 1 ? ' still has' : 's still have'} rent to pay.`)
  else if (tenants) out.push('Every tenant is up to date with their rent.')
  if (vacant) out.push(`${vacant} room${vacant === 1 ? ' is' : 's are'} ready for a new tenant.`)
  else if (rental.properties.length) out.push('Every room you own is occupied.')
  if (cashToConfirm.value.length) out.push(`${cashToConfirm.value.length} cash payment${cashToConfirm.value.length === 1 ? ' is' : 's are'} waiting for you to confirm.`)
  out.push('Tap any row below to see its full details.')
  return out
})
const lineIndex = ref(0)
const line = computed(() => lines.value[lineIndex.value % lines.value.length])
let lineTimer = null
onMounted(() => {
  if (window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) return
  lineTimer = setInterval(() => (lineIndex.value += 1), 4000)
})
onBeforeUnmount(() => clearInterval(lineTimer))
const today = new Date().toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long' })

const chart = computed(() =>
  a.months6.value.map((m) => ({ label: m.label, full: longMonth(m.period), value: m.collected, ghost: m.billed })),
)
const cashToConfirm = computed(() => rental.pendingCash.filter((c) => c.submittedRole === 'tenant'))


// My properties: rentals (with their rooms) and standalone houses
const collectedAt = (id) => a.byHouse.value.find((h) => h.id === id)?.value ?? 0
const places = computed(() => {
  const rentals = rental.rentals.map((r) => {
    const rooms = rental.roomsOf(r.id)
    const occupied = rooms.filter((p) => rental.tenantForProperty(p.id)).length
    return {
      key: r.id, kind: 'rental', to: `/landlord/rentals/${r.id}`, name: r.name,
      sub: `${rooms.length} room${rooms.length === 1 ? '' : 's'} · ${occupied} occupied`,
      collected: rooms.reduce((s, p) => s + collectedAt(p.id), 0),
    }
  })
  const houses = rental.properties
    .filter((p) => !p.rentalId || !rental.rentalById(p.rentalId))
    .map((p) => {
      const t = rental.tenantForProperty(p.id)
      return { key: p.id, kind: 'house', to: `/landlord/properties/${p.id}`, name: p.name, sub: t ? t.name : 'Vacant', collected: collectedAt(p.id), vacant: !t }
    })
  return [...rentals, ...houses]
})

// More than one rental / house → compare them; just one → its months
const manyPlaces = computed(() => places.value.length > 1)
// Rental (or house) that earned the most — shown when there are 2+ properties to compare
const best = computed(() => {
  if (places.value.length < 2) return null
  const top = [...places.value].sort((x, y) => y.collected - x.collected)[0]
  return top.collected > 0 ? top : null
})


// This month's rent (shown when there's only one rental)
const monthName = new Date().toLocaleDateString('en-GB', { month: 'long', year: 'numeric' })
const monthCounts = computed(() => {
  const period = new Date().toLocaleDateString('en-CA').slice(0, 7)
  const charges = rental.payments.filter((p) => p.period === period)
  return { paid: charges.filter((p) => p.status === 'paid').length, unpaid: charges.filter((p) => p.status !== 'paid').length }
})

const placeBars = computed(() =>
  [...places.value].sort((x, y) => y.collected - x.collected).map((p) => ({ label: p.name, value: p.collected })),
)

// Cash vs mobile money
const mobile = computed(() => a.channels.value[0])
const cash = computed(() => a.channels.value[1])
const paymentsCount = computed(() => mobile.value.count + cash.value.count)

const stays = computed(() => a.tenancies.value.slice(0, 5))
const recent = computed(() => a.revenue.value.slice(0, 5))
const debtors = computed(() => a.topDebtors.value.slice(0, 4))
const managedCount = computed(() => rental.currentTenants.filter((t) => t.managedByLandlord && !t.userId).length)

const tenantName = (id) => rental.tenantById(id)?.name ?? 'Former tenant'
const tenantLink = (t) => `/landlord/tenants/${t.id}`
const leftTone = (d) => (d === null ? 'disc-slate' : d <= 7 ? 'disc-red' : d <= 30 ? 'disc-amber' : 'disc-sky')
</script>

<template>
  <div class="mx-auto max-w-6xl space-y-6">
    <!-- Total revenue -->
    <section class="page-hero rise px-4 py-5 sm:px-8 sm:py-8">
      <p class="text-[11px] font-semibold tracking-[0.14em] text-white/70 uppercase sm:text-xs">{{ today }}</p>

      <!-- Greeting -->
      <h1 class="mt-2 text-2xl leading-tight font-bold tracking-tight sm:text-3xl">Hello, {{ fullName || 'there' }}</h1>
      <div class="relative mt-1.5 h-6 overflow-hidden sm:h-7" aria-live="polite">
        <Transition name="line">
          <p :key="line" class="absolute inset-x-0 truncate text-sm text-white/80 sm:text-base">{{ line }}</p>
        </Transition>
      </div>

      <div class="mt-4 grid grid-cols-2 gap-2 sm:mt-6 sm:max-w-md sm:gap-3">
        <RouterLink to="/landlord/payments" class="hero-stat hero-stat-link">
          <p class="hero-stat-label">Revenue</p>
          <p class="hero-stat-value flex items-center justify-between gap-1 text-base sm:text-xl">{{ compactUGX(a.thisMonth.value.collected) }} <ChevronRight class="size-4 shrink-0 text-white/60" /></p>
        </RouterLink>
        <RouterLink :to="{ path: '/landlord/properties', query: { show: 'vacant' } }" class="hero-stat hero-stat-link">
          <p class="hero-stat-label">Unoccupied</p>
          <p class="hero-stat-value flex items-center justify-between gap-1 text-base sm:text-xl">
            {{ a.occupancy.value.vacant }} {{ a.occupancy.value.vacant === 1 ? 'room' : 'rooms' }}
            <ChevronRight class="size-4 shrink-0 text-white/60" />
          </p>
        </RouterLink>
      </div>

      <div class="mt-4 grid grid-cols-2 gap-2 sm:mt-6 sm:flex sm:flex-wrap sm:gap-2.5">
        <RouterLink to="/landlord/revenue" class="hero-btn hero-btn-solid"><History class="size-4" /> Transactions</RouterLink>
        <RouterLink to="/landlord/payments" class="hero-btn hero-btn-glass"><Wallet class="size-4" /> Payments</RouterLink>
      </div>
    </section>

    <!-- Needs action -->
    <RouterLink
      v-if="cashToConfirm.length"
      to="/landlord/payments"
      class="rise flex items-center gap-4 rounded-2xl border border-amber-200 bg-amber-50 p-4 transition hover:bg-amber-100/60"
    >
      <span class="icon-disc disc-amber bg-white"><Banknote class="size-5" /></span>
      <div class="min-w-0 flex-1">
        <p class="font-semibold text-slate-900">{{ cashToConfirm.length }} cash payment{{ cashToConfirm.length === 1 ? '' : 's' }} to confirm</p>
        <p class="truncate text-sm text-slate-600">Tenants say they paid you in cash.</p>
      </div>
      <ChevronRight class="size-5 shrink-0 text-amber-700" />
    </RouterLink>

    <!-- Tenants asking to leave -->
    <RouterLink
      v-if="rental.pendingMoveOuts.length"
      to="/landlord/move-outs"
      class="rise flex items-center gap-4 rounded-2xl border border-sky-200 bg-sky-50 p-4 transition hover:bg-sky-100/60"
    >
      <span class="icon-tile tile-sky"><DoorOpen class="size-5" /></span>
      <div class="min-w-0 flex-1">
        <p class="font-semibold text-slate-900">{{ rental.pendingMoveOuts.length }} request{{ rental.pendingMoveOuts.length === 1 ? '' : 's' }} to leave</p>
        <p class="truncate text-sm text-slate-600">A tenant wants to move out. Review and approve or decline.</p>
      </div>
      <ChevronRight class="size-5 shrink-0 text-sky-700" />
    </RouterLink>
    <!-- Getting started -->
    <Panel v-if="!rental.properties.length" title="Get started">
      <ol class="grid gap-3 text-sm text-slate-600 sm:grid-cols-3">
        <li class="flex items-center gap-3"><span class="icon-disc disc-solid size-8 rounded-full text-xs font-bold">1</span> Add a house or a rental with rooms</li>
        <li class="flex items-center gap-3"><span class="icon-disc disc-brand size-8 rounded-full text-xs font-bold">2</span> Put a tenant in each one</li>
        <li class="flex items-center gap-3"><span class="icon-disc disc-brand size-8 rounded-full text-xs font-bold">3</span> Record rent as tenants pay</li>
      </ol>
      <RouterLink to="/landlord/properties" class="btn-primary mt-5 h-11"><Plus class="size-4" /> Add property</RouterLink>
    </Panel>

    <div class="grid gap-6 lg:grid-cols-5">
      <!-- Top earning rentals (only when there's more than one to compare) -->
      <section v-if="manyPlaces" class="rise lg:col-span-2" style="--d: 60ms">
        <h2 class="section-title">Top earner</h2>
        <div class="sheet">
          <RouterLink v-if="best" to="/landlord/earnings" class="tile-glow block px-5 py-5">
            <div class="flex items-center gap-3.5">
              <span class="icon-tile tile-amber size-12"><Trophy class="size-6" /></span>
              <div class="min-w-0 flex-1">
                <p class="text-xs font-semibold tracking-wider text-amber-700 uppercase">{{ best.kind === 'rental' ? 'Rental that earned the most' : 'Earned the most' }}</p>
                <p class="truncate text-lg font-semibold text-slate-900">{{ best.name }}</p>
              </div>
              <ChevronRight class="size-5 shrink-0 text-slate-400" />
            </div>
            <p class="mt-5 text-xs font-medium text-slate-500">Money collected</p>
            <p class="mt-0.5 text-3xl font-bold tracking-tight text-slate-900 tabular-nums">{{ formatUGX(best.collected) }}</p>
          </RouterLink>
          <div v-else class="flex items-center gap-3.5 px-5 py-6">
            <span class="icon-tile tile-slate size-12"><Trophy class="size-6" /></span>
            <p class="text-sm text-slate-500">Your top earning rental shows here once rent comes in.</p>
          </div>
        </div>
      </section>

      <!-- One rental: this month's rent instead -->
      <section v-else class="rise lg:col-span-2" style="--d: 60ms">
        <h2 class="section-title">This month's rent</h2>
        <RouterLink to="/landlord/payments" class="sheet block p-5 transition hover:bg-slate-50">
          <div class="flex items-center gap-3.5">
            <span class="icon-tile tile-teal size-12"><CalendarCheck class="size-6" /></span>
            <div class="min-w-0 flex-1">
              <p class="text-xs font-semibold tracking-wider text-brand-700 uppercase">{{ monthName }}</p>
              <p class="text-lg font-semibold text-slate-900">{{ formatUGX(a.thisMonth.value.collected) }} <span class="text-sm font-normal text-slate-500">of {{ formatUGX(a.thisMonth.value.billed) }}</span></p>
            </div>
            <ChevronRight class="size-5 shrink-0 text-slate-400" />
          </div>
          <div class="mt-4 h-2.5 overflow-hidden rounded-full bg-slate-100">
            <div class="h-full rounded-full bg-gradient-to-r from-teal-400 to-teal-700" :style="{ width: `${a.thisMonth.value.rate}%` }" />
          </div>
          <div class="mt-4 grid grid-cols-2 gap-3 text-sm">
            <div class="rounded-2xl bg-slate-50 p-3.5">
              <p class="text-xs text-slate-500">Paid</p>
              <p class="mt-0.5 text-lg font-bold text-slate-900">{{ monthCounts.paid }} <span class="text-xs font-normal text-slate-500">tenant{{ monthCounts.paid === 1 ? '' : 's' }}</span></p>
            </div>
            <div class="rounded-2xl p-3.5" :class="monthCounts.unpaid ? 'bg-amber-50' : 'bg-slate-50'">
              <p class="text-xs" :class="monthCounts.unpaid ? 'text-amber-700' : 'text-slate-500'">Still to pay</p>
              <p class="mt-0.5 text-lg font-bold" :class="monthCounts.unpaid ? 'text-amber-800' : 'text-slate-900'">{{ monthCounts.unpaid }} <span class="text-xs font-normal opacity-70">tenant{{ monthCounts.unpaid === 1 ? '' : 's' }}</span></p>
            </div>
          </div>
          <p v-if="!a.thisMonth.value.billed" class="mt-3 text-xs text-slate-500">No rent for this month yet.</p>
        </RouterLink>
      </section>
      <!-- Cash vs mobile money -->
      <section class="rise lg:col-span-3" style="--d: 100ms">
        <h2 class="section-title">Payment methods</h2>
        <div class="sheet p-5">
          <div v-if="paymentsCount" class="flex items-start gap-3.5">
            <span class="icon-disc disc-solid size-12 rounded-2xl">
              <Smartphone v-if="a.topChannel.value.label === 'Mobile money'" class="size-6" />
              <Banknote v-else class="size-6" />
            </span>
            <div class="min-w-0">
              <p class="text-xs font-semibold tracking-wider text-brand-700 uppercase">Used most</p>
              <p class="text-lg font-semibold text-slate-900">{{ a.topChannel.value.label }}</p>
              <p class="text-sm text-slate-500">{{ a.topChannel.value.count }} of {{ paymentsCount }} payments</p>
            </div>
          </div>
          <p v-else class="text-sm text-slate-500">Once tenants pay, you'll see here whether they use cash or mobile money.</p>

          <!-- one whole split in two, labelled below so colour is never the only cue -->
          <div class="viz mt-5">
            <div v-if="paymentsCount" class="flex h-3 gap-0.5 overflow-hidden" role="img" :aria-label="`Mobile money ${mobile.share}%, cash ${cash.share}%`">
              <div v-if="mobile.value" class="h-full rounded-full" :style="{ width: `${mobile.share}%`, background: 'var(--series-1)' }" />
              <div v-if="cash.value" class="h-full rounded-full" :style="{ width: `${cash.share}%`, background: 'var(--series-2)' }" />
            </div>
            <div v-else class="h-3 rounded-full bg-slate-100" />

            <div class="mt-4 grid grid-cols-2 gap-3">
              <div v-for="(c, i) in [mobile, cash]" :key="c.label" class="rounded-2xl bg-slate-50 p-4">
                <p class="flex items-center gap-2 text-sm font-medium text-slate-700">
                  <span class="size-2.5 rounded-sm" :style="{ background: i ? 'var(--series-2)' : 'var(--series-1)' }" />
                  {{ c.label }}
                </p>
                <p class="mt-2 text-base font-bold text-slate-900 tabular-nums sm:text-xl">{{ formatUGX(c.value) }}</p>
                <p class="text-xs text-slate-500">{{ c.count }} payment{{ c.count === 1 ? '' : 's' }} · {{ c.share }}%</p>
              </div>
            </div>
          </div>
        </div>
      </section>

      <!-- My properties -->
      <section class="rise lg:col-span-3" style="--d: 140ms">
        <div class="flex items-center justify-between">
          <h2 class="section-title">My properties</h2>
          <RouterLink to="/landlord/properties" class="mb-2.5 text-xs font-semibold text-brand-700">See all</RouterLink>
        </div>
        <div class="sheet">
          <ul v-if="places.length" class="divide-y divide-slate-100">
            <ListRow
              v-for="p in places.slice(0, 6)"
              :key="p.key"
              :to="p.to"
              :title="p.name"
              :subtitle="p.sub"
              :value="formatUGX(p.collected)"
              value-sub="collected"
            >
              <template #icon>
                <span class="icon-tile" :class="p.kind === 'rental' ? 'tile-teal' : p.vacant ? 'tile-slate' : 'tile-sky'">
                  <Building2 v-if="p.kind === 'rental'" class="size-[1.35rem]" />
                  <House v-else class="size-[1.35rem]" />
                </span>
              </template>
            </ListRow>
          </ul>
          <p v-else class="px-5 py-10 text-center text-sm text-slate-500">No properties yet.</p>
        </div>
      </section>

      <!-- Time left in their rooms -->
      <section class="rise lg:col-span-2" style="--d: 180ms">
        <div class="flex items-center justify-between">
          <h2 class="section-title">Rental time</h2>
          <RouterLink to="/landlord/tenants" class="mb-2.5 text-xs font-semibold text-brand-700">All tenants</RouterLink>
        </div>
        <div class="sheet">
          <ul v-if="stays.length" class="divide-y divide-slate-100">
            <ListRow v-for="t in stays" :key="t.id" :to="tenantLink(t)" :title="t.name" :subtitle="rental.placeName(t.propertyId)">
              <template #icon><span class="icon-disc rounded-full" :class="leftTone(t.daysLeft)"><CalendarClock class="size-5" /></span></template>
              <template #below>
                <div v-if="t.used !== null" class="mt-2 h-1.5 overflow-hidden rounded-full bg-slate-100">
                  <div class="h-full rounded-full bg-brand-500" :style="{ width: `${t.used}%` }" />
                </div>
              </template>
              <template #value>
                <p class="text-sm font-semibold" :class="t.daysLeft !== null && t.daysLeft <= 30 ? 'text-amber-700' : 'text-slate-900'">{{ t.left.replace(' left', '') }}</p>
                <p class="mt-0.5 text-[11px] text-slate-500">{{ t.leaseEnd ? `paid to ${formatDate(t.leaseEnd)}` : 'not paid yet' }}</p>
              </template>
            </ListRow>
          </ul>
          <p v-else class="px-5 py-10 text-center text-sm text-slate-500">No tenants yet.</p>
        </div>
      </section>

      <!-- Rent collected: per rental when there are several, per month when there's one -->
      <Panel
        class="rise lg:col-span-3"
        style="--d: 220ms"
        title="Rent collected"
        :subtitle="manyPlaces ? `Total collected in each of your ${places.length} properties` : 'Last 6 months · against what was billed'"
      >
        <template v-if="manyPlaces">
          <RankBars :rows="placeBars" :format="formatUGX" :limit="6" />
          <RouterLink to="/landlord/earnings" class="btn-secondary mt-5 h-11 w-full">
            See details of each rental <ChevronRight class="size-4" />
          </RouterLink>
        </template>
        <ColumnChart v-else :data="chart" value-label="Collected" ghost-label="Billed" :format="formatUGX" :tick="compactUGX" />
      </Panel>

      <!-- Who owes -->
      <section class="rise lg:col-span-2" style="--d: 260ms">
        <h2 class="section-title">Unpaid rent</h2>
        <div class="sheet">
          <ul v-if="debtors.length" class="divide-y divide-slate-100">
            <ListRow v-for="t in debtors" :key="t.id" :to="tenantLink(t)" :title="t.name" :subtitle="rental.placeName(t.propertyId)" :value="formatUGX(t.owed)" value-class="text-red-600">
              <template #icon><span class="icon-disc disc-red rounded-full"><AlertCircle class="size-5" /></span></template>
            </ListRow>
          </ul>
          <p v-else class="px-5 py-10 text-center text-sm text-slate-500">Nobody owes rent right now.</p>
        </div>
      </section>

      <!-- Recent money in -->
      <section class="rise lg:col-span-3" style="--d: 300ms">
        <div class="flex items-center justify-between">
          <h2 class="section-title">Latest money in</h2>
          <RouterLink to="/landlord/revenue" class="mb-2.5 text-xs font-semibold text-brand-700">All transactions</RouterLink>
        </div>
        <div class="sheet">
          <ul v-if="recent.length" class="divide-y divide-slate-100">
            <ListRow
              v-for="r in recent"
              :key="r.id"
              :to="{ path: '/landlord/revenue', query: { open: r.id } }"
              :title="tenantName(r.tenantId)"
              :subtitle="`${r.channel === 'Cash' ? 'Cash' : r.method || 'Mobile money'} · ${formatDate(r.at)}`"
              :value="formatUGX(r.amount)"
              value-class="text-emerald-700"
            >
              <template #icon>
                <span class="icon-disc" :class="r.channel === 'Cash' ? 'disc-amber' : 'disc-emerald'">
                  <Banknote v-if="r.channel === 'Cash'" class="size-5" />
                  <ArrowDownLeft v-else class="size-5" />
                </span>
              </template>
            </ListRow>
          </ul>
          <p v-else class="px-5 py-10 text-center text-sm text-slate-500">No payments yet.</p>
        </div>
      </section>

      <!-- Shortcuts -->
      <section class="rise lg:col-span-2" style="--d: 340ms">
        <h2 class="section-title">Shortcuts</h2>
        <div class="sheet">
          <ul class="divide-y divide-slate-100">
            <ListRow to="/landlord/managed" title="Accounts without smartphones" :subtitle="`${managedCount} tenant${managedCount === 1 ? '' : 's'} you look after`">
              <template #icon><span class="icon-disc disc-slate"><UserCog class="size-5" /></span></template>
            </ListRow>
            <ListRow to="/landlord/notifications" title="Send a notice" subtitle="Message one tenant or everyone">
              <template #icon><span class="icon-disc disc-sky"><Send class="size-5" /></span></template>
            </ListRow>
            <ListRow to="/landlord/properties" title="Add a house or rental" subtitle="Several rooms in one business">
              <template #icon><span class="icon-disc disc-brand"><Building2 class="size-5" /></span></template>
            </ListRow>
          </ul>
        </div>
      </section>
    </div>

    <!-- Bottom button -->
    <RouterLink
      to="/landlord/reports"
      class="rise flex h-14 w-full items-center justify-center gap-2 rounded-2xl text-[15px] font-semibold text-white shadow-lg shadow-brand-900/20 transition hover:brightness-110 active:scale-[0.99]"
      style="--d: 380ms; background: linear-gradient(120deg, #14918a, #0f766e 50%, #0a3b38)"
    >
      <BarChart3 class="size-5" /> Open full reports
    </RouterLink>
  </div>
</template>

<style scoped>
/* Greeting subtitle: old line slides up and out, new one rises in */
.line-enter-active, .line-leave-active { transition: opacity 0.45s ease, transform 0.45s cubic-bezier(0.22, 1, 0.36, 1); }
.line-enter-from { opacity: 0; transform: translateY(100%); }
.line-leave-to { opacity: 0; transform: translateY(-100%); }
</style>
