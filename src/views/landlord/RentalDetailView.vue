<script setup>
import { computed, reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ArrowLeft, Plus, Pencil, Trash2, UserPlus, DoorOpen, DoorClosed, Minus, Wallet } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useRentAnalytics } from '@/composables/useRentAnalytics'
import { formatUGX } from '@/utils/format'
import AdminHeader from '@/components/admin/AdminHeader.vue'
import ListRow from '@/components/admin/ListRow.vue'
import BaseModal from '@/components/BaseModal.vue'
import TenantFormModal from '@/components/TenantFormModal.vue'
import ConnectCodeModal from '@/components/ConnectCodeModal.vue'

// One rental business: its rooms as rows. Rename a room, change its rent, put a tenant in it.
const props = defineProps({ id: String })
const rental = useRentalStore()
const router = useRouter()
const a = useRentAnalytics()

const biz = computed(() => rental.rentalById(props.id))
const rooms = computed(() =>
  rental.roomsOf(props.id).map((p) => {
    const t = rental.tenantForProperty(p.id)
    const owed = a.byHouse.value.find((h) => h.id === p.id)?.owed ?? 0
    return { ...p, tenant: t, owed }
  }),
)
const occupied = computed(() => rooms.value.filter((r) => r.tenant).length)
const monthly = computed(() => rooms.value.reduce((s, r) => s + r.rent, 0))
const collected = computed(() => rooms.value.reduce((s, r) => s + (a.byHouse.value.find((h) => h.id === r.id)?.value ?? 0), 0))
const filter = ref('all')
const shown = computed(() =>
  rooms.value.filter((r) => filter.value === 'all' || (filter.value === 'vacant' ? !r.tenant : Boolean(r.tenant))),
)

