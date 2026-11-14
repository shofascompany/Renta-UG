<script setup>
import { computed, reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import {
  ChevronLeft, Mail, Phone, Building2, House, Users, Wallet, TriangleAlert, Pencil, ShieldOff, ShieldCheck, Trash2,
  Megaphone, MoreVertical, KeyRound, ArrowDownLeft, Banknote,
} from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useLandlordStats } from '@/composables/useLandlordStats'
import { formatUGX, formatDate } from '@/utils/format'
import SuperHero from '@/components/super/SuperHero.vue'
import StatTile from '@/components/super/StatTile.vue'
import ListRow from '@/components/admin/ListRow.vue'
import DropMenu from '@/components/admin/DropMenu.vue'
import BaseModal from '@/components/BaseModal.vue'
import PropertyEditModal from '@/components/super/PropertyEditModal.vue'

// Main admin: one landlord — their numbers, properties, tenants and money, and every action on them.
const props = defineProps({ id: String })
const rental = useRentalStore()
const router = useRouter()
const { statsFor } = useLandlordStats()

const landlord = computed(() => rental.landlords.find((l) => l.id === props.id))
const s = computed(() => statsFor(props.id))
const properties = computed(() =>
  rental.properties
    .filter((p) => p.landlordId === props.id)
    .sort((a, b) => rental.placeName(a.id).localeCompare(rental.placeName(b.id), undefined, { numeric: true })),
)
const current = computed(() => rental.tenants.filter((t) => t.landlordId === props.id && t.propertyId))
const formerCount = computed(() => rental.tenants.filter((t) => t.landlordId === props.id && !t.propertyId).length)
const receipts = computed(() =>
  rental.payment_receipts
    .filter((r) => r.landlordId === props.id)
    .sort((a, b) => String(b.receivedAt).localeCompare(String(a.receivedAt)))
    .slice(0, 8),
)
const allTime = computed(() => rental.payments.filter((p) => p.landlordId === props.id).reduce((x, p) => x + p.amountPaid, 0))
const owedBy = (tenantId) => rental.duesForTenant(tenantId).reduce((x, p) => x + p.balance, 0)
const tab = ref('properties') // properties | tenants | money
const editingProperty = ref(null)

