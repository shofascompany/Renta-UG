<script setup>
import { computed, reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import {
  ChevronLeft, Mail, Phone, Building2, House, Users, Wallet, TriangleAlert, Pencil, ShieldOff, ShieldCheck, Trash2,
  Megaphone, MoreVertical, KeyRound, ArrowDownLeft, Banknote, Lock, Crown, Clock,
} from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useFilter } from '@/composables/useFilter'
import { useBillingStore, subscriptionStatus, paidWith } from '@/stores/billing'
import CashSubscriptionModal from '@/components/super/CashSubscriptionModal.vue'
import PayStatus from '@/components/PayStatus.vue'
import { useLandlordStats } from '@/composables/useLandlordStats'
import { formatUGX, formatDate } from '@/utils/format'
import SuperHero from '@/components/super/SuperHero.vue'
import StatTile from '@/components/super/StatTile.vue'
import ListRow from '@/components/admin/ListRow.vue'
import DropMenu from '@/components/admin/DropMenu.vue'
import BaseModal from '@/components/BaseModal.vue'
import PropertyEditModal from '@/components/super/PropertyEditModal.vue'
import EmptyState from '@/components/EmptyState.vue'

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
const tab = useFilter('tab', 'properties', ['properties', 'tenants', 'money'])
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
    say(form.resetPassword ? 'Saved. They sign in with their email or phone number and create a new password.' : 'Saved.')
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
// ── Subscription ──
const billing = useBillingStore()
const cashFor = ref(null)
const sub = computed(() =>
  landlord.value
    ? subscriptionStatus(landlord.value.subscriptionUntil, landlord.value.subscriptionPlan, { tier: landlord.value.subscriptionTier, exempt: landlord.value.subscriptionExempt, clock: landlord.value.subscriptionClock })
    : null,
)
const subPayments = computed(() => billing.payments.filter((p) => p.landlordId === props.id).slice(0, 5))
const subPending = computed(() => subPayments.value.find((p) => p.status === 'pending') ?? null)
const tierName = (t) => (t === 'big' ? 'Big scale' : 'Small scale')
const subLine = computed(() => {
  const x = sub.value
  if (!x) return ''
  if (x.state === 'none') return 'Not paid yet: their account is locked until a payment is confirmed.'
  if (!x.active) return `Ended on ${formatDate(x.until)}: their account is locked.`
  return `Active until ${formatDate(x.until)} · ${x.daysLeft} day${x.daysLeft === 1 ? '' : 's'} left`
})
const onCash = (r) => say(`Cash payment recorded. Subscription runs until ${formatDate(r.until)}.`)

const initials = computed(() => (landlord.value?.name ?? '?').split(' ').map((x) => x[0]).slice(0, 2).join('').toUpperCase())
</script>

