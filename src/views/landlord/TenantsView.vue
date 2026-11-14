<script setup>
import { computed, onBeforeUnmount, ref } from 'vue'
import {
  Search, UserCog, ChevronRight, KeyRound, Smartphone, ArrowUpDown, UserRoundPlus, ListFilter, EllipsisVertical,
  FileDown, FolderArchive, Check, X, Users, Wallet, AlertCircle, CalendarClock,
} from '@lucide/vue'
import DropMenu from '@/components/admin/DropMenu.vue'
import { useRentalStore } from '@/stores/rental'
import { downloadCSV, timeLeft } from '@/composables/useRentAnalytics'
import { formatUGX, formatDate, daysUntil } from '@/utils/format'
import AdminHeader from '@/components/admin/AdminHeader.vue'
import TenantFormModal from '@/components/TenantFormModal.vue'
import ConnectCodeModal from '@/components/ConnectCodeModal.vue'

// Current tenants as a sortable table. Former tenants live on the Records page.
const rental = useRentalStore()
const query = ref('')
const filter = ref('all') // all | owing | overdue | app | managed | ending
const sort = ref({ key: 'balance', dir: -1 })

const all = computed(() =>
  rental.currentTenants.map((t) => {
    const dues = rental.duesForTenant(t.id)
    return {
      ...t,
      house: rental.placeName(t.propertyId),
      rent: rental.propertyById(t.propertyId)?.rent ?? 0,
      balance: dues.reduce((s, p) => s + p.balance, 0),
      status: dues.some((p) => p.status === 'overdue') ? 'overdue' : dues.length ? 'due' : 'paid',
      leaseDays: t.leaseEnd ? daysUntil(t.leaseEnd) : null,
      account: t.userId ? 'app' : t.managedByLandlord ? 'managed' : 'none',
    }
  }),
)

const rows = computed(() => {
  const q = query.value.trim().toLowerCase()
  const f = filter.value
  const list = all.value.filter((t) => {
    if (f === 'owing' && !t.balance) return false
    if (f === 'overdue' && t.status !== 'overdue') return false
    if (f === 'app' && t.account !== 'app') return false
    if (f === 'managed' && t.account !== 'managed') return false
    if (f === 'ending' && !(t.leaseDays !== null && t.leaseDays >= 0 && t.leaseDays <= 30)) return false
    return !q || `${t.name} ${t.email ?? ''} ${t.phone ?? ''} ${t.house}`.toLowerCase().includes(q)
  })
  const { key, dir } = sort.value
  return list.sort((a, b) => {
    const va = a[key] ?? ''
    const vb = b[key] ?? ''
    return (typeof va === 'number' ? va - vb : String(va).localeCompare(String(vb))) * dir
  })
})
function sortBy(key) {
  sort.value = sort.value.key === key ? { key, dir: -sort.value.dir } : { key, dir: key === 'name' || key === 'house' ? 1 : -1 }
}

const counts = computed(() => ({
  all: all.value.length,
  owing: all.value.filter((t) => t.balance).length,
  overdue: all.value.filter((t) => t.status === 'overdue').length,
  app: all.value.filter((t) => t.account === 'app').length,
  managed: all.value.filter((t) => t.account === 'managed').length,
  ending: all.value.filter((t) => t.leaseDays !== null && t.leaseDays >= 0 && t.leaseDays <= 30).length,
}))
// "Add tenant" words show for 5 s when the page opens, then fold into the icon
const showAddLabel = ref(true)
const addTimer = setTimeout(() => (showAddLabel.value = false), 5000)
onBeforeUnmount(() => clearTimeout(addTimer))

const FILTERS = [
  ['all', 'All tenants', Users],
  ['owing', 'Owing rent', Wallet],
  ['overdue', 'Overdue', AlertCircle],
  ['ending', 'Ending soon', CalendarClock],
  ['app', 'On the app', Smartphone],
  ['managed', 'No smartphone', UserCog],
]
const filterLabel = computed(() => FILTERS.find((f) => f[0] === filter.value)?.[1] ?? 'Filter')

const owedTotal = computed(() => all.value.reduce((s, t) => s + t.balance, 0))

const statusStyle = { paid: 'bg-emerald-50 text-emerald-700', due: 'bg-amber-50 text-amber-700', overdue: 'bg-red-50 text-red-700' }
const statusText = { paid: 'Paid up', due: 'Due', overdue: 'Overdue' }
const initials = (name) => name.split(' ').map((p) => p[0]).slice(0, 2).join('').toUpperCase()

