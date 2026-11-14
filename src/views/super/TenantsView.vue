<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { Search, Trash2, Users, Smartphone, UserCog, TriangleAlert, UserX } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { usePlatformStats } from '@/composables/usePlatformStats'
import { formatUGX, formatDate } from '@/utils/format'
import SuperHero from '@/components/super/SuperHero.vue'
import StatTile from '@/components/super/StatTile.vue'
import ListRow from '@/components/admin/ListRow.vue'
import BaseModal from '@/components/BaseModal.vue'

// Main admin: every tenant on the platform, plus app accounts that aren't renting anything.
const rental = useRentalStore()
const route = useRoute()
const p = usePlatformStats()
const query = ref('')
const landlordFilter = ref('')
const show = ref(route.query.show === 'overdue' ? 'overdue' : 'current') // current | overdue | former | accounts

const owed = (id) => rental.duesForTenant(id).reduce((s, x) => s + x.balance, 0)
const isOverdue = (id) => rental.duesForTenant(id).some((x) => x.status === 'overdue')

const current = computed(() => rental.tenants.filter((t) => t.propertyId))
const rows = computed(() => {
  const base =
    show.value === 'former' ? rental.tenants.filter((t) => !t.propertyId)
    : show.value === 'overdue' ? current.value.filter((t) => isOverdue(t.id))
    : current.value
  const q = query.value.trim().toLowerCase()
  return base
    .filter((t) => !landlordFilter.value || t.landlordId === landlordFilter.value)
    .filter((t) => !q || `${t.name} ${t.email ?? ''} ${t.phone ?? ''} ${p.landlordName(t.landlordId)}`.toLowerCase().includes(q))
    .sort((a, b) => owed(b.id) - owed(a.id) || a.name.localeCompare(b.name))
})
const place = (t) => rental.placeName(t.propertyId ?? t.lastPropertyId)

