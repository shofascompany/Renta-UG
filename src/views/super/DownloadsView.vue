<script setup>
import { computed } from 'vue'
import { Apple, ChevronRight, Download, Globe, Laptop, LogIn, Monitor, MonitorSmartphone, RefreshCw, Smartphone, TriangleAlert, Users } from '@lucide/vue'
import { SITE } from '@/lib/site'
import { prettyPhone } from '@/lib/phone'
import { searcher } from '@/lib/search'
import { dayOf } from '@/utils/format'
import { useFilter } from '@/composables/useFilter'
import { useSiteStats } from '@/composables/useSiteStats'
import SuperHero from '@/components/super/SuperHero.vue'
import StatTile from '@/components/super/StatTile.vue'
import SignedInAccounts from '@/components/super/SignedInAccounts.vue'
import Panel from '@/components/admin/Panel.vue'
import ColumnChart from '@/components/charts/ColumnChart.vue'
import EmptyState from '@/components/EmptyState.vue'

// Main admin: visits to the website and downloads of the app, live, with the proof behind each number.
//   visit      the website was opened (signing in there is part of the visit), on any system
//   download   an account signed in inside the Android app
// Everything records itself (lib/installs.js → database/59), so nothing is typed in.
const HOST = new URL(SITE.url).host // the official website
const SYSTEMS = {
  android: { label: 'Android', icon: Smartphone },
  ios: { label: 'iPhone & iPad', icon: Apple },
  windows: { label: 'Windows', icon: Monitor },
  mac: { label: 'Mac', icon: Laptop },
  other: { label: 'Other', icon: Globe },
}
const SOURCE = { website: 'From the website', play: 'Google Play' }

const { data: site, missing, error, live, updatedAt, load } = useSiteStats('site_stats', ['site_visit_days', 'site_visits', 'app_devices', 'web_installs'])
const { data: details, error: detailsError, load: loadDetails } = useSiteStats('site_details', ['site_visits', 'app_devices', 'web_installs'])
const refresh = () => Promise.all([load(), loadDetails()])

const fmt = (n) => Number(n || 0).toLocaleString()
const num = (n) => (site.value ? fmt(n) : missing.value || error.value ? '—' : '…')
const plural = (n, one, many = `${one}s`) => `${num(n)} ${Number(n) === 1 ? one : many}`

const periods = computed(() => [
  { label: 'Today', visits: site.value?.today, visitors: site.value?.todayVisitors },
  { label: 'Last 7 days', visits: site.value?.week, visitors: site.value?.weekVisitors },
  { label: 'Last 30 days', visits: site.value?.month, visitors: site.value?.monthVisitors },
  { label: 'All time', visits: site.value?.visits, visitors: site.value?.visitors },
])
// The last 14 days, with the quiet ones shown as zero
const chart = computed(() => {
  if (!site.value?.day) return []
  const by = Object.fromEntries((site.value.days ?? []).map((d) => [d.day, d]))
  const end = new Date(`${site.value.day}T12:00:00Z`).getTime()
  return Array.from({ length: 14 }, (_, i) => {
    const date = new Date(end - (13 - i) * 86_400_000)
    return {
      label: String(date.getUTCDate()),
      full: date.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'long', timeZone: 'UTC' }),
      value: by[date.toISOString().slice(0, 10)]?.visits ?? 0,
    }
  })
})
const tick = (v) => (Number.isInteger(v) ? v.toLocaleString('en', { notation: 'compact' }) : '')
const systems = computed(() => {
  const n = site.value?.systems ?? {}
  const total = Object.values(n).reduce((s, x) => s + x, 0)
  return Object.entries(SYSTEMS).map(([key, s]) => ({ key, ...s, n: n[key] ?? 0, share: total ? Math.round(((n[key] ?? 0) / total) * 100) : 0 }))
})