function exportCSV() {
  downloadCSV(`renta-tenants-${new Date().toLocaleDateString('en-CA')}.csv`, [
    { label: 'Name', value: (t) => t.name },
    { label: 'Phone', value: (t) => t.phone ?? '' },
    { label: 'Email', value: (t) => t.email ?? '' },
    { label: 'House', value: (t) => t.house },
    { label: 'Monthly rent (UGX)', value: (t) => t.rent },
    { label: 'Balance (UGX)', value: (t) => t.balance },
    { label: 'Rent status', value: (t) => statusText[t.status] },
    { label: 'Moved in', value: (t) => t.leaseStart ?? '' },
    { label: 'Rental time ends', value: (t) => t.leaseEnd ?? '' },
    { label: 'Account', value: (t) => ({ app: 'Uses the app', managed: 'No smartphone (managed)', none: 'Not connected' })[t.account] },
  ], rows.value)
}

const adding = ref(false)
const codeFor = ref(null)
function onSaved(t) {
  if (!t.userId && !t.managedByLandlord) codeFor.value = t.id
}
</script>

<template>
  <div class="mx-auto max-w-6xl">
    <AdminHeader
      eyebrow="People"
      title="Tenants"
      :subtitle="`${counts.all} current tenants${owedTotal ? ` · ${formatUGX(owedTotal)} owed` : ''}`"
    >
      <template #corner>
        <button type="button" class="add-btn" :class="showAddLabel && 'add-open'" aria-label="Add tenant" @click="adding = true">
          <UserRoundPlus class="size-[1.35rem]" stroke-width="2.25" />
          <span class="add-label">Add tenant</span>
        </button>
      </template>
    </AdminHeader>

    <!-- Toolbar: search · filter menu · more menu -->
    <div class="flex items-center gap-2">
      <div class="relative min-w-0 flex-1">
        <Search class="pointer-events-none absolute top-1/2 left-3.5 size-4 -translate-y-1/2 text-slate-400" />
        <input v-model="query" class="input h-11 rounded-xl bg-white pl-10" placeholder="Search name, phone or house" />
      </div>

      <!-- Filter -->
      <DropMenu
        label="Filter tenants"
        width="w-64"
        trigger-class="tool-btn"
        :class="filter !== 'all' && 'is-on'"
      >
        <template #trigger>
          <ListFilter class="size-[1.15rem]" />
          <span class="hidden sm:inline">{{ filterLabel }}</span>
          <span v-if="filter !== 'all'" class="tool-dot" />
        </template>
        <template #default="{ close }">
          <p class="px-3 pt-2 pb-1.5 text-[11px] font-semibold tracking-wider text-slate-400 uppercase">Show</p>
          <button
            v-for="f in FILTERS"
            :key="f[0]"
            type="button"
            role="menuitemradio"
            :aria-checked="filter === f[0]"
            class="menu-item"
            :class="filter === f[0] && 'menu-item-on'"
            @click="filter = f[0]; close()"
          >
            <component :is="f[2]" class="size-4 shrink-0" />
            <span class="flex-1 text-left">{{ f[1] }}</span>
            <span class="text-xs text-slate-400 tabular-nums">{{ counts[f[0]] }}</span>
            <Check v-if="filter === f[0]" class="size-4 text-brand-600" />
          </button>
        </template>
      </DropMenu>

      <!-- More: download + records -->
      <DropMenu label="More options" width="w-60" trigger-class="tool-btn tool-icon">
        <template #trigger><EllipsisVertical class="size-[1.15rem]" /></template>
        <template #default="{ close }">
          <button type="button" class="menu-item" :disabled="!rows.length" @click="exportCSV(); close()">
            <span class="menu-ico bg-emerald-50 text-emerald-700"><FileDown class="size-4" /></span>
            <span class="flex-1 text-left">
              Download list
              <span class="block text-xs font-normal text-slate-400">Excel / CSV file</span>
            </span>
          </button>
          <RouterLink to="/landlord/records" class="menu-item" @click="close()">
            <span class="menu-ico bg-violet-50 text-violet-700"><FolderArchive class="size-4" /></span>
            <span class="flex-1 text-left">
              Records
              <span class="block text-xs font-normal text-slate-400">Former tenants</span>
            </span>
          </RouterLink>
        </template>
      </DropMenu>
    </div>

    <!-- Active filter chip -->
    <div v-if="filter !== 'all'" class="mt-3 flex">
      <button type="button" class="inline-flex items-center gap-1.5 rounded-full bg-brand-50 py-1.5 pr-2.5 pl-3 text-xs font-semibold text-brand-700" @click="filter = 'all'">
        {{ filterLabel }} · {{ rows.length }} <X class="size-3.5" />
      </button>
    </div>
    <!-- Table (computers) -->
    <div class="mt-4 hidden overflow-hidden rounded-2xl border border-slate-200 bg-white md:block">
      <table v-if="rows.length" class="min-w-full text-sm">
        <thead class="border-b border-slate-200 bg-slate-50/80 text-left text-xs font-semibold tracking-wide text-slate-500 uppercase">
          <tr>
            <th v-for="c in [['name', 'Tenant'], ['house', 'House'], ['leaseDays', 'Time left'], ['balance', 'Balance'], ['status', 'Rent'], ['account', 'Account']]" :key="c[0]" class="px-4 py-3">
              <button class="inline-flex items-center gap-1 uppercase hover:text-slate-800" :class="sort.key === c[0] && 'text-slate-900'" @click="sortBy(c[0])">
                {{ c[1] }} <ArrowUpDown class="size-3" :class="sort.key === c[0] ? 'opacity-100' : 'opacity-30'" />
              </button>
            </th>
            <th class="w-10" />
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100">
          <tr v-for="t in rows" :key="t.id" class="group cursor-pointer transition-colors hover:bg-slate-50" @click="$router.push(`/landlord/tenants/${t.id}`)">
            <td class="px-4 py-3">
              <div class="flex items-center gap-3">
                <span class="icon-disc disc-brand size-9 rounded-full text-xs font-bold">{{ initials(t.name) }}</span>
                <div class="min-w-0">
                  <p class="truncate font-medium text-slate-900">{{ t.name }}</p>
                  <p class="truncate text-xs text-slate-500">{{ t.phone || t.email || '—' }}</p>
                </div>
              </div>
            </td>
            <td class="px-4 py-3 text-slate-700">{{ t.house }}</td>
            <td class="px-4 py-3 whitespace-nowrap text-slate-700">
              {{ formatDate(t.leaseEnd) }}
              <p class="text-xs" :class="t.leaseDays !== null && t.leaseDays <= 30 ? 'font-semibold text-amber-700' : 'text-slate-500'">{{ timeLeft(t.leaseDays) }}</p>
            </td>
            <td class="px-4 py-3 font-semibold whitespace-nowrap tabular-nums" :class="t.balance ? 'text-slate-900' : 'text-slate-400'">{{ formatUGX(t.balance) }}</td>
            <td class="px-4 py-3"><span class="rounded-md px-2 py-0.5 text-xs font-semibold" :class="statusStyle[t.status]">{{ statusText[t.status] }}</span></td>
            <td class="px-4 py-3 text-xs">
              <span v-if="t.account === 'app'" class="inline-flex items-center gap-1 font-medium text-emerald-700"><Smartphone class="size-3.5" /> App</span>
              <span v-else-if="t.account === 'managed'" class="inline-flex items-center gap-1 font-medium text-slate-600"><UserCog class="size-3.5" /> Managed</span>
              <button v-else class="inline-flex items-center gap-1 rounded-md bg-brand-50 px-2 py-1 font-semibold text-brand-700 hover:bg-brand-100" @click.stop="codeFor = t.id"><KeyRound class="size-3" /> Get code</button>
            </td>
            <td class="pr-4"><ChevronRight class="size-4 text-slate-300 group-hover:text-slate-500" /></td>
          </tr>
        </tbody>
      </table>
      <p v-else class="px-5 py-14 text-center text-sm text-slate-500">{{ counts.all ? 'No tenants match.' : 'No tenants yet. Click "Add tenant".' }}</p>
    </div>

    <!-- List (phones) -->
    <div class="mt-4 overflow-hidden rounded-2xl border border-slate-200 bg-white md:hidden">
      <ul v-if="rows.length" class="divide-y divide-slate-100">
        <li v-for="t in rows" :key="t.id">
          <button type="button" class="flex w-full items-center gap-3.5 px-4 py-4 text-left active:bg-slate-50" @click="$router.push(`/landlord/tenants/${t.id}`)">
            <span class="icon-disc disc-solid size-11 rounded-full text-xs font-bold">{{ initials(t.name) }}</span>
            <div class="min-w-0 flex-1">
              <p class="flex items-center gap-1.5 truncate font-medium text-slate-900">
                {{ t.name }}
                <UserCog v-if="t.account === 'managed'" class="size-3.5 shrink-0 text-slate-400" />
                <Smartphone v-else-if="t.account === 'app'" class="size-3.5 shrink-0 text-emerald-600" />
              </p>
              <p class="truncate text-xs text-slate-500">{{ t.house }} · {{ timeLeft(t.leaseDays) }}</p>
            </div>
            <div class="shrink-0 text-right">
              <p class="text-sm font-semibold tabular-nums" :class="t.balance ? 'text-slate-900' : 'text-slate-400'">{{ formatUGX(t.balance) }}</p>
              <span class="mt-0.5 inline-block rounded px-1.5 py-0.5 text-[11px] font-semibold" :class="statusStyle[t.status]">{{ statusText[t.status] }}</span>
            </div>
          </button>
        </li>
      </ul>
      <p v-else class="px-5 py-12 text-center text-sm text-slate-500">{{ counts.all ? 'No tenants match.' : 'No tenants yet.' }}</p>
    </div>

    <TenantFormModal v-model="adding" @saved="onSaved" />
    <ConnectCodeModal v-if="codeFor" :tenant-id="codeFor" :model-value="true" @update:model-value="!$event && (codeFor = null)" />
  </div>
