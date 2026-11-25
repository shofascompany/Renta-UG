<script setup>
import { computed, ref } from 'vue'
import { useRouter } from 'vue-router'
import ConnectCodeModal from '@/components/ConnectCodeModal.vue'
import RecordPaymentModal from '@/components/RecordPaymentModal.vue'
import PayStatus from '@/components/PayStatus.vue'
import {
  ArrowLeft, Phone, Mail, UserX, Smartphone, CheckCircle2, KeyRound, Banknote,
  LogOut, Trash2, UserCog, ArrowDownLeft, Clock, AlertCircle, Pencil, ChevronRight, UserRoundPlus,
} from '@lucide/vue'
import BaseModal from '@/components/BaseModal.vue'
import AppInvite from '@/components/AppInvite.vue'
import EndTenancyModal from '@/components/EndTenancyModal.vue'
import TenantFormModal from '@/components/TenantFormModal.vue'
import AdminHeader from '@/components/admin/AdminHeader.vue'
import HeaderAction from '@/components/admin/HeaderAction.vue'
import { useRentalStore } from '@/stores/rental'
import { formatUGX, formatDate, formatPeriod, timeLeft } from '@/utils/format'
import { rentDaysLeft } from '@/lib/now'
import EmptyState from '@/components/EmptyState.vue'
import { askConfirm } from '@/composables/useConfirm'


const props = defineProps({ id: String })
const rental = useRentalStore()
const router = useRouter()
const showCode = ref(false)
const showCash = ref(false)

// Tenant without a smartphone: the landlord manages them
const switching = ref(false)
const switchError = ref('')
async function toggleManaged() {
  switching.value = true
  switchError.value = ''
  try {
    await rental.setManagedByLandlord(tenant.value.id, true)
  } catch (e) {
    switchError.value = e.message
  } finally {
    switching.value = false
  }
}

// They got a smartphone: create their login (phone sign-in, no connection code)
const accessOpen = ref(false)
const accessBusy = ref(false)
const accessError = ref('')
const accessGiven = ref('')
async function giveAccess() {
  accessBusy.value = true
  accessError.value = ''
  try {
    const res = await rental.giveAppAccess(tenant.value.id)
    accessGiven.value = res.phone
    accessOpen.value = false
  } catch (e) {
    accessError.value = e.message
  } finally {
    accessBusy.value = false
  }
}

const endOpen = ref(false)
const payAmount = ref(0)
function recordPay(amount = 0) {
  payAmount.value = amount
  showCash.value = true
}

async function removeProperty() {
  const back = parent.value ? `/landlord/rentals/${parent.value.id}` : '/landlord/properties'
  const ok = await askConfirm({
    title: `Delete ${property.value.name}?`,
    text: "It is removed from your properties. This can't be undone.",
    confirm: parent.value ? 'Delete room' : 'Delete house',
    cancel: 'Keep it',
    working: 'Deleting…',
    icon: Trash2,
    action: () => rental.deleteProperty(props.id),
  })
  if (ok) router.push(back)
}

const property = computed(() => rental.propertyById(props.id))
const parent = computed(() => property.value?.rentalId && rental.rentalById(property.value.rentalId))

// Rename / change rent (house or room)
const editOpen = ref(false)
const editBusy = ref(false)
const editError = ref('')
const edit = ref({ name: '', rent: 0, location: '' })
function openEdit() {
  edit.value = { name: property.value.name, rent: property.value.rent, location: property.value.location }
  editError.value = ''
  editOpen.value = true
}
async function saveEdit() {
  editBusy.value = true
  editError.value = ''
  try {
    const changes = { name: edit.value.name.trim(), rent: Math.round(Number(edit.value.rent)) }
    if (!parent.value) changes.location = edit.value.location.trim()
    await rental.updateProperty(props.id, changes)
    editOpen.value = false
  } catch (e) {
    editError.value = e.message
  } finally {
    editBusy.value = false
  }
}
const tenant = computed(() => rental.tenantForProperty(props.id))
const payments = computed(() => rental.payments.filter((p) => p.propertyId === props.id).sort((a, b) => b.period.localeCompare(a.period)))
const balance = computed(() => payments.value.reduce((s, p) => s + p.balance, 0))
const collected = computed(() => payments.value.reduce((s, p) => s + p.amountPaid, 0))
const initials = (name) => (name ?? '?').split(' ').map((p) => p[0]).slice(0, 2).join('').toUpperCase()

