<script setup>
import { computed, reactive, ref } from 'vue'
import {
  ChevronLeft, Pencil, DoorClosed, Phone, Mail, House, Briefcase, Wallet, CalendarClock, TriangleAlert, ArrowDownLeft, Banknote,
  Bell, Clock, Smartphone, UserCog,
} from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { formatUGX, formatDate, formatPeriod, daysUntil, timeLeft } from '@/utils/format'
import SuperHero from '@/components/super/SuperHero.vue'
import StatTile from '@/components/super/StatTile.vue'
import ListRow from '@/components/admin/ListRow.vue'
import BaseModal from '@/components/BaseModal.vue'
import EndTenancyModal from '@/components/EndTenancyModal.vue'
import EmptyState from '@/components/EmptyState.vue'

// Main admin: one tenant — their stay, money and messages; edit details or end the tenancy.
const props = defineProps({ id: String })
const rental = useRentalStore()

const t = computed(() => rental.tenantById(props.id))
const landlord = computed(() => rental.landlords.find((l) => l.id === t.value?.landlordId))
const charges = computed(() => rental.paymentsForTenant(props.id))
const receipts = computed(() =>
  rental.payment_receipts.filter((r) => r.tenantId === props.id).sort((a, b) => String(b.receivedAt).localeCompare(String(a.receivedAt))),
)
const notes = computed(() => rental.notificationsForTenant(props.id).slice(0, 8))
const owed = computed(() => rental.duesForTenant(props.id).reduce((s, x) => s + x.balance, 0))
const pay = computed(() => rental.payStateFor(props.id)) // Paid / Part paid / Not paid
const paid = computed(() => charges.value.reduce((s, x) => s + x.amountPaid, 0))
const left = computed(() => (t.value?.leaseEnd ? daysUntil(t.value.leaseEnd) : null))
const tab = ref('money') // money | charges | messages
const placeId = computed(() => t.value?.propertyId ?? t.value?.lastPropertyId)