// ── App accounts not renting anything right now ──
const inactive = ref([])
const inactiveLoading = ref(true)
const inactiveError = ref('')
async function loadInactive() {
  inactiveError.value = ''
  try {
    inactive.value = await rental.loadInactiveTenantAccounts()
  } catch (e) {
    inactiveError.value = e.message
  } finally {
    inactiveLoading.value = false
  }
}
onMounted(loadInactive)
watch(() => rental.tenants, loadInactive)
const deleting = ref(null)
const busy = ref(false)
const error = ref('')
async function removeAccount() {
  busy.value = true
  error.value = ''
  try {
    const a = deleting.value
    await rental.deleteUser(a.id)
    rental.adminNote('account.delete', 'account', null, `Deleted tenant app account ${a.email}`)
    deleting.value = null
    await loadInactive()
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <div>
    <SuperHero eyebrow="People" title="Tenants" :subtitle="`${current.length} renting now across ${rental.landlords.length} landlords`" tone="violet">
      <template #stats>
        <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <StatTile glass label="Renting now" :value="current.length" :hint="`${rental.tenants.length - current.length} former`" :icon="Users" />
          <StatTile glass label="Use the app" :value="current.filter((t) => t.userId).length" hint="Connected accounts" :icon="Smartphone" tile="tile-sky" />
          <StatTile glass label="No smartphone" :value="current.filter((t) => t.managedByLandlord).length" hint="Managed by landlord" :icon="UserCog" tile="tile-violet" />
          <StatTile glass label="Overdue" :value="p.overdueTenants.value" :hint="formatUGX(p.outstanding.value)" :icon="TriangleAlert" tile="tile-amber" :alert="p.overdueTenants.value > 0" />
        </div>
      </template>
    </SuperHero>

    <div class="mb-4 flex flex-col gap-3 lg:flex-row lg:items-center">
      <div class="relative flex-1 lg:max-w-sm">
        <Search class="pointer-events-none absolute top-1/2 left-3.5 size-4 -translate-y-1/2 text-slate-400" />
        <input v-model="query" class="input pl-10" placeholder="Search name, phone, email or landlord" />
      </div>
      <div class="grid grid-cols-4 rounded-2xl bg-slate-100 p-1 text-sm lg:w-[26rem]">
        <button v-for="f in [['current', 'Renting'], ['overdue', 'Overdue'], ['former', 'Former'], ['accounts', 'Accounts']]" :key="f[0]" type="button" class="h-9 rounded-xl font-medium transition" :class="show === f[0] ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500'" @click="show = f[0]">{{ f[1] }}</button>
      </div>
      <select v-if="show !== 'accounts'" v-model="landlordFilter" class="input lg:w-56">
        <option value="">All landlords</option>
        <option v-for="l in rental.landlords" :key="l.id" :value="l.id">{{ l.name }}</option>
      </select>
    </div>

    <!-- Tenants -->
    <div v-if="show !== 'accounts'" class="sheet">
      <ul v-if="rows.length" class="divide-y divide-slate-100">
        <ListRow
          v-for="t in rows"
          :key="t.id"
          :to="`/admin2026/tenants/${t.id}`"
          :title="t.name"
          :subtitle="`${place(t)} · ${p.landlordName(t.landlordId)}`"
          :value="t.propertyId ? (owed(t.id) ? formatUGX(owed(t.id)) : 'Paid up') : `Left ${formatDate(t.endedAt)}`"
          :value-class="!t.propertyId ? 'text-slate-500' : owed(t.id) ? 'text-red-600' : 'text-emerald-700'"
          :value-sub="t.propertyId ? (t.leaseEnd ? `to ${formatDate(t.leaseEnd)}` : 'not paid yet') : ''"
        >
          <template #icon>
            <span class="icon-disc rounded-full" :class="!t.propertyId ? 'disc-slate' : isOverdue(t.id) ? 'disc-red' : t.userId ? 'disc-emerald' : 'disc-sky'">
              <UserCog v-if="t.managedByLandlord" class="size-5" /><Users v-else class="size-5" />
            </span>
          </template>
        </ListRow>
      </ul>
      <p v-else class="px-5 py-12 text-center text-sm text-slate-500">No tenants here.</p>
    </div>

    <!-- App accounts not renting -->
    <div v-else class="sheet">
      <p class="border-b border-slate-100 px-5 py-3.5 text-xs text-slate-500">App accounts not renting right now: never connected, or their tenancy ended.</p>
      <div v-if="inactiveLoading" class="space-y-3 p-5"><div v-for="i in 3" :key="i" class="skeleton h-10 w-full" /></div>
      <p v-else-if="inactiveError" class="px-5 py-6 text-sm text-red-600">{{ inactiveError }}</p>
      <ul v-else-if="inactive.length" class="divide-y divide-slate-100">
        <ListRow v-for="a in inactive" :key="a.id" :title="a.name || a.email" :subtitle="`${a.email} · joined ${formatDate(a.createdAt)} · ${a.formerTenant ? 'former tenant' : 'never connected'}`" :chevron="false" @click="deleting = a">
          <template #icon><span class="icon-disc disc-slate rounded-full"><UserX class="size-5" /></span></template>
          <template #value><span class="inline-flex items-center gap-1 rounded-lg px-2 py-1 text-xs font-semibold text-red-600"><Trash2 class="size-3.5" /> Delete</span></template>
        </ListRow>
      </ul>
      <p v-else class="px-5 py-12 text-center text-sm text-slate-500">No unused accounts.</p>
    </div>

    <BaseModal :model-value="Boolean(deleting)" title="Delete account?" width="max-w-sm" @update:model-value="!$event && (deleting = null)">
      <p class="text-sm text-slate-600">The account <strong>{{ deleting?.email }}</strong> will be deleted and can't sign in any more. This cannot be undone.</p>
      <p v-if="error" class="mt-3 text-sm text-red-600">{{ error }}</p>
      <div class="mt-6 flex justify-end gap-2">
        <button class="btn-secondary" @click="deleting = null">Cancel</button>
        <button :data-busy="Boolean(busy)" class="btn bg-red-600 text-white hover:bg-red-700" :disabled="busy" @click="removeAccount">{{ busy ? 'Deleting…' : 'Delete' }}</button>
      </div>
    </BaseModal>
  </div>
</template>