// ── The records ──
const tab = useFilter('tab', 'downloads', ['downloads', 'visits', 'installed'])
const who = useFilter('who', 'all', ['all', 'landlord', 'tenant', 'out'])
const query = useFilter('q', '')
const moment = (iso) => new Date(iso).toLocaleString('en-GB', { day: 'numeric', month: 'short', year: dayOf(iso).slice(0, 4) === dayOf(new Date()).slice(0, 4) ? undefined : 'numeric', hour: 'numeric', minute: '2-digit', hour12: true })
const roleName = { landlord: 'Landlord', tenant: 'Tenant' }
const pageOf = (r) => (r.role === 'landlord' && r.userId ? `/admin2026/landlords/${r.userId}` : r.tenantId ? `/admin2026/tenants/${r.tenantId}` : null)
const downloads = computed(() => {
  const hit = searcher(query.value)
  return (details.value?.downloads ?? [])
    .filter((d) => ['all', d.role].includes(who.value))
    .map((d) => ({
      id: d.id, to: pageOf(d), icon: Download, tone: 'disc-emerald', title: d.userId ? d.name || 'No name' : 'Deleted account',
      sub: [roleName[d.role], d.phone ? prettyPhone(d.phone) : d.email, d.device || 'Android phone'].filter(Boolean).join(' · '),
      note: `${SOURCE[d.source]} · phone ${d.phoneCode}`, at: d.firstAt, end: dayOf(d.lastAt) === dayOf(d.firstAt) ? '' : `used ${moment(d.lastAt)}`, phone: d.phone,
    }))
    .filter((d) => hit(d.title, d.sub, d.note, d.phone))
})
const visits = computed(() => {
  const hit = searcher(query.value)
  return (details.value?.visits ?? [])
    .filter((v) => who.value === 'all' || (who.value === 'out' ? !v.signedInAt : v.role === who.value))
    .map((v) => ({
      id: v.id, to: pageOf(v), icon: v.signedInAt ? LogIn : (SYSTEMS[v.system] ?? SYSTEMS.other).icon, tone: v.signedInAt ? 'disc-sky' : 'disc-slate',
      title: v.signedInAt ? (v.userId ? v.name || 'No name' : 'Deleted account') : 'Visitor',
      sub: [v.signedInAt ? `${roleName[v.role] ?? 'Account'} · signed in on the website` : 'Not signed in', (SYSTEMS[v.system] ?? SYSTEMS.other).label].join(' · '),
      note: v.device, at: v.at, end: '',
    }))
    .filter((v) => hit(v.title, v.sub, v.note))
})
const installed = computed(() => {
  const hit = searcher(query.value)
  return (details.value?.installed ?? [])
    .map((x) => ({ id: x.code + x.at, to: null, icon: Smartphone, tone: 'disc-amber', title: 'Android phone', sub: 'App installed, nobody has signed in yet', note: `phone ${x.code}`, at: x.at, end: '' }))
    .filter((x) => hit(x.title, x.sub, x.note))
})
const rows = computed(() => ({ downloads, visits, installed })[tab.value].value)
const choices = computed(() => (tab.value === 'visits' ? [['all', 'Everyone'], ['landlord', 'Landlords'], ['tenant', 'Tenants'], ['out', 'Not signed in']] : [['all', 'Everyone'], ['landlord', 'Landlords'], ['tenant', 'Tenants']]))
function open(t) {
  tab.value = t
  if (t !== 'visits' && who.value === 'out') who.value = 'all'
}

const HOW = [
  { icon: Globe, title: 'Visit', text: `Someone opens ${HOST} in a browser, on any phone or computer. Coming back after half an hour away is a new visit.` },
  { icon: LogIn, title: 'Signing in on the website', text: 'Still a visit, also on Android. The visit then shows who signed in. iPhone, Windows and Mac are always visits.' },
  { icon: Download, title: 'Download', text: 'An account signs in inside the Android app. One phone is one download, however many accounts use it.' },
  { icon: MonitorSmartphone, title: 'Installed, not signed in', text: 'Android reported that the app was installed, but no account has signed in there. It becomes a download when one does.' },
]
</script>