// ── Edit / end ──
const dialog = ref(null)
const form = reactive({ name: '', phone: '', email: '' })
const endOpen = ref(false)
const busy = ref(false)
const error = ref('')
function openEdit() {
  Object.assign(form, { name: t.value.name, phone: t.value.phone ?? '', email: t.value.email && !t.value.email.endsWith('@phone-signin.example.com') ? t.value.email : '' })
  error.value = ''
  dialog.value = 'edit'
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
const saveEdit = () => run(() => rental.adminUpdateTenant(props.id, form))
</script>

<template>
  <div v-if="!t" class="sheet"><EmptyState kind="missing" title="Tenant not found" text="It may have been removed, or the link is old." to="/admin2026/tenants" action="All tenants" /></div>

  <div v-else>
    <SuperHero :eyebrow="t.propertyId ? 'Tenant · renting' : 'Tenant · moved out'" :title="t.name" :tone="t.propertyId ? 'violet' : 'amber'">
      <template #back>
        <RouterLink to="/admin2026/tenants" class="back mb-4 inline-flex h-9 items-center gap-1 rounded-full pr-3.5 pl-2 text-sm font-medium"><ChevronLeft class="size-4" /> Tenants</RouterLink>
      </template>
      <button class="btn-primary" @click="openEdit"><Pencil class="size-4" /> Edit details</button>
      <button v-if="t.propertyId" class="btn-secondary" @click="endOpen = true"><DoorClosed class="size-4" /> End tenancy</button>
      <template #stats>
        <div class="mb-4 flex flex-wrap gap-x-5 gap-y-2 text-sm text-white/80">
          <span v-if="t.phone" class="flex items-center gap-1.5"><Phone class="size-4" /> {{ t.phone }}</span>
          <span v-if="t.email && !t.email.endsWith('@phone-signin.example.com')" class="flex items-center gap-1.5"><Mail class="size-4" /> {{ t.email }}</span>
          <span class="flex items-center gap-1.5"><component :is="t.userId ? Smartphone : UserCog" class="size-4" /> {{ t.userId ? 'Uses the app' : t.managedByLandlord ? 'No smartphone' : 'Not connected' }}</span>
        </div>
        <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <StatTile glass label="Place" :value="rental.placeName(placeId)" :hint="t.propertyId ? 'Renting now' : `Left ${formatDate(t.endedAt)}`" :icon="House" />
          <StatTile glass label="Landlord" :value="landlord?.name ?? '—'" :hint="landlord?.phone ?? landlord?.email" :icon="Briefcase" tile="tile-sky" :to="landlord ? `/admin2026/landlords/${landlord.id}` : null" />
          <StatTile glass label="Rental time" :value="t.leaseEnd ? timeLeft(left) : 'Not started'" :hint="t.leaseEnd ? `Paid to ${formatDate(t.leaseEnd)}` : 'Starts when they pay'" :icon="CalendarClock" tile="tile-violet" />
          <StatTile glass :label="pay?.label ?? 'Rent'" :value="pay?.key === 'paid' ? 'Paid' : formatUGX(pay?.owed ?? owed)" :hint="`${pay?.detail ?? ''} · ${formatUGX(paid)} paid in total`" :icon="pay?.key === 'paid' ? Wallet : TriangleAlert" tile="tile-amber" :alert="pay?.key !== 'paid'" />
        </div>
      </template>
    </SuperHero>

    <div class="mb-4 grid grid-cols-3 rounded-2xl bg-slate-100 p-1 text-sm sm:w-96">
      <button v-for="x in [['money', 'Money in'], ['charges', 'Rent months'], ['messages', 'Messages']]" :key="x[0]" type="button" class="h-10 rounded-xl font-medium transition" :class="tab === x[0] ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500'" @click="tab = x[0]">{{ x[1] }}</button>
    </div>

    <div class="sheet">
      <ul v-if="tab === 'money' && receipts.length" class="divide-y divide-slate-100">
        <ListRow v-for="r in receipts" :key="r.id" :title="/cash/i.test(r.method ?? '') ? 'Cash' : r.method" :subtitle="`${formatDate(r.receivedAt)}${r.reference ? ` · ${r.reference}` : ''}`" :value="formatUGX(r.amount)" value-class="text-emerald-700" :chevron="false">
          <template #icon>
            <span class="icon-disc" :class="/cash/i.test(r.method ?? '') ? 'disc-amber' : 'disc-emerald'"><Banknote v-if="/cash/i.test(r.method ?? '')" class="size-5" /><ArrowDownLeft v-else class="size-5" /></span>
          </template>
        </ListRow>
      </ul>
      <ul v-else-if="tab === 'charges' && charges.length" class="divide-y divide-slate-100">
        <ListRow
          v-for="c in charges"
          :key="c.id"
          :title="`${formatPeriod(c.period)} rent`"
          :subtitle="c.paidAt ? `Paid ${formatDate(c.paidAt)}` : `Due ${formatDate(c.dueDate)}`"
          :value="formatUGX(c.status === 'paid' ? c.amount : c.balance)"
          :value-sub="c.status === 'paid' ? 'paid' : c.status === 'overdue' ? 'overdue' : 'to pay'"
          :value-class="c.status === 'paid' ? 'text-emerald-700' : c.status === 'overdue' ? 'text-red-600' : 'text-amber-700'"
          :chevron="false"
        >
          <template #icon><span class="icon-disc rounded-full" :class="c.status === 'paid' ? 'disc-emerald' : c.status === 'overdue' ? 'disc-red' : 'disc-amber'"><Clock class="size-5" /></span></template>
        </ListRow>
      </ul>
      <ul v-else-if="tab === 'messages' && notes.length" class="divide-y divide-slate-100">
        <li v-for="n in notes" :key="n.id" class="flex gap-3.5 px-4 py-4 sm:px-5">
          <span class="icon-disc disc-brand"><Bell class="size-5" /></span>
          <div class="min-w-0">
            <p class="text-sm font-medium text-slate-900">{{ n.title }}</p>
            <p class="mt-0.5 text-sm text-slate-600">{{ n.body }}</p>
            <p class="mt-1 text-xs text-slate-400">{{ formatDate(n.createdAt) }}{{ n.read ? ' · read' : '' }}</p>
          </div>
        </li>
      </ul>
      <EmptyState v-else :kind="tab === 'messages' ? 'messages' : tab === 'charges' ? 'time' : 'money'" :title="tab === 'messages' ? 'No messages yet' : tab === 'charges' ? 'No rent months yet' : 'No payments yet'" />
    </div>

    <!-- Edit -->
    <BaseModal :model-value="dialog === 'edit'" title="Edit tenant" @update:model-value="!$event && (dialog = null)">
      <form class="space-y-4" @submit.prevent="saveEdit">
        <div>
          <label class="label" for="te-name">Full name</label>
          <input id="te-name" v-model="form.name" class="input" data-cap="words" required />
        </div>
        <div class="grid gap-4 sm:grid-cols-2">
          <div>
            <label class="label" for="te-phone">Phone</label>
            <input id="te-phone" v-model="form.phone" type="tel" class="input" />
          </div>
          <div>
            <label class="label" for="te-email">Email</label>
            <input id="te-email" v-model="form.email" type="email" class="input" data-cap="off" />
          </div>
        </div>
        <p class="text-xs text-slate-500">This changes the tenant record the landlord sees. It doesn't change the tenant's own sign-in details.</p>
        <p v-if="error" class="form-error" role="alert">{{ error }}</p>
        <div class="flex justify-end gap-2">
          <button type="button" class="btn-secondary" @click="dialog = null">Cancel</button>
          <button :data-busy="Boolean(busy)" type="submit" class="btn-primary" :disabled="busy">{{ busy ? 'Saving…' : 'Save' }}</button>
        </div>
      </form>
    </BaseModal>

    <!-- End tenancy -->
    <EndTenancyModal v-model="endOpen" :tenant="t" by="admin" />
  </div>
</template>

<style scoped>
.back { --color-white: #fff; color: #fff; background: rgb(var(--glass) / 0.14); box-shadow: inset 0 0 0 1px rgb(var(--glass) / 0.2); }
</style>