// ── Actions ──
const flash = ref('')
const error = ref('')
const busy = ref(false)
const dialog = ref(null) // edit | suspend | delete
const form = reactive({ name: '', phone: '', resetPassword: false })
function openEdit() {
  Object.assign(form, { name: landlord.value.name ?? '', phone: landlord.value.phone ?? '', resetPassword: false })
  error.value = ''
  dialog.value = 'edit'
}
function say(msg) {
  flash.value = msg
  setTimeout(() => (flash.value = ''), 5000)
}
async function run(fn) {
  busy.value = true
  error.value = ''
  try {
    await fn()
    dialog.value = null
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}
const saveEdit = () =>
  run(async () => {
    await rental.updateLandlord(props.id, { name: form.name, phone: form.phone, ...(form.resetPassword ? { resetPassword: true } : {}) })
    rental.adminNote('landlord.update', 'landlord', props.id, `Edited landlord ${form.name}${form.resetPassword ? ' and reset their password' : ''}`)
    say(form.resetPassword ? 'Saved. They will create a new password at their next sign-in.' : 'Saved.')
  })
const toggleActive = () =>
  run(async () => {
    const was = landlord.value.active
    await rental.updateLandlord(props.id, { active: !was })
    rental.adminNote(was ? 'landlord.suspend' : 'landlord.reactivate', 'landlord', props.id, `${was ? 'Suspended' : 'Reactivated'} landlord ${landlord.value.name}`)
    say(was ? 'Suspended. They can no longer sign in.' : 'Reactivated. They can sign in again.')
  })
const remove = () =>
  run(async () => {
    const name = landlord.value.name
    await rental.deleteUser(props.id)
    rental.adminNote('landlord.delete', 'landlord', null, `Deleted landlord ${name} and all their data`)
    router.replace('/admin2026/landlords')
  })
const initials = computed(() => (landlord.value?.name ?? '?').split(' ').map((x) => x[0]).slice(0, 2).join('').toUpperCase())
</script>

<template>
  <div v-if="!landlord" class="py-20 text-center text-sm text-slate-500">Landlord not found.</div>

  <div v-else>
    <SuperHero :eyebrow="landlord.active ? 'Landlord · active' : 'Landlord · suspended'" :title="landlord.name || landlord.email" :tone="landlord.active ? 'teal' : 'amber'">
      <template #back>
        <RouterLink to="/admin2026/landlords" class="back mb-4 inline-flex h-9 items-center gap-1 rounded-full pr-3.5 pl-2 text-sm font-medium"><ChevronLeft class="size-4" /> Landlords</RouterLink>
      </template>
      <button class="btn-primary" @click="openEdit"><Pencil class="size-4" /> Edit</button>
      <RouterLink :to="`/admin2026/broadcast?landlord=${landlord.id}`" class="btn-secondary"><Megaphone class="size-4" /> Message</RouterLink>
      <DropMenu trigger-class="btn-secondary h-11 w-11 rounded-[0.95rem] p-0 text-white" label="More actions" width="w-60">
        <template #trigger><MoreVertical class="size-5" /></template>
        <template #default="{ close }">
          <button type="button" class="menu-item" @click="close(); form.resetPassword = true; openEdit(); form.resetPassword = true"><KeyRound class="size-4 text-slate-500" /> Reset password</button>
          <button type="button" class="menu-item" :class="landlord.active && 'text-red-600'" @click="close(); dialog = 'suspend'">
            <component :is="landlord.active ? ShieldOff : ShieldCheck" class="size-4" /> {{ landlord.active ? 'Suspend' : 'Reactivate' }}
          </button>
          <button v-if="!landlord.active" type="button" class="menu-item text-red-600" @click="close(); dialog = 'delete'"><Trash2 class="size-4" /> Delete permanently</button>
        </template>
      </DropMenu>
      <template #stats>
        <div class="mb-4 flex flex-wrap items-center gap-x-5 gap-y-2 text-sm text-white/80">
          <span class="flex items-center gap-3"><span class="hero-avatar flex size-9 items-center justify-center rounded-xl text-xs font-bold">{{ initials }}</span></span>
          <a :href="`mailto:${landlord.email}`" class="flex items-center gap-1.5 hover:text-white"><Mail class="size-4" /> {{ landlord.email }}</a>
          <a v-if="landlord.phone" :href="`tel:${landlord.phone}`" class="flex items-center gap-1.5 hover:text-white"><Phone class="size-4" /> {{ landlord.phone }}</a>
          <span>Joined {{ formatDate(landlord.createdAt) }}</span>
        </div>
        <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <StatTile glass label="Properties" :value="s.properties" :hint="`${s.occupied} occupied`" :icon="Building2" />
          <StatTile glass label="Tenants" :value="s.tenants" :hint="`${s.connected} use the app`" :icon="Users" tile="tile-violet" />
          <StatTile glass label="Collected" :value="formatUGX(allTime)" :hint="`${formatUGX(s.collected)} this month`" :icon="Wallet" tile="tile-sky" />
          <StatTile glass label="Unpaid" :value="formatUGX(s.outstanding)" :hint="`${s.overdue} overdue charge${s.overdue === 1 ? '' : 's'}`" :icon="TriangleAlert" tile="tile-amber" :alert="s.overdue > 0" />
        </div>
      </template>
    </SuperHero>

    <p v-if="flash" class="sheet mb-5 p-4 text-sm text-emerald-700">{{ flash }}</p>

    <div class="mb-4 grid grid-cols-3 rounded-2xl bg-slate-100 p-1 text-sm sm:w-96">
      <button v-for="t in [['properties', 'Properties'], ['tenants', 'Tenants'], ['money', 'Money in']]" :key="t[0]" type="button" class="h-10 rounded-xl font-medium transition" :class="tab === t[0] ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500'" @click="tab = t[0]">{{ t[1] }}</button>
    </div>

    <div class="sheet">
      <!-- Properties: tap to edit -->
      <ul v-if="tab === 'properties' && properties.length" class="divide-y divide-slate-100">
        <ListRow
          v-for="p in properties"
          :key="p.id"
          :title="rental.placeName(p.id)"
          :subtitle="rental.tenantForProperty(p.id) ? `Rented by ${rental.tenantForProperty(p.id).name}` : 'Vacant'"
          :value="formatUGX(p.rent)"
          value-sub="per month · edit"
          @click="editingProperty = p.id"
        >
          <template #icon>
            <span class="icon-tile" :class="rental.tenantForProperty(p.id) ? (p.rentalId ? 'tile-teal' : 'tile-sky') : 'tile-slate'">
              <Building2 v-if="p.rentalId" class="size-[1.3rem]" /><House v-else class="size-[1.3rem]" />
            </span>
          </template>
        </ListRow>
      </ul>

      <ul v-else-if="tab === 'tenants' && current.length" class="divide-y divide-slate-100">
        <ListRow
          v-for="t in current"
          :key="t.id"
          :to="`/admin2026/tenants/${t.id}`"
          :title="t.name"
          :subtitle="`${rental.placeName(t.propertyId)} · ${t.userId ? 'uses the app' : t.managedByLandlord ? 'no smartphone' : 'not connected'}`"
          :value="owedBy(t.id) ? formatUGX(owedBy(t.id)) : 'Paid up'"
          :value-class="owedBy(t.id) ? 'text-red-600' : 'text-emerald-700'"
          :value-sub="t.leaseEnd ? `to ${formatDate(t.leaseEnd)}` : 'not paid yet'"
        >
          <template #icon><span class="icon-disc rounded-full" :class="owedBy(t.id) ? 'disc-red' : 'disc-emerald'"><Users class="size-5" /></span></template>
        </ListRow>
      </ul>

      <ul v-else-if="tab === 'money' && receipts.length" class="divide-y divide-slate-100">
        <ListRow
          v-for="r in receipts"
          :key="r.id"
          :to="`/admin2026/tenants/${r.tenantId}`"
          :title="rental.tenantById(r.tenantId)?.name ?? 'Tenant'"
          :subtitle="`${/cash/i.test(r.method ?? '') ? 'Cash' : r.method} · ${formatDate(r.receivedAt)}`"
          :value="formatUGX(r.amount)"
          value-class="text-emerald-700"
        >
          <template #icon>
            <span class="icon-disc" :class="/cash/i.test(r.method ?? '') ? 'disc-amber' : 'disc-emerald'">
              <Banknote v-if="/cash/i.test(r.method ?? '')" class="size-5" /><ArrowDownLeft v-else class="size-5" />
            </span>
          </template>
        </ListRow>
      </ul>

      <p v-else class="px-5 py-12 text-center text-sm text-slate-500">
        {{ tab === 'properties' ? 'No properties yet.' : tab === 'tenants' ? 'No tenants renting right now.' : 'No payments yet.' }}
      </p>
    </div>
    <p v-if="tab === 'tenants' && formerCount" class="mt-3 px-1 text-xs text-slate-400">{{ formerCount }} former tenant record{{ formerCount === 1 ? '' : 's' }} kept in their Records.</p>

    <PropertyEditModal :property-id="editingProperty" @close="editingProperty = null" />

    <!-- Edit -->
    <BaseModal :model-value="dialog === 'edit'" title="Edit landlord" @update:model-value="!$event && (dialog = null)">
      <form class="space-y-4" @submit.prevent="saveEdit">
        <div>
          <label class="label" for="le-name">Full name</label>
          <input id="le-name" v-model="form.name" class="input" data-cap="words" required />
        </div>
        <div>
          <label class="label" for="le-phone">Phone</label>
          <input id="le-phone" v-model="form.phone" type="tel" class="input" placeholder="0772 123456" />
        </div>
        <p class="text-xs text-slate-500">Email (login): {{ landlord.email }}</p>
        <label class="flex items-start gap-2.5 rounded-xl border border-slate-200 p-3 text-sm text-slate-700">
          <input v-model="form.resetPassword" type="checkbox" class="mt-0.5 size-4 accent-brand-600" />
          <span>Reset password<span class="block text-xs text-slate-500">Their current password stops working; they create a new one at their next sign-in.</span></span>
        </label>
        <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
        <div class="flex justify-end gap-2">
          <button type="button" class="btn-secondary" @click="dialog = null">Cancel</button>
          <button :data-busy="Boolean(busy)" type="submit" class="btn-primary" :disabled="busy">{{ busy ? 'Saving…' : 'Save' }}</button>
        </div>
      </form>
    </BaseModal>

    <!-- Suspend / reactivate -->
    <BaseModal :model-value="dialog === 'suspend'" :title="landlord.active ? 'Suspend landlord?' : 'Reactivate landlord?'" width="max-w-sm" @update:model-value="!$event && (dialog = null)">
      <p class="text-sm text-slate-600">
        <template v-if="landlord.active"><strong>{{ landlord.name }}</strong> won't be able to sign in. Their tenants, properties and payments stay as they are.</template>
        <template v-else><strong>{{ landlord.name }}</strong> will be able to sign in again.</template>
      </p>
      <p v-if="error" class="mt-3 text-sm text-red-600">{{ error }}</p>
      <div class="mt-6 flex justify-end gap-2">
        <button class="btn-secondary" @click="dialog = null">Cancel</button>
        <button :data-busy="Boolean(busy)" class="btn" :class="landlord.active ? 'bg-red-600 text-white hover:bg-red-700' : 'btn-primary'" :disabled="busy" @click="toggleActive">
          {{ busy ? 'Please wait…' : landlord.active ? 'Suspend' : 'Reactivate' }}
        </button>
      </div>
    </BaseModal>

    <!-- Delete -->
    <BaseModal :model-value="dialog === 'delete'" title="Delete permanently?" width="max-w-sm" @update:model-value="!$event && (dialog = null)">
      <div class="flex items-start gap-3 rounded-2xl bg-red-50 p-4 text-sm text-red-900">
        <TriangleAlert class="mt-0.5 size-5 shrink-0 text-red-600" />
        <p>This deletes <strong>{{ landlord.name }}</strong> and their {{ s.properties }} properties, tenant records, payments and messages. It cannot be undone.</p>
      </div>
      <p v-if="error" class="mt-3 text-sm text-red-600">{{ error }}</p>
      <div class="mt-6 flex justify-end gap-2">
        <button class="btn-secondary" @click="dialog = null">Cancel</button>
        <button :data-busy="Boolean(busy)" class="btn bg-red-600 text-white hover:bg-red-700" :disabled="busy" @click="remove">{{ busy ? 'Deleting…' : 'Delete' }}</button>
      </div>
    </BaseModal>
  </div>
</template>

<style scoped>
.back { --color-white: #fff; color: #fff; background: rgb(255 255 255 / 0.14); box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.2); }
.hero-avatar { color: #0a3b38; background: #fff; }
.menu-item {
  display: flex;
  width: 100%;
  align-items: center;
  gap: 0.6rem;
  border-radius: 0.75rem;
  padding: 0.65rem 0.75rem;
  text-align: left;
  font-size: 0.875rem;
  font-weight: 500;
  color: var(--color-slate-700);
}
.menu-item:hover { background: var(--color-slate-50); }
</style>