// ── Edit one room ──
const editing = ref(null)
const roomForm = reactive({ name: '', rent: 0 })
const busy = ref(false)
const error = ref('')
function editRoom(r) {
  editing.value = r.id
  Object.assign(roomForm, { name: r.name, rent: r.rent })
  error.value = ''
}
async function saveRoom() {
  busy.value = true
  error.value = ''
  try {
    await rental.updateProperty(editing.value, { name: roomForm.name.trim(), rent: Math.round(Number(roomForm.rent)) })
    editing.value = null
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}
async function deleteRoom() {
  const r = rooms.value.find((x) => x.id === editing.value)
  if (r?.tenant) return (error.value = 'This room has a tenant. End their tenancy first.')
  if (!confirm(`Delete ${r?.name}? Its rent history is deleted too.`)) return
  try {
    await rental.deleteProperty(editing.value)
    editing.value = null
  } catch (e) {
    error.value = e.message
  }
}

// ── Edit the rental ──
const settingsOpen = ref(false)
const bizForm = reactive({ name: '', location: '', sameRent: null })
function openSettings() {
  Object.assign(bizForm, { name: biz.value.name, location: biz.value.location, sameRent: null })
  error.value = ''
  settingsOpen.value = true
}
async function saveSettings() {
  busy.value = true
  error.value = ''
  try {
    await rental.updateRental(props.id, { name: bizForm.name.trim(), location: bizForm.location.trim() })
    if (bizForm.sameRent !== null && bizForm.sameRent !== '') await rental.setRentalRent(props.id, bizForm.sameRent)
    settingsOpen.value = false
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}
async function removeRental() {
  if (!confirm(`Delete "${biz.value.name}" and all its rooms? This can't be undone.`)) return
  try {
    await rental.deleteRental(props.id)
    router.push('/landlord/properties')
  } catch (e) {
    error.value = e.message
  }
}

// ── Add rooms ──
const adding = ref(false)
const addForm = reactive({ count: 1, prefix: 'Room', rent: null })
function openAdd() {
  const rents = rooms.value.map((r) => r.rent)
  Object.assign(addForm, { count: 1, prefix: 'Room', rent: rents.length ? rents[rents.length - 1] : null })
  error.value = ''
  adding.value = true
}
async function saveAdd() {
  busy.value = true
  error.value = ''
  try {
    const taken = new Set(rooms.value.map((r) => r.name.toLowerCase()))
    const list = []
    for (let n = 1; list.length < addForm.count && n < 1000; n++) {
      const name = `${addForm.prefix.trim() || 'Room'} ${n}`
      if (!taken.has(name.toLowerCase())) list.push({ name, rent: addForm.rent })
    }
    await rental.addRooms(props.id, list)
    adding.value = false
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}

// ── Put a tenant in a room ──
const fillRoom = ref(null)
const codeFor = ref(null)
function onSaved(t) {
  fillRoom.value = null
  if (t && !t.userId && !t.managedByLandlord) codeFor.value = t.id
}
</script>

<template>
  <div class="mx-auto max-w-4xl">
    <RouterLink to="/landlord/properties" class="mb-4 inline-flex items-center gap-1.5 py-1 text-sm font-medium text-slate-500 hover:text-slate-900">
      <ArrowLeft class="size-4" /> My properties
    </RouterLink>

    <div v-if="!biz" class="py-20 text-center text-sm text-slate-500">Rental not found.</div>

    <template v-else>
      <AdminHeader :eyebrow="`${biz.type} · ${biz.location}`" :title="biz.name" :subtitle="`${rooms.length} ${biz.type.toLowerCase()} · ${occupied} occupied · ${formatUGX(monthly)} a month when full`">
        <button class="btn-secondary h-10" @click="openSettings"><Pencil class="size-4" /> Edit</button>
        <button class="btn-primary h-10" @click="openAdd"><Plus class="size-4" /> Add rooms</button>
      </AdminHeader>

      <!-- Collected -->
      <div class="sheet rise flex items-center gap-4 p-5" style="--d: 40ms">
        <span class="icon-tile tile-teal"><Wallet class="size-[1.35rem]" /></span>
        <div class="min-w-0 flex-1">
          <p class="text-xs font-semibold tracking-wider text-slate-500 uppercase">Collected here</p>
          <p class="mt-0.5 text-2xl font-bold text-slate-900 tabular-nums">{{ formatUGX(collected) }}</p>
        </div>
        <p class="shrink-0 text-right text-sm text-slate-500"><span class="block text-lg font-bold text-slate-900">{{ rooms.length - occupied }}</span> vacant</p>
      </div>

      <!-- Rooms -->
      <div class="mt-6 flex items-center justify-between gap-3">
        <h2 class="section-title mb-0">Rooms</h2>
        <div class="flex rounded-lg bg-slate-100 p-0.5 text-xs">
          <button v-for="f in [['all', 'All'], ['occupied', 'Occupied'], ['vacant', 'Vacant']]" :key="f[0]" class="h-8 rounded-md px-3 font-medium" :class="filter === f[0] ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500'" @click="filter = f[0]">{{ f[1] }}</button>
        </div>
      </div>
      <div class="sheet rise mt-3" style="--d: 80ms">
        <ul v-if="shown.length" class="divide-y divide-slate-100">
          <ListRow
            v-for="r in shown"
            :key="r.id"
            :to="`/landlord/properties/${r.id}`"
            :title="r.name"
            :subtitle="r.tenant ? r.tenant.name : 'Vacant'"
            :value="formatUGX(r.rent)"
            :value-sub="r.owed ? `${formatUGX(r.owed)} owed` : 'a month'"
            :chevron="false"
          >
            <template #icon>
              <span class="icon-tile" :class="r.tenant ? 'tile-teal' : 'tile-amber'"><component :is="r.tenant ? DoorClosed : DoorOpen" class="size-[1.35rem]" /></span>
            </template>
            <template #value>
              <div class="flex items-center gap-1">
                <div class="text-right">
                  <p class="text-sm font-semibold text-slate-900 tabular-nums">{{ formatUGX(r.rent) }}</p>
                  <p class="mt-0.5 text-[11px]" :class="r.owed ? 'font-medium text-red-600' : 'text-slate-500'">{{ r.owed ? `${formatUGX(r.owed)} owed` : 'a month' }}</p>
                </div>
                <button v-if="!r.tenant" class="ml-1 flex size-9 items-center justify-center rounded-full bg-brand-50 text-brand-700 hover:bg-brand-100" aria-label="Add a tenant" @click.prevent.stop="fillRoom = r.id"><UserPlus class="size-4" /></button>
                <button class="flex size-9 items-center justify-center rounded-full text-slate-400 hover:bg-slate-100 hover:text-slate-700" aria-label="Rename or change rent" @click.prevent.stop="editRoom(r)"><Pencil class="size-4" /></button>
              </div>
            </template>
          </ListRow>
        </ul>
        <p v-else class="px-5 py-12 text-center text-sm text-slate-500">No rooms here.</p>
      </div>

      <p v-if="error && !editing && !settingsOpen && !adding" class="mt-3 text-sm text-red-600">{{ error }}</p>
      <button class="mt-4 flex w-full items-center justify-center gap-1.5 py-2 text-xs font-medium text-red-600 hover:text-red-700" @click="removeRental">
        <Trash2 class="size-3.5" /> Delete this rental
      </button>

      <!-- Edit room -->
      <BaseModal :model-value="Boolean(editing)" title="Edit room" width="max-w-md" @update:model-value="!$event && (editing = null)">
        <form class="space-y-4" @submit.prevent="saveRoom">
          <div>
            <label class="label" for="room-name">Name</label>
            <input id="room-name" v-model="roomForm.name" class="input" required />
          </div>
          <div>
            <label class="label" for="room-rent">Monthly rent (UGX)</label>
            <input id="room-rent" v-model="roomForm.rent" type="number" min="0" step="1000" class="input" required />
            <p class="mt-1 text-xs text-slate-500">New rent applies from the next rent charge.</p>
          </div>
          <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
          <div class="flex items-center justify-between gap-2 pt-1">
            <button type="button" class="text-sm font-medium text-red-600 hover:text-red-700" @click="deleteRoom">Delete room</button>
            <div class="flex gap-2">
              <button type="button" class="btn-secondary" @click="editing = null">Cancel</button>
              <button :data-busy="Boolean(busy)" type="submit" class="btn-primary" :disabled="busy">{{ busy ? 'Saving…' : 'Save' }}</button>
            </div>
          </div>
        </form>
      </BaseModal>

      <!-- Edit rental -->
      <BaseModal v-model="settingsOpen" title="Edit rental" width="max-w-md">
        <form class="space-y-4" @submit.prevent="saveSettings">
          <div>
            <label class="label" for="biz-name">Business name</label>
            <input id="biz-name" v-model="bizForm.name" class="input" required />
          </div>
          <div>
            <label class="label" for="biz-loc">Location</label>
            <input id="biz-loc" v-model="bizForm.location" class="input" required />
          </div>
          <div>
            <label class="label" for="biz-rent">Same rent for every room (optional)</label>
            <input id="biz-rent" v-model="bizForm.sameRent" type="number" min="0" step="1000" class="input" placeholder="Leave empty to keep each room's rent" />
          </div>
          <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
          <div class="flex justify-end gap-2 pt-1">
            <button type="button" class="btn-secondary" @click="settingsOpen = false">Cancel</button>
            <button :data-busy="Boolean(busy)" type="submit" class="btn-primary" :disabled="busy">{{ busy ? 'Saving…' : 'Save' }}</button>
          </div>
        </form>
      </BaseModal>

      <!-- Add rooms -->
      <BaseModal v-model="adding" title="Add rooms" width="max-w-md">
        <form class="space-y-4" @submit.prevent="saveAdd">
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="label" for="add-count">How many?</label>
              <div class="flex h-11 items-center rounded-xl border border-slate-300 bg-white">
                <button type="button" class="flex h-full w-11 items-center justify-center text-slate-500" aria-label="Fewer" @click="addForm.count = Math.max(1, addForm.count - 1)"><Minus class="size-4" /></button>
                <input id="add-count" v-model.number="addForm.count" type="number" min="1" max="100" class="h-full min-w-0 flex-1 bg-transparent text-center font-semibold outline-none" />
                <button type="button" class="flex h-full w-11 items-center justify-center text-slate-500" aria-label="More" @click="addForm.count = Math.min(100, addForm.count + 1)"><Plus class="size-4" /></button>
              </div>
            </div>
            <div>
              <label class="label" for="add-prefix">Name them</label>
              <input id="add-prefix" v-model="addForm.prefix" class="input" />
            </div>
          </div>
          <div>
            <label class="label" for="add-rent">Monthly rent each (UGX)</label>
            <input id="add-rent" v-model="addForm.rent" type="number" min="0" step="1000" class="input" required />
          </div>
          <p class="text-xs text-slate-500">You can rename any room afterwards.</p>
          <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
          <div class="flex justify-end gap-2 pt-1">
            <button type="button" class="btn-secondary" @click="adding = false">Cancel</button>
            <button :data-busy="Boolean(busy)" type="submit" class="btn-primary" :disabled="busy">{{ busy ? 'Adding…' : `Add ${addForm.count}` }}</button>
          </div>
        </form>
      </BaseModal>

      <TenantFormModal :model-value="Boolean(fillRoom)" :property-id="fillRoom" @update:model-value="!$event && (fillRoom = null)" @saved="onSaved" />
      <ConnectCodeModal v-if="codeFor" :tenant-id="codeFor" :model-value="true" @update:model-value="!$event && (codeFor = null)" />
    </template>
  </div>
</template>