// ── Add a tenant to this house ──
const pickOpen = ref(false)
const formOpen = ref(false)
const pickError = ref('')
const movingIn = ref('')
// People who rented from you before and aren't renting anywhere now
const returning = computed(() => rental.tenantRecords.filter((r) => r.status === 'former'))
function openPick() {
  pickError.value = ''
  pickOpen.value = true
}
function newTenant() {
  pickOpen.value = false
  formOpen.value = true
}
async function moveIn(r) {
  movingIn.value = r.personId
  pickError.value = ''
  try {
    const email = r.email && !r.email.endsWith('@phone-signin.example.com') ? r.email : ''
    await rental.readdTenant(r.latestEnded.id, { name: r.name, email, phone: r.phone ?? '', propertyId: props.id })
    pickOpen.value = false
  } catch (e) {
    pickError.value = e.message
  } finally {
    movingIn.value = ''
  }
}
function onTenantSaved(t) {
  if (!t.managedByLandlord) showCode.value = true // has a smartphone: give them the connection code now
}
</script>

<template>
  <div class="mx-auto max-w-6xl">
    <RouterLink :to="parent ? `/landlord/rentals/${parent.id}` : '/landlord/properties'" class="mb-4 inline-flex items-center gap-1.5 rounded-lg py-1 text-sm font-medium text-slate-500 hover:text-slate-900">
      <ArrowLeft class="size-4" /> {{ parent ? parent.name : 'My properties' }}
    </RouterLink>

    <div v-if="!property" class="sheet"><EmptyState kind="missing" title="House not found" text="It may have been removed, or the link is old." to="/landlord/properties" action="My properties" /></div>

    <template v-else>
      <!-- House -->
      <AdminHeader
        :eyebrow="`${parent ? parent.name : property.type} · ${tenant ? 'Occupied' : 'Vacant'}`"
        :title="property.name"
        :subtitle="parent ? `${property.location} · ${formatUGX(property.rent)} a month` : `${property.location} · ${formatUGX(property.rent)} a month · ${property.bedrooms} bed, ${property.bathrooms} bath`"
      >
        <template #corner>
          <HeaderAction :icon="Pencil" :label="parent ? 'Edit room' : 'Edit house'" intro @click="openEdit" />
        </template>
      </AdminHeader>

      <div class="mt-6 grid gap-6 lg:grid-cols-5">
        <!-- Tenant -->
        <section class="rise lg:col-span-2" style="--d: 60ms">
          <h2 class="section-title">Tenant</h2>

          <div v-if="tenant" class="sheet">
            <div class="tile-glow flex items-center gap-3.5 px-5 py-5">
              <span class="icon-disc disc-solid size-12 rounded-2xl text-sm font-bold">{{ initials(tenant.name) }}</span>
              <div class="min-w-0 flex-1">
                <p class="truncate text-lg font-semibold text-slate-900">{{ tenant.name }}</p>
                <p v-if="tenant.usesApp" class="flex items-center gap-1 text-xs font-medium text-emerald-700"><Smartphone class="size-3.5" /> Uses the app</p>
                <p v-else-if="tenant.managedByLandlord" class="flex items-center gap-1 text-xs font-medium text-slate-600"><UserCog class="size-3.5" /> Managed by you · {{ tenant.userId ? 'invited, not registered yet' : 'no smartphone' }}</p>
                <p v-else class="text-xs text-slate-500">Not connected yet</p>
              </div>
            </div>

            <dl class="divide-y divide-slate-100 border-t border-slate-100 text-sm">
              <div v-if="tenant.phone" class="flex items-center justify-between gap-3 px-5 py-3">
                <dt class="text-slate-500">Phone</dt>
                <dd><a :href="`tel:${tenant.phone}`" class="flex items-center gap-1.5 font-medium text-slate-900 hover:text-brand-700"><Phone class="size-3.5" /> {{ tenant.phone }}</a></dd>
              </div>
              <div v-if="tenant.email" class="flex items-center justify-between gap-3 px-5 py-3">
                <dt class="text-slate-500">Email</dt>
                <dd class="min-w-0"><a :href="`mailto:${tenant.email}`" class="flex items-center gap-1.5 truncate font-medium text-slate-900 hover:text-brand-700"><Mail class="size-3.5 shrink-0" /> <span class="truncate">{{ tenant.email }}</span></a></dd>
              </div>
              <div class="flex justify-between gap-3 px-5 py-3"><dt class="text-slate-500">Rental time</dt><dd class="text-right"><p class="font-medium text-slate-900">{{ timeLeft(rentDaysLeft(tenant)) }}</p><p v-if="tenant.leaseEnd" class="text-xs text-slate-500">{{ formatDate(tenant.leaseStart) }} – {{ formatDate(tenant.leaseEnd) }}</p></dd></div>
              <div class="flex justify-between gap-3 px-5 py-3"><dt class="text-slate-500">Rent</dt><dd class="text-right"><PayStatus :tenant-id="tenant.id" /><p class="mt-0.5 text-xs text-slate-500">{{ rental.payStateFor(tenant.id)?.detail }}</p></dd></div>
              <div class="flex justify-between gap-3 px-5 py-3"><dt class="text-slate-500">To pay</dt><dd class="font-semibold" :class="rental.payStateFor(tenant.id)?.owed ? 'text-red-600' : 'text-emerald-700'">{{ formatUGX(rental.payStateFor(tenant.id)?.owed ?? balance) }}</dd></div>
            </dl>

            <div class="space-y-2 border-t border-slate-100 p-4">
              <template v-if="!tenant.userId">
                <button v-if="tenant.managedByLandlord" class="btn-primary h-11 w-full" @click="accessOpen = true">
                  <Smartphone class="size-4" /> Give app access
                </button>
                <template v-else>
                  <button class="btn-primary h-11 w-full" @click="showCode = true"><KeyRound class="size-4" /> Get connection code</button>
                  <button class="w-full py-1 text-xs font-medium text-brand-700 hover:text-brand-600 disabled:opacity-50" :disabled="switching" @click="toggleManaged">
                    No smartphone? Manage this tenant yourself
                  </button>
                </template>
                <p v-if="switchError" class="field-error">{{ switchError }}</p>
              </template>
              <RouterLink v-if="tenant.managedByLandlord" :to="`/landlord/managed/${tenant.id}`" class="flex items-center gap-3 rounded-xl bg-slate-50 px-4 py-3 text-sm font-medium text-slate-700 hover:bg-slate-100">
                <UserCog class="size-4 text-slate-500" /> <span class="flex-1">Open their account page</span> <ChevronRight class="size-4 text-slate-400" />
              </RouterLink>
              <AppInvite v-if="tenant.userId" :tenant-id="tenant.id" />
              <p v-if="accessGiven && !tenant.usesApp" class="flex items-start gap-2 rounded-xl border border-emerald-200 bg-emerald-50 p-3 text-xs text-emerald-800">
                <CheckCircle2 class="mt-0.5 size-4 shrink-0" />
                <span>App access given. {{ tenant.name.split(' ')[0] }} can now sign in with <strong>{{ accessGiven }}</strong>. No code needed.</span>
              </p>
              <div class="grid grid-cols-2 gap-2">
                <button class="btn-secondary h-11" @click="recordPay(0)"><Banknote class="size-4" /> Record payment</button>
                <button class="btn-secondary h-11" @click="endOpen = true"><LogOut class="size-4" /> End tenancy</button>
              </div>
            </div>
          </div>

          <div v-else class="sheet flex flex-col items-center px-6 py-10 text-center">
            <span class="icon-disc disc-slate size-12 rounded-full"><UserX class="size-6" /></span>
            <p class="mt-3 font-semibold text-slate-900">This house is vacant</p>
            <p class="mt-1 text-sm text-slate-500">Add a tenant to start collecting rent.</p>
            <button type="button" class="add-pill mt-4" @click="openPick"><UserRoundPlus class="size-[1.2rem]" stroke-width="2.25" /> Add a tenant</button>
          </div>

          <button type="button" class="danger-link mt-3" @click="removeProperty">
            <Trash2 class="size-3.5" /> Delete this {{ parent ? 'room' : 'house' }}
          </button>
        </section>

        <!-- Payments -->
        <section class="rise lg:col-span-3" style="--d: 120ms">
          <h2 class="section-title">Rent history</h2>
          <div class="sheet">
            <ul v-if="payments.length" class="divide-y divide-slate-100">
              <li v-for="p in payments" :key="p.id" class="flex items-center gap-3.5 px-4 py-3.5">
                <span class="icon-disc" :class="p.status === 'paid' ? 'disc-solid' : p.status === 'overdue' ? 'disc-red' : 'disc-amber'">
                  <ArrowDownLeft v-if="p.status === 'paid'" class="size-5" />
                  <AlertCircle v-else-if="p.status === 'overdue'" class="size-5" />
                  <Clock v-else class="size-5" />
                </span>
                <div class="min-w-0 flex-1">
                  <p class="truncate font-medium text-slate-900">{{ formatPeriod(p.period) }}</p>
                  <p class="truncate text-xs text-slate-500">
                    <template v-if="p.paidAt">Paid {{ formatDate(p.paidAt) }}<template v-if="p.method"> · {{ p.method }}</template></template>
                    <template v-else>Due {{ formatDate(p.dueDate) }}<template v-if="p.amountPaid"> · {{ formatUGX(p.amountPaid) }} paid</template></template>
                  </p>
                </div>
                <div class="shrink-0 text-right">
                  <p class="font-semibold text-slate-900 tabular-nums">{{ formatUGX(p.amount) }}</p>
                  <p class="text-xs font-medium capitalize" :class="p.status === 'paid' ? 'text-emerald-700' : p.status === 'overdue' ? 'text-red-600' : 'text-amber-700'">{{ p.status }}</p>
                </div>
              </li>
            </ul>
            <EmptyState v-else kind="money" title="No rent history yet" text="Rent months for this place appear here." />
          </div>
        </section>
      </div>

      <template v-if="tenant">
        <RecordPaymentModal v-model="showCash" :tenant-id="tenant.id" :preset-amount="payAmount" />
      </template>
      <!-- Outside the v-if: it stays open to say the room is vacant once the tenant has left -->
      <EndTenancyModal v-model="endOpen" :tenant="tenant" @record="recordPay" />

      <!-- Add a tenant to THIS house: someone from Records, or a new tenant. You stay on this page. -->
      <BaseModal v-model="pickOpen" center width="max-w-md" :title="`Add a tenant · ${property.name}`">
        <div class="space-y-4">
          <template v-if="returning.length">
            <p class="text-sm text-slate-500">Move someone back in, or add a new tenant.</p>
            <ul class="max-h-[50dvh] space-y-2 overflow-y-auto overscroll-contain pr-0.5">
              <li v-for="r in returning" :key="r.personId" class="person-card flex items-center gap-3 rounded-2xl p-3">
                <span class="person-avatar">{{ initials(r.name) }}</span>
                <div class="min-w-0 flex-1">
                  <p class="truncate font-semibold text-slate-900">{{ r.name }}</p>
                  <p class="truncate text-xs text-slate-500">{{ r.phone || r.email || 'No contact' }}</p>
                  <p class="truncate text-[11px] text-slate-400">Last in {{ rental.propertyById(r.latestEnded.lastPropertyId) ? rental.placeName(r.latestEnded.lastPropertyId) : 'a removed house' }}<template v-if="r.latestEnded.endedAt"> · left {{ formatDate(r.latestEnded.endedAt) }}</template></p>
                </div>
                <button type="button" class="btn-primary h-9 shrink-0 rounded-xl px-3 text-sm" :data-busy="movingIn === r.personId" :disabled="Boolean(movingIn)" @click="moveIn(r)">
                  {{ movingIn === r.personId ? 'Adding…' : 'Move in' }}
                </button>
              </li>
            </ul>
          </template>
          <div v-else class="flex flex-col items-center rounded-2xl bg-slate-50 px-5 py-8 text-center">
            <span class="icon-disc disc-slate size-12 rounded-full"><UserX class="size-6" /></span>
            <p class="mt-3 font-semibold text-slate-900">No tenants to add yet</p>
            <p class="mt-1 text-sm text-slate-500">Add a new tenant for {{ property.name }}.</p>
          </div>
          <p v-if="pickError" class="form-error" role="alert">{{ pickError }}</p>
          <button type="button" class="btn-primary h-12 w-full rounded-2xl" @click="newTenant"><UserRoundPlus class="size-5" /> Add a new tenant</button>
        </div>
      </BaseModal>
      <TenantFormModal v-model="formOpen" :property-id="id" @saved="onTenantSaved" />
      <BaseModal v-model="editOpen" :title="parent ? 'Edit room' : 'Edit house'" width="max-w-md">
        <form class="space-y-4" @submit.prevent="saveEdit">
          <div>
            <label class="label" for="ed-name">Name</label>
            <input id="ed-name" v-model="edit.name" class="input" required />
          </div>
          <div v-if="!parent">
            <label class="label" for="ed-loc">Location</label>
            <input id="ed-loc" v-model="edit.location" class="input" required />
          </div>
          <div>
            <label class="label" for="ed-rent">Monthly rent (UGX)</label>
            <input id="ed-rent" v-model="edit.rent" type="number" min="0" step="1000" class="input" required />
            <p class="mt-1 text-xs text-slate-500">New rent applies from the next rent charge.</p>
          </div>
          <p v-if="editError" class="form-error" role="alert">{{ editError }}</p>
          <div class="flex justify-end gap-2">
            <button type="button" class="btn-secondary" @click="editOpen = false">Cancel</button>
            <button :data-busy="Boolean(editBusy)" type="submit" class="btn-primary" :disabled="editBusy">{{ editBusy ? 'Saving…' : 'Save' }}</button>
          </div>
        </form>
      </BaseModal>
      <template v-if="tenant">
        <ConnectCodeModal v-if="showCode" v-model="showCode" :tenant-id="tenant.id" />
        <BaseModal v-model="accessOpen" title="Give app access" width="max-w-md">
          <div class="space-y-4">
            <div class="flex items-center gap-3 rounded-xl bg-slate-50 p-4">
              <span class="icon-disc disc-brand rounded-full"><Smartphone class="size-5" /></span>
              <div class="min-w-0">
                <p class="truncate font-medium text-slate-900">{{ tenant.name }}</p>
                <p class="text-sm text-slate-500">{{ tenant.phone || 'No phone number' }}</p>
              </div>
            </div>
            <ol class="space-y-2 text-sm text-slate-600">
              <li class="flex gap-2.5"><span class="step-dot">1</span> Their account is created now, already linked to you. No connection code.</li>
              <li class="flex gap-2.5"><span class="step-dot">2</span> They open Renta and sign in with this phone number.</li>
              <li class="flex gap-2.5"><span class="step-dot">3</span> They add their email and choose a password, then they're in.</li>
            </ol>
            <p v-if="accessError" class="form-error" role="alert">{{ accessError }}</p>
            <div class="flex justify-end gap-2">
              <button class="btn-secondary" @click="accessOpen = false">Cancel</button>
              <button :data-busy="Boolean(accessBusy)" class="btn-primary" :disabled="accessBusy || !tenant.phone" @click="giveAccess">
                {{ accessBusy ? 'Setting up…' : 'Give app access' }}
              </button>
            </div>
          </div>
        </BaseModal>
      </template>
    </template>
  </div>
</template>

<style scoped>
.person-card { background: var(--color-white); box-shadow: inset 0 0 0 1px var(--color-slate-200); }
.person-avatar {
  display: flex;
  width: 2.75rem;
  height: 2.75rem;
  flex-shrink: 0;
  align-items: center;
  justify-content: center;
  border-radius: 0.95rem;
  font-size: 0.85rem;
  font-weight: 700;
  color: #fff;
  background: linear-gradient(140deg, #14b8a6, #0f766e 60%, #0a3b38);
}
.step-dot {
  display: flex;
  width: 1.375rem;
  height: 1.375rem;
  flex-shrink: 0;
  align-items: center;
  justify-content: center;
  border-radius: 9999px;
  background: var(--color-brand-50);
  color: var(--color-brand-700);
  font-size: 0.75rem;
  font-weight: 600;
}
</style>
