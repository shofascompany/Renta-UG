<script setup>
import { computed } from 'vue'
import { BadgeCheck, ChevronDown, ChevronRight, Star, TriangleAlert } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useSiteStats } from '@/composables/useSiteStats'
import { useFilter } from '@/composables/useFilter'
import { describeAgent } from '@/lib/device'
import { prettyPhone } from '@/lib/phone'
import { moveDay } from '@/utils/exactTime'
import { searcher } from '@/lib/search'
import { formatDate, formatUGX, timeAgo } from '@/utils/format'
import EmptyState from '@/components/EmptyState.vue'

// Main admin: every account that is signed in right now, with its information from the database (database/60).
// Tap one to see everything. Passwords, sign-in tokens and IP addresses are never sent here.
const { data, missing, error } = useSiteStats('admin_signed_in', ['app_devices', 'site_visits', 'tenants', 'payments'])

const rental = useRentalStore()
// Unpaid rent: every month they are behind, the same total as on every other page
const owedBy = (t) => (rental.tenantById(t.id)?.propertyId ? rental.payStateFor(t.id).owed : t.unpaid)
const owedTo = (a) => (rental.landlords.some((x) => x.id === a.id) ? rental.unpaidMonths.filter((m) => m.landlordId === a.id).reduce((s, m) => s + m.amount, 0) : a.landlord.unpaid)

const ROLE = { landlord: 'Landlord', tenant: 'Tenant', superadmin: 'Main admin' }
const who = useFilter('accounts', 'all', ['all', 'landlord', 'tenant', 'superadmin'])
const query = useFilter('accountq', '')
const accounts = computed(() => data.value?.accounts ?? [])
const placeOf = (t) => [t?.place, t?.rental].filter(Boolean).join(' · ')
const list = computed(() => {
  const hit = searcher(query.value)
  return accounts.value.filter(
    (a) => (who.value === 'all' || a.role === who.value) && hit(a.name, a.phone, a.email, ROLE[a.role], placeOf(a.tenant), a.tenant?.location, a.tenant?.landlordName, a.sessions.map((s) => describeAgent(s.agent)), a.appDevices.map((d) => d.device)),
  )
})
const counts = computed(() => Object.fromEntries(['all', 'landlord', 'tenant', 'superadmin'].map((k) => [k, accounts.value.filter((a) => k === 'all' || a.role === k).length])))

