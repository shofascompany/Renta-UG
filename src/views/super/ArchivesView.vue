<script setup>
import { computed, ref, watch } from 'vue'
import {
  ChevronLeft, Archive, Briefcase, Users, Building2, Wallet, DoorOpen, Bell, Download, Search, ArrowDownLeft, Banknote,
} from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { formatUGX, formatDate } from '@/utils/format'
import SuperHero from '@/components/super/SuperHero.vue'
import StatTile from '@/components/super/StatTile.vue'
import ListRow from '@/components/admin/ListRow.vue'

// Main admin only: saved copies of everything landlords and tenants entered before "Delete all users".
// /admin2026/archives       → the list
// /admin2026/archives/:id   → one archive, browsable and downloadable
const props = defineProps({ id: { type: String, default: null } })
const rental = useRentalStore()

const list = ref(null)
const listError = ref('')
rental.loadArchives().then((a) => (list.value = a)).catch((e) => {
  listError.value = e.message
  list.value = []
})

const archive = ref(null)
const loading = ref(false)
const error = ref('')
watch(
  () => props.id,
  async (id) => {
    archive.value = null
    if (!id) return
    loading.value = true
    error.value = ''
    try {
      archive.value = await rental.loadArchive(id)
      if (!archive.value) error.value = 'Archive not found.'
    } catch (e) {
      error.value = e.message
    } finally {
      loading.value = false
    }
  },
  { immediate: true },
)

const when = (iso) => new Date(iso).toLocaleString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', hour: 'numeric', minute: '2-digit', hour12: true })
const d = computed(() => archive.value?.data ?? {})
const nameOfLandlord = (id) => d.value.landlords?.find((l) => l.id === id)?.full_name ?? 'Landlord'
const nameOfTenant = (id) => d.value.tenants?.find((t) => t.id === id)?.full_name ?? 'Tenant'
const placeOf = (id) => {
  const p = d.value.properties?.find((x) => x.id === id)
  if (!p) return '—'
  const r = p.rental_id && d.value.rentals?.find((x) => x.id === p.rental_id)
  return r ? `${p.name} · ${r.name}` : p.name
}

const tab = ref('landlords')
const query = ref('')
const TABS = [
  { id: 'landlords', label: 'Landlords', icon: Briefcase },
  { id: 'tenants', label: 'Tenants', icon: Users },
  { id: 'properties', label: 'Places', icon: Building2 },
  { id: 'payments', label: 'Payments', icon: Wallet },
  { id: 'moveouts', label: 'Leaving', icon: DoorOpen },
  { id: 'messages', label: 'Messages', icon: Bell },
]
const rows = computed(() => {
  const x = d.value
  let out = []
  if (tab.value === 'landlords') out = (x.landlords ?? []).map((l) => ({ id: l.id, title: l.full_name || l.email, sub: `${l.email}${l.phone ? ` · ${l.phone}` : ''} · joined ${formatDate(l.created_at)}`, value: l.active ? 'active' : 'suspended' }))
  if (tab.value === 'tenants') out = (x.tenants ?? []).map((t) => ({ id: t.id, title: t.full_name, sub: `${placeOf(t.property_id ?? t.last_property_id)} · ${nameOfLandlord(t.landlord_id)}${t.phone ? ` · ${t.phone}` : ''}`, value: t.property_id ? 'renting' : `left ${formatDate(t.ended_at)}` }))
  if (tab.value === 'properties') out = (x.properties ?? []).map((p) => ({ id: p.id, title: placeOf(p.id), sub: `${nameOfLandlord(p.landlord_id)}${p.location ? ` · ${p.location}` : ''}`, value: formatUGX(p.rent) }))
  if (tab.value === 'payments') out = (x.payment_receipts ?? []).map((r) => ({ id: r.id, cash: /cash/i.test(r.method ?? ''), title: nameOfTenant(r.tenant_id), sub: `${r.method} · ${nameOfLandlord(r.landlord_id)} · ${formatDate(r.received_at)}`, value: formatUGX(r.amount) })).reverse()
  if (tab.value === 'moveouts') out = (x.move_out_requests ?? []).map((m) => ({ id: m.id, title: nameOfTenant(m.tenant_id), sub: `${m.reason}${m.rating ? ` · ${m.rating}/5` : ''}`, value: m.status }))
  if (tab.value === 'messages') out = (x.notifications ?? []).map((n) => ({ id: n.id, title: n.title, sub: `${nameOfTenant(n.tenant_id)} · ${n.body}`, value: formatDate(n.created_at) })).reverse()
  const q = query.value.trim().toLowerCase()
  return q ? out.filter((r) => `${r.title} ${r.sub} ${r.value}`.toLowerCase().includes(q)) : out
})
const shown = ref(50)
watch([tab, query], () => (shown.value = 50))

function download() {
  const blob = new Blob([JSON.stringify(archive.value, null, 2)], { type: 'application/json' })
  const url = URL.createObjectURL(blob)
  const a = Object.assign(document.createElement('a'), { href: url, download: `renta-archive-${String(archive.value.created_at).slice(0, 10)}.json` })
  document.body.appendChild(a)
  a.click()
  a.remove()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}
</script>

