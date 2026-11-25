<script setup>
import BaseSelect from '@/components/BaseSelect.vue'
import { computed, onMounted, ref, watch } from 'vue'
import { Search, Trash2, Users, Smartphone, UserCog, TriangleAlert, UserX } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useFilter } from '@/composables/useFilter'
import { compare, searcher } from '@/lib/search'
import { usePlatformStats } from '@/composables/usePlatformStats'
import { formatUGX, formatDate } from '@/utils/format'
import SuperHero from '@/components/super/SuperHero.vue'
import StatTile from '@/components/super/StatTile.vue'
import ListRow from '@/components/admin/ListRow.vue'
import PayStatus from '@/components/PayStatus.vue'
import BaseModal from '@/components/BaseModal.vue'
import EmptyState from '@/components/EmptyState.vue'

// Main admin: every tenant on the platform, plus app accounts that aren't renting anything.
const rental = useRentalStore()
const p = usePlatformStats()
const query = useFilter('q', '')
const landlordFilter = useFilter('landlord', '')
const show = useFilter('show', 'current', ['current', 'overdue', 'former', 'accounts'])

const owed = (id) => rental.payStateFor(id)?.owed ?? 0
const isOverdue = (id) => Boolean(rental.payStateFor(id)?.late)

const place = (t) => rental.placeName(t.propertyId ?? t.lastPropertyId)
const current = computed(() => rental.tenants.filter((t) => t.propertyId))
const rows = computed(() => {
  const base =
    show.value === 'former' ? rental.tenants.filter((t) => !t.propertyId)
    : show.value === 'overdue' ? current.value.filter((t) => isOverdue(t.id))
    : current.value
  const hit = searcher(query.value)
  return base
    .filter((t) => !landlordFilter.value || t.landlordId === landlordFilter.value)
    .filter((t) => hit(t.name, t.email, t.phone, place(t), p.landlordName(t.landlordId)))
    .map((t) => ({ t, owed: owed(t.id) }))
    .sort((a, b) => (show.value === 'former' ? compare(a.t.endedAt, b.t.endedAt, -1) : b.owed - a.owed) || compare(a.t.name, b.t.name))
    .map((x) => x.t)
})

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
const shownAccounts = computed(() => {
  const hit = searcher(query.value)
  return inactive.value.filter((x) => hit(x.name, x.email, x.phone, x.formerTenant ? 'former tenant' : 'never connected'))
})
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
          <StatTile glass label="Use the app" :value="current.filter((t) => t.usesApp).length" hint="Connected accounts" :icon="Smartphone" tile="tile-sky" />
          <StatTile glass label="No smartphone" :value="current.filter((t) => t.managedByLandlord).length" hint="Managed by landlord" :icon="UserCog" tile="tile-violet" />
          <StatTile glass label="Overdue" :value="p.overdueTenants.value" :hint="formatUGX(p.outstanding.value)" :icon="TriangleAlert" tile="tile-amber" :alert="p.overdueTenants.value > 0" />
        </div>
      </template>
    </SuperHero>

    <div class="mb-4 flex flex-col gap-3 lg:flex-row lg:items-center">
      <div class="relative flex-1 lg:max-w-sm">
        <Search class="pointer-events-none absolute top-1/2 left-3.5 size-4 -translate-y-1/2 text-slate-400" />
        <input v-model="query" class="input pl-10" placeholder="Search name, phone, place or landlord" />
      </div>
      <div class="grid grid-cols-4 rounded-2xl bg-slate-100 p-1 text-sm lg:w-[26rem]">
        <button v-for="f in [['current', 'Renting'], ['overdue', 'Overdue'], ['former', 'Former'], ['accounts', 'Accounts']]" :key="f[0]" type="button" class="h-9 rounded-xl font-medium transition" :class="show === f[0] ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500'" @click="show = f[0]">{{ f[1] }}</button>
      </div>
      <BaseSelect v-if="show !== 'accounts'" v-model="landlordFilter" class="lg:w-56" :options="[{ value: '', label: 'All landlords' }, ...rental.landlords.map((l) => ({ value: l.id, label: l.name || l.email }))]" />
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
          value="-"
        >
          <template #value>
            <template v-if="t.propertyId">
              <PayStatus :tenant-id="t.id" />
              <p class="mt-1 text-[11px] text-slate-500">{{ rental.payStateFor(t.id)?.detail }}</p>
            </template>
            <p v-else class="text-sm font-semibold text-slate-500">Left {{ formatDate(t.endedAt) }}</p>
          </template>
          <template #icon>
            <span class="icon-disc rounded-full" :class="!t.propertyId ? 'disc-slate' : isOverdue(t.id) ? 'disc-red' : t.usesApp ? 'disc-emerald' : 'disc-sky'">
              <UserCog v-if="t.managedByLandlord" class="size-5" /><Users v-else class="size-5" />
            </span>
          </template>
        </ListRow>
      </ul>
      <EmptyState v-else kind="people" title="No tenants here" text="Try another filter or name." />
    </div>

    <!-- App accounts not renting -->
    <div v-else class="sheet">
      <p class="border-b border-slate-100 px-5 py-3.5 text-xs text-slate-500">App accounts not renting right now: never connected, or their tenancy ended.</p>
      <div v-if="inactiveLoading" class="space-y-3 p-5"><div v-for="i in 3" :key="i" class="skeleton h-10 w-full" /></div>
      <p v-else-if="inactiveError" class="form-error m-5" role="alert">{{ inactiveError }}</p>
      <ul v-else-if="shownAccounts.length" class="divide-y divide-slate-100">
        <ListRow v-for="a in shownAccounts" :key="a.id" :title="a.name || a.email" :subtitle="`${a.email} · joined ${formatDate(a.createdAt)} · ${a.formerTenant ? 'former tenant' : 'never connected'}`" :chevron="false" @click="deleting = a">
          <template #icon><span class="icon-disc disc-slate rounded-full"><UserX class="size-5" /></span></template>
          <template #value><span class="inline-flex items-center gap-1 rounded-lg px-2 py-1 text-xs font-semibold text-red-600"><Trash2 class="size-3.5" /> Delete</span></template>
        </ListRow>
      </ul>
      <EmptyState v-else-if="inactive.length" kind="search" title="No accounts match" text="Try another name or email." />
      <EmptyState v-else kind="done" title="No unused accounts" text="Every tenant account is renting." />
    </div>

    <BaseModal :model-value="Boolean(deleting)" title="Delete account?" width="max-w-sm" @update:model-value="!$event && (deleting = null)">
      <p class="rounded-2xl bg-red-50 p-4 text-sm leading-relaxed text-red-900">The account <strong>{{ deleting?.email }}</strong> will be deleted and can't sign in any more. This cannot be undone.</p>
      <p v-if="error" class="form-error mt-3" role="alert">{{ error }}</p>
      <div class="mt-6 flex justify-end gap-2">
        <button class="btn-secondary" @click="deleting = null">Cancel</button>
        <button :data-busy="Boolean(busy)" class="btn bg-red-600 text-white hover:bg-red-700" :disabled="busy" @click="removeAccount">{{ busy ? 'Deleting…' : 'Delete' }}</button>
      </div>
    </BaseModal>
  </div>
</template>