<template>
  <div v-if="!landlord" class="sheet"><EmptyState kind="missing" title="Landlord not found" text="It may have been removed, or the link is old." to="/admin2026/landlords" action="All landlords" /></div>

  <div v-else>
    <SuperHero :eyebrow="landlord.active ? 'Landlord · active' : 'Landlord · suspended'" :title="landlord.name || landlord.email" :tone="landlord.active ? 'teal' : 'amber'">
      <template #back>
        <RouterLink to="/admin2026/landlords" class="back mb-4 inline-flex h-9 items-center gap-1 rounded-full pr-3.5 pl-2 text-sm font-medium"><ChevronLeft class="size-4" /> Landlords</RouterLink>
      </template>
      <button class="btn-primary" @click="openEdit"><Pencil class="size-4" /> Edit</button>
      <RouterLink :to="`/admin2026/broadcast?landlord=${landlord.id}`" class="btn-secondary"><Megaphone class="size-4" /> Message</RouterLink>
      <DropMenu trigger-class="hero-more" label="More actions" :title="landlord.name || 'Landlord'" width="w-64">
        <template #trigger><MoreVertical class="size-5" /></template>
        <template #default="{ close }">
          <button v-if="!landlord.subscriptionExempt" type="button" class="menu-item" @click="close(); form.resetPassword = true; openEdit(); form.resetPassword = true"><span class="menu-ico"><KeyRound class="size-4" /></span> Reset password</button>
          <p v-if="landlord.subscriptionExempt" class="menu-note">
            Permanent account: it can't be suspended, deleted or have its password reset.
          </p>
          <button v-else type="button" class="menu-item" :class="landlord.active && 'menu-item-danger'" @click="close(); dialog = 'suspend'">
            <span class="menu-ico"><component :is="landlord.active ? ShieldOff : ShieldCheck" class="size-4" /></span> {{ landlord.active ? 'Suspend' : 'Reactivate' }}
          </button>
          <button v-if="!landlord.active && !landlord.subscriptionExempt" type="button" class="menu-item menu-item-danger" @click="close(); dialog = 'delete'"><span class="menu-ico"><Trash2 class="size-4" /></span> Delete permanently</button>
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
          <StatTile glass label="Unpaid" :value="formatUGX(s.outstanding)" :hint="`${s.overdue} tenant${s.overdue === 1 ? '' : 's'} overdue`" :icon="TriangleAlert" tile="tile-amber" :alert="s.overdue > 0" />
        </div>
      </template>
    </SuperHero>

    <!-- The permanent account: told plainly to every main admin -->
    <div v-if="landlord.subscriptionExempt" class="mb-5 flex items-start gap-3.5 rounded-2xl border border-amber-300 bg-amber-50 p-4 sm:p-5">
      <span class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-amber-500 text-[#fff]"><Lock class="size-5" /></span>
      <div class="text-sm text-amber-900">
        <p class="font-semibold">Permanent account · free for life · will never be deleted</p>
        <p class="mt-1 leading-relaxed text-amber-900/85">
          This landlord account is permanently registered. It can't be deleted, suspended or have its password reset, and it never pays a subscription.
          "Delete all users" keeps it with all its properties, tenants, rent and payment records. The database refuses any attempt to remove it or its data.
        </p>
      </div>
    </div>

    <p v-if="flash" class="form-ok mb-5" role="status">{{ flash }}</p>

    <!-- Subscription: status, package, and "paid in cash" -->
    <section v-if="!landlord.subscriptionExempt && sub" class="sub-card sheet mb-5 overflow-hidden">
      <div class="flex flex-wrap items-center gap-4 p-5">
        <span class="sub-ico flex size-12 shrink-0 items-center justify-center rounded-2xl" :class="sub.active ? 'sub-ok' : 'sub-bad'">
          <component :is="sub.active ? Crown : Lock" class="size-5.5" />
        </span>
        <div class="min-w-0 grow basis-48">
          <p class="text-xs font-semibold tracking-[0.14em] text-slate-400 uppercase">Subscription</p>
          <p class="mt-0.5 text-base font-semibold text-slate-900">
            {{ landlord.subscriptionPlan ? `${tierName(landlord.subscriptionTier)} · ${landlord.subscriptionPlan === 'yearly' ? 'Yearly' : 'Monthly'}` : 'No package yet' }}
          </p>
          <p class="mt-0.5 text-sm" :class="sub.active ? 'text-slate-500' : 'text-red-600'">{{ subLine }}</p>
          <p class="mt-1 text-xs text-slate-500">
            {{ s.properties }} house{{ s.properties === 1 ? '' : 's' }}/rooms registered
            <template v-if="landlord.plannedUnits"> · said they will register {{ landlord.plannedUnits }}</template>
            <template v-if="Math.max(s.properties, landlord.plannedUnits ?? 0) > billing.settings.smallMaxUnits"> · needs Big scale</template>
          </p>
        </div>
        <button type="button" class="btn-primary h-11 w-full rounded-xl sm:w-auto" @click="cashFor = landlord"><Banknote class="size-4.5" /> Record cash payment</button>
      </div>
      <p v-if="subPending" class="flex items-center gap-2 border-t border-slate-100 bg-amber-50 px-5 py-3 text-sm text-amber-900">
        <Clock class="size-4 shrink-0 text-amber-600" />
        {{ formatUGX(subPending.amount) }} by mobile money is waiting for you.
        <RouterLink to="/admin2026/subscriptions" class="ml-auto font-semibold text-amber-800 underline">Review</RouterLink>
      </p>
      <ul v-if="subPayments.length" class="divide-y divide-slate-100 border-t border-slate-100 text-sm">
        <li v-for="p in subPayments" :key="p.id" class="flex items-center justify-between gap-3 px-5 py-2.5">
          <span class="min-w-0">
            <span class="block truncate font-medium text-slate-900">{{ tierName(p.tier) }} · <span class="capitalize">{{ p.plan }}</span> · {{ paidWith(p.network) }}</span>
            <span class="block text-xs text-slate-500">{{ formatDate(p.paidOn) }}<template v-if="p.periodEnd"> · covers to {{ formatDate(p.periodEnd) }}</template><template v-if="p.note"> · {{ p.note }}</template></span>
          </span>
          <span class="text-right">
            <span class="block font-semibold text-slate-900 tabular-nums">{{ formatUGX(p.amount) }}</span>
            <span class="text-xs capitalize" :class="p.status === 'confirmed' ? 'text-emerald-700' : p.status === 'pending' ? 'text-amber-700' : 'text-slate-400'">{{ p.status === 'confirmed' ? 'paid' : p.status }}</span>
          </span>
        </li>
      </ul>
    </section>
    <CashSubscriptionModal :landlord="cashFor" @close="cashFor = null" @done="onCash" />

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
          :subtitle="`${rental.placeName(t.propertyId)} · ${t.usesApp ? 'uses the app' : t.managedByLandlord ? 'no smartphone' : 'not connected'}`"
          value="-"
        >
          <template #value>
            <PayStatus :tenant-id="t.id" />
            <p class="mt-1 text-[11px] text-slate-500">{{ rental.payStateFor(t.id)?.detail }}</p>
          </template>
          <template #icon><span class="icon-disc rounded-full" :class="rental.payStateFor(t.id)?.key === 'paid' ? 'disc-emerald' : rental.payStateFor(t.id)?.key === 'part' ? 'disc-amber' : 'disc-red'"><Users class="size-5" /></span></template>
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

      <EmptyState v-else :kind="tab === 'properties' ? 'places' : tab === 'tenants' ? 'people' : 'money'" :title="tab === 'properties' ? 'No properties yet' : tab === 'tenants' ? 'No tenants renting' : 'No payments yet'" />
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
        <label v-if="!landlord.subscriptionExempt" class="flex items-start gap-2.5 rounded-xl border border-slate-200 p-3 text-sm text-slate-700">
          <input v-model="form.resetPassword" type="checkbox" class="size-5 accent-brand-600" />
          <span>Reset password<span class="block text-xs text-slate-500">Their current password stops working; they create a new one at their next sign-in.</span></span>
        </label>
        <p v-if="error" class="form-error" role="alert">{{ error }}</p>
        <div class="flex justify-end gap-2">
          <button type="button" class="btn-secondary" @click="dialog = null">Cancel</button>
          <button :data-busy="Boolean(busy)" type="submit" class="btn-primary" :disabled="busy">{{ busy ? 'Saving…' : 'Save' }}</button>
        </div>
      </form>
    </BaseModal>

    <!-- Suspend / reactivate -->
    <BaseModal :model-value="dialog === 'suspend'" :title="landlord.active ? 'Suspend landlord?' : 'Reactivate landlord?'" width="max-w-sm" @update:model-value="!$event && (dialog = null)">
      <p class="rounded-2xl p-4 text-sm leading-relaxed" :class="landlord.active ? 'bg-amber-50 text-amber-900' : 'bg-emerald-50 text-emerald-800'">
        <template v-if="landlord.active"><strong>{{ landlord.name }}</strong> won't be able to sign in. Their tenants, properties and payments stay as they are.</template>
        <template v-else><strong>{{ landlord.name }}</strong> will be able to sign in again.</template>
      </p>
      <p v-if="error" class="form-error mt-3" role="alert">{{ error }}</p>
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
      <p v-if="error" class="form-error mt-3" role="alert">{{ error }}</p>
      <div class="mt-6 flex justify-end gap-2">
        <button class="btn-secondary" @click="dialog = null">Cancel</button>
        <button :data-busy="Boolean(busy)" class="btn bg-red-600 text-white hover:bg-red-700" :disabled="busy" @click="remove">{{ busy ? 'Deleting…' : 'Delete' }}</button>
      </div>
    </BaseModal>
  </div>
</template>

<style scoped>
.back { --color-white: #fff; color: #fff; background: rgb(var(--glass) / 0.14); box-shadow: inset 0 0 0 1px rgb(var(--glass) / 0.2); }
.hero-avatar { color: #0a3b38; background: #fff; }
.sub-ico { --color-white: #fff; color: #fff; box-shadow: 0 8px 18px -10px rgb(0 0 0 / 0.5); }
.sub-ok { background: linear-gradient(140deg, #fbbf24, #b45309); }
.sub-bad { background: linear-gradient(140deg, #f87171, #b91c1c); }
:deep(.hero-more) {
  display: flex;
  width: 2.75rem;
  height: 2.75rem;
  align-items: center;
  justify-content: center;
  border-radius: 0.95rem;
  cursor: pointer;
  color: #fff;
  background: rgb(var(--glass) / 0.14);
  box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.25);
  transition: background-color 0.15s ease;
}
:deep(.hero-more:hover),
:deep(.hero-more[aria-expanded='true']) { background: rgb(var(--glass) / 0.26); }
</style>
