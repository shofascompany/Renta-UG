<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { Search, History, Archive, FileText, MoreVertical } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useLongPress } from '@/composables/useLongPress'
import { formatDate } from '@/utils/format'
import PageHeader from '@/components/PageHeader.vue'
import StatusBadge from '@/components/StatusBadge.vue'
import EmptyState from '@/components/EmptyState.vue'
import TenantFormModal from '@/components/TenantFormModal.vue'
import TenantRecordCard from '@/components/TenantRecordCard.vue'
import ConnectCodeModal from '@/components/ConnectCodeModal.vue'

// Everyone who has ever moved out, kept permanently. Status shows "active" if they're renting again.
// Tap a person → their record card (each stay separate). Press and hold / right-click → menu.
const rental = useRentalStore()
const query = ref('')

const houseName = (id) => rental.propertyById(id)?.name ?? 'Removed house'

const rows = computed(() =>
  rental.tenantRecords
    .map((r) => ({
      ...r,
      where: r.current ? `Now at ${houseName(r.current.propertyId)}` : `Last at ${houseName(r.latestEnded.lastPropertyId)}`,
      left: r.latestEnded?.endedAt,
    }))
    .filter((r) => {
      const q = query.value.trim().toLowerCase()
      return !q || `${r.name} ${r.email ?? ''} ${r.stays.map((s) => houseName(s.propertyId ?? s.lastPropertyId)).join(' ')}`.toLowerCase().includes(q)
    }),
)

// ── Record card (looked up live so it updates if data reloads) ──
const cardPerson = ref(null)
const cardRecord = computed(() => rental.tenantRecords.find((r) => r.personId === cardPerson.value) ?? null)

// ── Press-and-hold menu ──
const menu = ref(null) // { x, y, record }
const lp = useLongPress((pos, record) => openMenu(pos, record))

function openMenu(pos, record) {
  const w = 220
  const h = 100
  menu.value = {
    x: Math.min(pos.x, window.innerWidth - w - 8),
    y: Math.min(pos.y, window.innerHeight - h - 8),
    record,
  }
}
function closeMenu() {
  menu.value = null
}
function onKey(e) {
  if (e.key === 'Escape') closeMenu()
}
onMounted(() => {
  window.addEventListener('keydown', onKey)
  window.addEventListener('scroll', closeMenu, true)
})
onBeforeUnmount(() => {
  window.removeEventListener('keydown', onKey)
  window.removeEventListener('scroll', closeMenu, true)
})

function viewRecords(r) {
  closeMenu()
  cardPerson.value = r.personId
}

// ── Add back (creates a new stay) ──
const readdId = ref(null)
const codeFor = ref(null)
function addBack(r) {
  closeMenu()
  if (r.current) return
  readdId.value = r.latestEnded.id
}
function onSaved(t) {
  readdId.value = null
  if (t && !t.userId) codeFor.value = t.id
}
</script>

<template>
  <PageHeader title="Records" subtitle="Everyone who has rented from you, with each stay kept separately." />

  <div class="mb-5 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
    <div class="relative w-full sm:max-w-sm">
      <Search class="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-slate-400" />
      <input v-model="query" class="input pl-9" placeholder="Search name, email or house" />
    </div>
    <p class="text-xs text-slate-400">Tap a tenant to view their records · press and hold for more options</p>
  </div>

  <section class="card overflow-hidden">
    <ul v-if="rows.length" class="divide-y divide-slate-100">
      <li
        v-for="r in rows"
        :key="r.personId"
        class="flex cursor-pointer items-center gap-4 px-5 py-4 transition-colors select-none hover:bg-slate-50 [-webkit-touch-callout:none]"
        :class="menu?.record.personId === r.personId && 'bg-slate-50'"
        role="button"
        tabindex="0"
        @pointerdown="lp.start($event, r)"
        @pointermove="lp.move"
        @pointerup="lp.cancel"
        @pointerleave="lp.cancel"
        @pointercancel="lp.cancel"
        @contextmenu.prevent="openMenu({ x: $event.clientX, y: $event.clientY }, r)"
        @click="lp.consumed() || viewRecords(r)"
        @keydown.enter="viewRecords(r)"
      >
        <div class="flex size-10 shrink-0 items-center justify-center rounded-full bg-slate-50 text-sm font-semibold text-slate-600">
          {{ r.name.split(' ').map((p) => p[0]).slice(0, 2).join('').toUpperCase() }}
        </div>
        <div class="min-w-0 flex-1">
          <div class="flex items-center gap-2">
            <p class="truncate font-medium text-slate-900">{{ r.name }}</p>
            <StatusBadge :status="r.status" />
          </div>
          <p class="truncate text-xs text-slate-500">
            {{ r.email ?? 'no email' }} · {{ r.where }}<template v-if="!r.current && r.left"> · left {{ formatDate(r.left) }}</template>
          </p>
        </div>
        <span class="hidden shrink-0 text-xs text-slate-400 sm:block">{{ r.stays.length }} stay{{ r.stays.length === 1 ? '' : 's' }}</span>
        <!-- Same menu for keyboard / mouse users who don't long-press -->
        <button
          class="btn-ghost -mr-2 shrink-0 px-2"
          aria-label="More options"
          @pointerdown.stop
          @click.stop="openMenu({ x: $event.clientX, y: $event.clientY }, r)"
        >
          <MoreVertical class="size-4" />
        </button>
      </li>
    </ul>
    <EmptyState
      v-else
      :icon="Archive"
      :title="rental.tenantRecords.length ? 'No matches' : 'No records yet'"
      :text="rental.tenantRecords.length ? 'Try a different search.' : 'When you end a tenancy, the tenant and their history appear here.'"
    />
  </section>

  <!-- Dropdown menu -->
  <Teleport to="body">
    <div v-if="menu" class="fixed inset-0 z-40" @click="closeMenu" @contextmenu.prevent="closeMenu" />
    <div
      v-if="menu"
      class="fixed z-50 w-56 overflow-hidden rounded-xl border border-slate-200 bg-white py-1 shadow-xl"
      :style="{ left: `${menu.x}px`, top: `${menu.y}px` }"
      role="menu"
    >
      <p class="truncate border-b border-slate-100 px-3 pt-1.5 pb-2 text-xs font-medium text-slate-500">{{ menu.record.name }}</p>
      <button
        class="flex w-full items-center gap-2.5 px-3 py-2 text-left text-sm text-slate-700 hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-50"
        role="menuitem"
        :disabled="Boolean(menu.record.current)"
        @click="addBack(menu.record)"
      >
        <History class="size-4 text-slate-400" />
        <span>
          Add back to a house
          <span v-if="menu.record.current" class="block text-xs text-slate-400">Already renting</span>
        </span>
      </button>
      <button class="flex w-full items-center gap-2.5 px-3 py-2 text-left text-sm text-slate-700 hover:bg-slate-50" role="menuitem" @click="viewRecords(menu.record)">
        <FileText class="size-4 text-slate-400" /> View records
      </button>
    </div>
  </Teleport>

  <TenantRecordCard :model-value="Boolean(cardRecord)" :record="cardRecord" @update:model-value="!$event && (cardPerson = null)" />

  <TenantFormModal
    :model-value="Boolean(readdId)"
    :prefill-id="readdId"
    @update:model-value="!$event && (readdId = null)"
    @saved="onSaved"
  />

  <ConnectCodeModal v-if="codeFor" :tenant-id="codeFor" :model-value="true" @update:model-value="!$event && (codeFor = null)" />
</template>