<template>
  <!-- One archive -->
  <div v-if="id">
    <SuperHero eyebrow="Archive · only you can see this" :title="archive ? when(archive.created_at) : 'Archive'" :subtitle="archive?.note || 'Everything landlords and tenants had entered at this moment.'" tone="sky">
      <template #back>
        <RouterLink to="/admin2026/archives" class="back mb-4 inline-flex h-9 items-center gap-1 rounded-full pr-3.5 pl-2 text-sm font-medium"><ChevronLeft class="size-4" /> Archives</RouterLink>
      </template>
      <button v-if="archive" class="btn-primary" @click="download"><Download class="size-4" /> Download (JSON)</button>
      <template v-if="archive" #stats>
        <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <StatTile glass label="Landlords" :value="archive.counts?.landlords ?? 0" :hint="`${archive.counts?.tenant_accounts ?? 0} tenant accounts`" :icon="Briefcase" />
          <StatTile glass label="Tenant records" :value="archive.counts?.tenants ?? 0" :hint="`${archive.counts?.move_out_requests ?? 0} requests to leave`" :icon="Users" tile="tile-violet" />
          <StatTile glass label="Places" :value="archive.counts?.properties ?? 0" :hint="`${archive.counts?.rentals ?? 0} rental businesses`" :icon="Building2" tile="tile-sky" />
          <StatTile glass label="Collected" :value="formatUGX(archive.counts?.collected ?? 0)" :hint="`${archive.counts?.payment_receipts ?? 0} payments`" :icon="Wallet" tile="tile-amber" />
        </div>
      </template>
    </SuperHero>

    <div v-if="loading" class="space-y-3"><div v-for="i in 4" :key="i" class="skeleton h-14 w-full rounded-2xl" /></div>
    <p v-else-if="error" class="sheet p-5 text-sm text-red-600">{{ error }}</p>
    <template v-else-if="archive">
      <div class="mb-4 flex gap-2 overflow-x-auto pb-1">
        <button
          v-for="t in TABS"
          :key="t.id"
          type="button"
          class="flex h-10 shrink-0 items-center gap-2 rounded-full px-4 text-sm font-medium transition"
          :class="tab === t.id ? 'tab-on text-white' : 'bg-white text-slate-600 ring-1 ring-slate-200'"
          @click="tab = t.id"
        >
          <component :is="t.icon" class="size-4" /> {{ t.label }}
        </button>
      </div>
      <div class="relative mb-4">
        <Search class="pointer-events-none absolute top-1/2 left-3.5 size-4 -translate-y-1/2 text-slate-400" />
        <input v-model="query" class="input pl-10" placeholder="Search this archive" />
      </div>
      <div class="sheet">
        <ul v-if="rows.length" class="divide-y divide-slate-100">
          <ListRow v-for="r in rows.slice(0, shown)" :key="r.id" :title="r.title" :subtitle="r.sub" :value="r.value" value-class="text-slate-700" :chevron="false">
            <template #icon>
              <span class="icon-disc" :class="tab === 'payments' ? (r.cash ? 'disc-amber' : 'disc-emerald') : 'disc-slate'">
                <template v-if="tab === 'payments'"><Banknote v-if="r.cash" class="size-5" /><ArrowDownLeft v-else class="size-5" /></template>
                <component :is="TABS.find((t) => t.id === tab).icon" v-else class="size-5" />
              </span>
            </template>
          </ListRow>
        </ul>
        <p v-else class="px-5 py-12 text-center text-sm text-slate-500">Nothing here.</p>
        <button v-if="rows.length > shown" type="button" class="w-full border-t border-slate-100 py-3.5 text-sm font-semibold text-brand-700 hover:bg-slate-50" @click="shown += 50">Show more ({{ rows.length - shown }} left)</button>
      </div>
    </template>
  </div>

  <!-- All archives -->
  <div v-else class="mx-auto max-w-3xl">
    <SuperHero eyebrow="History · only you can see this" title="Archives" subtitle="Saved copies of everything, made each time you deleted all users." tone="sky">
      <template #back>
        <RouterLink to="/admin2026/system" class="back mb-4 inline-flex h-9 items-center gap-1 rounded-full pr-3.5 pl-2 text-sm font-medium"><ChevronLeft class="size-4" /> Health & settings</RouterLink>
      </template>
    </SuperHero>
    <p v-if="listError" class="sheet mb-4 p-4 text-sm text-red-600">{{ listError }}</p>
    <div class="sheet">
      <div v-if="list === null" class="space-y-3 p-5"><div v-for="i in 3" :key="i" class="skeleton h-12 w-full" /></div>
      <ul v-else-if="list.length" class="divide-y divide-slate-100">
        <ListRow
          v-for="a in list"
          :key="a.id"
          :to="`/admin2026/archives/${a.id}`"
          :title="when(a.createdAt)"
          :subtitle="`${a.note ? `${a.note} · ` : ''}${a.counts.landlords ?? 0} landlords · ${a.counts.tenants ?? 0} tenants · ${a.counts.properties ?? 0} places`"
          :value="formatUGX(a.counts.collected ?? 0)"
          value-sub="collected"
        >
          <template #icon><span class="icon-tile tile-sky"><Archive class="size-[1.3rem]" /></span></template>
        </ListRow>
      </ul>
      <p v-else class="px-5 py-12 text-center text-sm text-slate-500">No archives yet. One is made automatically when you delete all users.</p>
    </div>
  </div>
</template>

<style scoped>
.back { --color-white: #fff; color: #fff; background: rgb(255 255 255 / 0.14); box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.2); }
.tab-on {
  --color-white: #fff;
  background: linear-gradient(135deg, #0284c7, #0c4a6e);
  box-shadow: 0 8px 18px -10px rgb(2 132 199 / 0.8);
}
</style>