<template>
  <div class="mx-auto max-w-3xl">
    <SuperHero eyebrow="Growth" title="Downloads & visits" :subtitle="`What really happens on ${HOST} and in the app, the moment it happens.`">
      <span class="live" role="status"><span class="dot" :class="live ? 'on' : 'off'" /> {{ live ? 'Live' : 'Connecting…' }}<template v-if="updatedAt"> · {{ updatedAt.toLocaleTimeString('en-GB') }}</template></span>
      <button type="button" class="btn-secondary" @click="refresh"><RefreshCw class="size-4" /> Refresh</button>
    </SuperHero>

    <p v-if="missing" class="mb-4 flex items-start gap-2 rounded-xl bg-amber-50 p-3 text-sm text-amber-800">
      <TriangleAlert class="mt-0.5 size-4 shrink-0" />
      <span>The numbers aren't set up yet. Run <strong>database/update_existing.sql</strong> in Supabase → SQL Editor, then refresh.</span>
    </p>
    <p v-if="error || detailsError" class="form-error mb-4" role="alert">{{ error || detailsError }}</p>

    <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
      <StatTile label="Website visits" :value="num(site?.visits)" :hint="site ? `${fmt(site.today)} today` : ''" :icon="Globe" tile="tile-violet" />
      <StatTile label="App downloads" :value="num(site?.downloads)" :hint="site ? `${fmt(site.downloadsToday)} today` : ''" :icon="Download" tile="tile-teal" />
      <StatTile label="Signed in on web" :value="num(site?.signedIn)" hint="Visits, last 30 days" :icon="LogIn" tile="tile-sky" />
      <StatTile label="Just arrived" :value="num(site?.now)" hint="Last 5 minutes" :icon="Users" tile="tile-amber" />
    </div>

    <h2 class="section-title mt-6">App downloads</h2>
    <div class="sheet divide-y divide-slate-100">
      <div class="flex items-center gap-3.5 px-4 py-4 sm:px-5">
        <span class="icon-tile tile-teal"><Smartphone class="size-[1.3rem]" /></span>
        <div class="min-w-0 flex-1">
          <p class="font-medium text-slate-900">Renta app on Android</p>
          <p class="text-xs text-slate-500">Phones where an account signed in inside the app</p>
        </div>
        <div class="text-right">
          <p class="text-lg font-bold text-slate-900 tabular-nums">{{ num(site?.downloads) }}</p>
          <p class="text-xs text-slate-500">{{ num(site?.downloadsActive) }} active this month</p>
        </div>
      </div>
      <div v-for="x in [[`Downloaded from ${HOST}`, site?.downloadsWebsite], ['Downloaded from Google Play', site?.downloadsPlay], ['Used by landlords', site?.downloadsLandlords], ['Used by tenants', site?.downloadsTenants], ['Installed, not signed in yet', site?.installedOnly]]" :key="x[0]" class="flex items-center justify-between gap-3 px-4 py-3 text-sm sm:px-5">
        <span class="min-w-0 text-slate-600">{{ x[0] }}</span><span class="shrink-0 font-semibold text-slate-900 tabular-nums">{{ num(x[1]) }}</span>
      </div>
    </div>

    <SignedInAccounts />

    <h2 class="section-title mt-6">Website visits</h2>
    <Panel title="Visits a day" subtitle="The last 14 days">
      <ColumnChart v-if="chart.length" :data="chart" value-label="Visits" :format="fmt" :tick="tick" :height="190" />
      <p v-else class="py-8 text-center text-sm text-slate-500">{{ missing || error ? 'No numbers yet' : 'Loading…' }}</p>
    </Panel>
    <div class="sheet mt-3 divide-y divide-slate-100">
      <div v-for="p in periods" :key="p.label" class="flex items-center gap-3 px-4 py-3.5 sm:px-5">
        <p class="flex-1 font-medium text-slate-900">{{ p.label }}</p>
        <p class="flex items-center gap-1.5 text-sm text-slate-500 tabular-nums"><Users class="size-4" /> {{ plural(p.visitors, 'person', 'people') }}</p>
        <p class="w-24 text-right text-sm text-slate-500"><span class="text-lg font-bold text-slate-900 tabular-nums">{{ num(p.visits) }}</span> visit{{ Number(p.visits) === 1 ? '' : 's' }}</p>
      </div>
    </div>
    <div class="sheet mt-3 divide-y divide-slate-100">
      <p class="px-4 py-3 text-xs font-semibold text-slate-500 sm:px-5">Visits by system · last 30 days</p>
      <div v-for="s in systems" :key="s.key" class="flex items-center gap-3 px-4 py-3 text-sm sm:px-5">
        <component :is="s.icon" class="size-4.5 shrink-0 text-slate-400" />
        <span class="w-28 shrink-0 text-slate-700">{{ s.label }}</span>
        <span class="h-2 flex-1 overflow-hidden rounded-full bg-slate-100"><span class="block h-full rounded-full bg-brand-600" :style="{ width: `${s.share}%` }" /></span>
        <span class="w-20 shrink-0 text-right text-slate-600 tabular-nums">{{ num(s.n) }} · {{ s.share }}%</span>
      </div>
    </div>

    <h2 class="section-title mt-6">The records</h2>
    <div class="grid grid-cols-3 rounded-2xl bg-slate-100 p-1 text-sm">
      <button v-for="t in [['downloads', 'Downloads'], ['visits', 'Visits'], ['installed', 'Not signed in']]" :key="t[0]" type="button" class="h-10 rounded-xl px-1 font-medium transition" :class="tab === t[0] ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500'" @click="open(t[0])">{{ t[1] }}</button>
    </div>
    <input v-model="query" class="input mt-3" :placeholder="tab === 'visits' ? 'Search name, system or device' : 'Search name, phone or device'" />
    <div v-if="tab !== 'installed'" class="-mx-4 mt-3 flex gap-2 overflow-x-auto px-4 pb-1 sm:mx-0 sm:px-0">
      <button v-for="f in choices" :key="f[0]" type="button" class="h-9 shrink-0 rounded-full px-4 text-sm font-medium transition" :class="who === f[0] ? 'bg-slate-900 text-white' : 'bg-slate-100 text-slate-600 hover:bg-slate-200'" @click="who = f[0]">{{ f[1] }}</button>
    </div>
    <div class="sheet mt-3">
      <ul v-if="rows.length" class="divide-y divide-slate-100">
        <li v-for="r in rows" :key="r.id">
          <component :is="r.to ? 'RouterLink' : 'div'" :to="r.to || undefined" class="flex items-center gap-3.5 px-4 py-3.5 transition-colors sm:px-5" :class="r.to && 'hover:bg-slate-50 active:bg-slate-100'">
            <span class="icon-disc" :class="r.tone"><component :is="r.icon" class="size-5" /></span>
            <span class="min-w-0 flex-1">
              <span class="block truncate font-medium text-slate-900">{{ r.title }}</span>
              <span class="mt-0.5 block text-xs text-slate-500">{{ r.sub }}</span>
              <span v-if="r.note" class="mt-0.5 block truncate text-[11px] text-slate-400">{{ r.note }}</span>
            </span>
            <span class="shrink-0 text-right text-[11px] text-slate-500"><span class="block font-medium text-slate-700">{{ moment(r.at) }}</span><span v-if="r.end" class="mt-0.5 block">{{ r.end }}</span></span>
            <ChevronRight v-if="r.to" class="size-4 shrink-0 text-slate-300" />
          </component>
        </li>
      </ul>
      <EmptyState v-else compact kind="activity" :title="!details ? (missing || detailsError ? 'No records yet' : 'Loading…') : query || who !== 'all' ? 'Nothing matches' : 'Nothing recorded yet'" :text="details ? 'It appears here the moment it happens.' : ''" />
    </div>

    <h2 class="section-title mt-6">How each number is obtained</h2>
    <div class="sheet divide-y divide-slate-100">
      <div v-for="h in HOW" :key="h.title" class="flex gap-3.5 px-4 py-3.5 sm:px-5">
        <span class="icon-disc disc-slate"><component :is="h.icon" class="size-5" /></span>
        <div class="min-w-0"><p class="text-sm font-medium text-slate-900">{{ h.title }}</p><p class="mt-0.5 text-xs leading-relaxed text-slate-500">{{ h.text }}</p></div>
      </div>
    </div>
    <p class="mt-4 text-xs leading-relaxed text-slate-500">
      Only {{ HOST }} and the app count: test copies, search robots and your own main admin pages do not. Each visit's record is kept for 90 days; the totals are kept for good. Counting starts from the day this was added.
    </p>
  </div>
</template>

<style scoped>
.live { display: inline-flex; align-items: center; gap: 0.5rem; padding: 0 0.9rem; font-size: 0.8rem; color: #fff; background: rgb(var(--glass) / 0.12); box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.18); font-variant-numeric: tabular-nums; }
.dot { width: 0.55rem; height: 0.55rem; border-radius: 9999px; }
.on { background: #4ade80; box-shadow: 0 0 0 4px rgb(74 222 128 / 0.25); animation: pulse 2s ease-in-out infinite; }
.off { background: #fbbf24; }
@keyframes pulse { 50% { box-shadow: 0 0 0 7px rgb(74 222 128 / 0); } }
@media (prefers-reduced-motion: reduce) { .on { animation: none; } }
</style>