</template>

<style scoped>
/* Add tenant: round icon in the header card; the words show on hover (computers always show them) */
.add-btn {
  --color-white: #fff;
  display: inline-flex;
  height: 3rem;
  min-width: 3rem;
  align-items: center;
  justify-content: center;
  gap: 0;
  border-radius: 1rem;
  padding: 0 0.8rem;
  font-size: 0.9rem;
  font-weight: 600;
  color: #0a3b38;
  background: #fff;
  box-shadow: 0 10px 22px -10px rgb(0 0 0 / 0.45);
  transition: transform 0.15s ease, gap 0.25s ease;
}
.add-btn:active { transform: scale(0.95); }
.add-label {
  max-width: 0;
  overflow: hidden;
  white-space: nowrap;
  opacity: 0;
  transition: max-width 0.3s cubic-bezier(0.22, 1, 0.36, 1), opacity 0.2s ease;
}
.add-btn:hover, .add-btn:focus-visible, .add-open { gap: 0.5rem; }
.add-btn:hover .add-label, .add-btn:focus-visible .add-label, .add-open .add-label { max-width: 8rem; opacity: 1; }
@media (min-width: 1024px) {
  .add-btn { height: 2.75rem; gap: 0.5rem; padding: 0 1.1rem 0 0.95rem; color: #fff; background: var(--color-brand-600); box-shadow: 0 8px 18px -10px rgb(15 118 110 / 0.7); }
  .add-label { max-width: none; opacity: 1; }
}

/* Toolbar buttons (filter / more) */
:deep(.tool-btn) {
  position: relative;
  display: inline-flex;
  height: 2.75rem;
  min-width: 2.75rem;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  border-radius: 0.875rem;
  border: 1px solid var(--color-slate-200);
  background: var(--color-white);
  padding: 0 0.85rem;
  font-size: 0.875rem;
  font-weight: 500;
  color: var(--color-slate-700);
  transition: background-color 0.15s ease, border-color 0.15s ease;
}
:deep(.tool-btn:hover) { background: var(--color-slate-50); }
:deep(.tool-btn[aria-expanded='true']) { border-color: var(--color-brand-200); background: var(--color-brand-50); color: var(--color-brand-700); }
:deep(.tool-icon) { padding: 0; }
.is-on :deep(.tool-btn) { border-color: var(--color-brand-200); color: var(--color-brand-700); }
.tool-dot {
  position: absolute;
  top: 0.45rem;
  right: 0.45rem;
  width: 0.5rem;
  height: 0.5rem;
  border-radius: 9999px;
  background: var(--color-brand-600);
  box-shadow: 0 0 0 2px var(--color-white);
}
@media (min-width: 640px) { .tool-dot { position: static; box-shadow: none; } }

/* Menu rows */
.menu-item {
  display: flex;
  width: 100%;
  align-items: center;
  gap: 0.75rem;
  border-radius: 0.75rem;
  padding: 0.7rem 0.75rem;
  font-size: 0.9rem;
  font-weight: 500;
  color: var(--color-slate-700);
  transition: background-color 0.12s ease;
}
.menu-item:hover { background: var(--color-slate-50); }
.menu-item:disabled { opacity: 0.45; }
.menu-item-on { color: var(--color-brand-700); background: var(--color-brand-50); }
.menu-ico {
  display: flex;
  width: 2.25rem;
  height: 2.25rem;
  flex-shrink: 0;
  align-items: center;
  justify-content: center;
  border-radius: 0.7rem;
}
</style>