const moment = (iso) => (iso ? new Date(iso).toLocaleString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', hour: 'numeric', minute: '2-digit', hour12: true }) : '—')
const initials = (n) => (n ?? '?').split(' ').map((x) => x[0]).slice(0, 2).join('').toUpperCase()
const pageOf = (a) => (a.role === 'landlord' ? `/admin2026/landlords/${a.id}` : a.tenant?.id ? `/admin2026/tenants/${a.tenant.id}` : null)
const SOURCE = { website: 'app from the website', play: 'app from Google Play' }

// Everything the database has about this account, as rows
function facts(a) {
  const t = a.tenant
  const l = a.landlord
  return [
    ['Account', ROLE[a.role] ?? a.role],
    ['Phone', a.phone ? prettyPhone(a.phone) : '—'],
    ['Email', a.email ?? 'Signs in with the phone number'],
    ['Status', !a.enabled ? 'Suspended' : a.ready ? 'Active' : 'Not set up yet'],
    ['Joined', formatDate(a.joinedAt)],
    ['Last sign-in', moment(a.lastSignInAt)],
    ['Last active', moment(a.lastActive)],
    ...(t
      ? [
          [t.renting ? 'Lives in' : 'Last lived in', placeOf(t) || '—'],
          ['Location', t.location || '—'],
          ['Rent', t.rent ? `${formatUGX(t.rent)} a month` : '—'],
          ['Rent paid up to', t.renting ? (t.leaseEnd ? formatDate(t.leaseEnd) : 'Not paid yet') : `Left ${formatDate(t.endedAt)}`],
          ['Tenant since', formatDate(t.leaseStart)],
          ['Paid in total', formatUGX(t.paid)],
          ['Unpaid rent', formatUGX(owedBy(t))],
          ['Landlord', [t.landlordName, t.landlordPhone && prettyPhone(t.landlordPhone)].filter(Boolean).join(' · ') || '—'],
        ]
      : a.role === 'tenant' ? [['Lives in', 'Not connected to a house']] : []),
    ...(l
      ? [
          ['Houses and rooms', `${l.places}${l.rentals ? ` · ${l.rentals} rental business${l.rentals === 1 ? '' : 'es'}` : ''}`],
          ['Tenants', l.tenants],
          ['Collected', formatUGX(l.collected)],
          ['Unpaid rent', formatUGX(owedTo(a))],
          ['Subscription', l.exempt ? 'Free for life' : l.until ? `${l.tier === 'big' ? 'Big scale' : 'Small scale'}${l.plan ? `, ${l.plan}` : ''} · until ${formatDate(moveDay(l.until, 1))}` : 'Not paid yet'],
          ...(l.plannedUnits ? [['Plans to register', `${l.plannedUnits} houses and rooms`]] : []),
        ]
      : []),
    ['Website visits', a.webVisits ? `${a.webVisits} in 90 days · last ${timeAgo(a.lastWebVisit)}` : 'None recorded'],
    ['Rating', a.stars ? `${a.stars} of 5 stars` : 'Not rated'],
  ]
}
</script>

<template>
  <section>
    <div class="mt-6 flex items-baseline justify-between gap-3">
      <h2 class="section-title">Accounts signed in</h2>
      <p class="mb-2.5 text-sm font-semibold text-slate-900 tabular-nums">{{ data ? data.total.toLocaleString() : missing || error ? '—' : '…' }}</p>
    </div>
    <p v-if="missing" class="mb-3 flex items-start gap-2 rounded-xl bg-amber-50 p-3 text-sm text-amber-800">
      <TriangleAlert class="mt-0.5 size-4 shrink-0" /><span>Not set up yet. Run <strong>database/update_existing.sql</strong> in Supabase → SQL Editor, then refresh.</span>
    </p>
    <p v-else-if="error" class="form-error mb-3" role="alert">{{ error }}</p>
    <p v-if="data && !data.known" class="mb-3 rounded-xl bg-amber-50 p-3 text-sm text-amber-800">The database does not allow the sessions to be read here, so this lists every account that has ever signed in, latest first.</p>

    <input v-model="query" class="input" placeholder="Search name, phone, email, house or device" aria-label="Search accounts" />
    <div class="-mx-4 mt-3 flex gap-2 overflow-x-auto px-4 pb-1 sm:mx-0 sm:px-0">
      <button v-for="f in [['all', 'Everyone'], ['landlord', 'Landlords'], ['tenant', 'Tenants'], ['superadmin', 'Main admin']]" :key="f[0]" type="button" class="h-9 shrink-0 rounded-full px-4 text-sm font-medium transition" :class="who === f[0] ? 'bg-slate-900 text-white' : 'bg-slate-100 text-slate-600 hover:bg-slate-200'" @click="who = f[0]">{{ f[1] }} <span class="text-xs opacity-60 tabular-nums">{{ counts[f[0]] }}</span></button>
    </div>

    <div class="sheet mt-3">
      <ul v-if="list.length" class="divide-y divide-slate-100">
        <li v-for="a in list" :key="a.id">
          <details class="acc group">
            <summary class="flex cursor-pointer list-none items-center gap-3.5 px-4 py-4 transition-colors hover:bg-slate-50 sm:px-5">
              <span class="icon-disc size-11 shrink-0 rounded-full text-xs font-bold" :class="a.role === 'landlord' ? 'disc-solid' : a.role === 'tenant' ? 'disc-brand' : 'disc-amber'">{{ initials(a.name) }}</span>
              <span class="min-w-0 flex-1">
                <span class="flex items-center gap-1.5"><span class="truncate font-medium text-slate-900">{{ a.name || a.email || 'No name' }}</span><BadgeCheck v-if="a.landlord?.exempt" class="size-4 shrink-0 text-amber-500" aria-label="Permanent account" /></span>
                <span class="mt-0.5 block truncate text-xs text-slate-500">{{ ROLE[a.role] }} · {{ a.phone ? prettyPhone(a.phone) : a.email ?? 'no phone' }}</span>
                <span class="mt-0.5 block truncate text-[11px] text-slate-400">{{ a.tenant ? placeOf(a.tenant) || 'Not renting' : a.landlord ? `${a.landlord.places} house${a.landlord.places === 1 ? '' : 's'}/rooms · ${a.landlord.tenants} tenant${a.landlord.tenants === 1 ? '' : 's'}` : '' }}</span>
              </span>
              <span class="shrink-0 text-right text-[11px] text-slate-500">
                <span class="block font-medium text-slate-700">{{ a.lastActive ? timeAgo(a.lastActive) : '—' }}</span>
                <span v-if="a.sessions.length" class="mt-0.5 block">{{ a.sessions.length }} sign-in{{ a.sessions.length === 1 ? '' : 's' }}</span>
              </span>
              <ChevronDown class="size-4 shrink-0 text-slate-300 transition-transform group-open:rotate-180" />
            </summary>

            <div class="border-t border-slate-100 bg-slate-50/60 px-4 py-4 sm:px-5">
              <dl class="grid gap-x-8 gap-y-0 text-sm sm:grid-cols-2">
                <div v-for="f in facts(a)" :key="f[0]" class="flex justify-between gap-4 border-b border-slate-200/60 py-2">
                  <dt class="shrink-0 text-slate-500">{{ f[0] }}</dt><dd class="min-w-0 text-right font-medium break-words text-slate-900">{{ f[1] }}</dd>
                </div>
              </dl>
              <template v-if="a.sessions.length">
                <p class="mt-4 text-xs font-semibold tracking-wide text-slate-500 uppercase">Signed in on</p>
                <ul class="mt-1.5 space-y-1.5">
                  <li v-for="(s, i) in a.sessions" :key="i" class="flex justify-between gap-4 rounded-xl bg-white px-3 py-2 text-xs ring-1 ring-slate-200/70"><span class="min-w-0 text-slate-700">{{ describeAgent(s.agent) || 'Device not reported' }}</span><span class="shrink-0 text-right text-slate-500">since {{ moment(s.signedInAt) }}</span></li>
                </ul>
              </template>
              <template v-if="a.appDevices.length">
                <p class="mt-4 text-xs font-semibold tracking-wide text-slate-500 uppercase">Android app</p>
                <ul class="mt-1.5 space-y-1.5">
                  <li v-for="(d, i) in a.appDevices" :key="i" class="flex justify-between gap-4 rounded-xl bg-white px-3 py-2 text-xs ring-1 ring-slate-200/70"><span class="min-w-0 text-slate-700">{{ d.device || 'Android phone' }} · {{ SOURCE[d.source] }}</span><span class="shrink-0 text-right text-slate-500">used {{ moment(d.lastAt) }}</span></li>
                </ul>
              </template>
              <div class="mt-4 flex items-center gap-3">
                <span v-if="a.stars" class="flex gap-0.5" role="img" :aria-label="`${a.stars} of 5 stars`"><Star v-for="n in 5" :key="n" class="size-4" :class="n <= a.stars ? 'fill-amber-400 text-amber-400' : 'text-slate-300'" stroke-width="1.5" /></span>
                <RouterLink v-if="pageOf(a)" :to="pageOf(a)" class="ml-auto inline-flex items-center gap-1 text-sm font-semibold text-brand-700">Open their page <ChevronRight class="size-4" /></RouterLink>
              </div>
            </div>
          </details>
        </li>
      </ul>
      <EmptyState v-else compact kind="people" :title="!data ? (missing || error ? 'No accounts to show' : 'Loading…') : query || who !== 'all' ? 'No accounts match' : 'Nobody is signed in'" />
    </div>
    <p class="mt-2 px-1 text-xs text-slate-400">Signed in = not signed out yet, on any phone or computer. Tap an account for everything the database has about it.</p>
  </section>
</template>

<style scoped>
.acc summary::-webkit-details-marker { display: none; }
</style>
