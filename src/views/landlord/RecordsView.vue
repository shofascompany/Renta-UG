<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { Search, History, Archive, FileText, MoreVertical } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useFilter } from '@/composables/useFilter'
import { searcher } from '@/lib/search'
import { useLongPress } from '@/composables/useLongPress'
import { formatDate } from '@/utils/format'
import StatusBadge from '@/components/StatusBadge.vue'
import AdminHeader from '@/components/admin/AdminHeader.vue'
import EmptyState from '@/components/EmptyState.vue'
import TenantFormModal from '@/components/TenantFormModal.vue'
import TenantRecordCard from '@/components/TenantRecordCard.vue'
import ConnectCodeModal from '@/components/ConnectCodeModal.vue'

// Everyone who has ever moved out, kept permanently. Status shows "active" if they're renting again.
// Tap a person → their record card (each stay separate). Press and hold / right-click → menu.
const rental = useRentalStore()
const query = useFilter('q', '')

const houseName = (id) => (rental.propertyById(id) ? rental.placeName(id) : 'Removed house')

const rows = computed(() => {
  const hit = searcher(query.value)
  return rental.tenantRecords
    .map((r) => ({
      ...r,
      where: r.current ? `Now at ${houseName(r.current.propertyId)}` : `Last at ${houseName(r.latestEnded.lastPropertyId)}`,
      left: r.latestEnded?.endedAt,
    }))
    .filter((r) => hit(r.name, r.email, r.phone, r.status, r.stays.map((s) => [s.phone, houseName(s.propertyId ?? s.lastPropertyId)])))
})

// ── Record card (looked up live so it updates if data reloads) ──
const cardPerson = ref(null)
const cardRecord = computed(() => rental.tenantRecords.find((r) => r.personId === cardPerson.value) ?? null)

// ── Press-and-hold menu ──
const menu = ref(null) // { x, y, record }
const lp = useLongPress((pos, record) => openMenu(pos, record))

function openMenu(pos, record) {
  const w = 264
  const h = 190
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
  <div class="mx-auto max-w-6xl">
  <AdminHeader
    eyebrow="History"
    title="Records"
    :subtitle="`${rental.tenantRecords.length} people who have rented from you, each stay kept separately`"
  />

  <div>
    <div class="relative">
      <Search class="pointer-events-none absolute top-1/2 left-3.5 size-4 -translate-y-1/2 text-slate-400" />
      <input v-model="query" class="input h-11 rounded-xl pl-10" placeholder="Search name, phone, email or house" />
    </div>
    <p class="mt-2 px-1 text-xs text-slate-400">Tap a person to view their records · press and hold for more options</p>
  </div>

  <section class="sheet mt-4">
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
        <div class="icon-disc rounded-full text-sm font-bold" :class="r.current ? 'disc-brand' : 'disc-slate'">
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
    <div v-if="menu" class="fixed inset-0 z-[79]" @click="closeMenu" @contextmenu.prevent="closeMenu" />
    <Transition name="menu-pop">
      <div v-if="menu" class="menu-panel menu-from-left w-64" :style="{ left: `${menu.x}px`, top: `${menu.y}px` }" role="menu">
        <p class="menu-title truncate">{{ menu.record.name }}</p>
        <div class="menu-scroll">
          <button type="button" class="menu-item" role="menuitem" @click="viewRecords(menu.record)">
            <span class="menu-ico"><FileText class="size-4" /></span>
            <span class="flex-1 text-left">View records<span class="menu-sub">Every stay and payment</span></span>
          </button>
          <button type="button" class="menu-item" role="menuitem" :disabled="Boolean(menu.record.current)" @click="addBack(menu.record)">
            <span class="menu-ico"><History class="size-4" /></span>
            <span class="flex-1 text-left">Register again<span class="menu-sub">{{ menu.record.current ? 'Already renting' : 'New tenant, no old history' }}</span></span>
          </button>
        </div>
      </div>
    </Transition>
  </Teleport>

  <TenantRecordCard :model-value="Boolean(cardRecord)" :record="cardRecord" @update:model-value="!$event && (cardPerson = null)" />

  <TenantFormModal
    :model-value="Boolean(readdId)"
    :prefill-id="readdId"
    @update:model-value="!$event && (readdId = null)"
    @saved="onSaved"
  />

  <ConnectCodeModal v-if="codeFor" :tenant-id="codeFor" :model-value="true" @update:model-value="!$event && (codeFor = null)" />
  </div>
</template>
