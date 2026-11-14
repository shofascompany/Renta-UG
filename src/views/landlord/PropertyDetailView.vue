<script setup>
import { computed, ref } from 'vue'
import { useRouter } from 'vue-router'
import ConnectCodeModal from '@/components/ConnectCodeModal.vue'
import CashPaymentModal from '@/components/CashPaymentModal.vue'
import {
  ArrowLeft, MapPin, BedDouble, Bath, Phone, Mail, UserX, Smartphone, CheckCircle2, Building2, KeyRound, Banknote,
  LogOut, Trash2, UserCog, ArrowDownLeft, Clock, AlertCircle, Pencil, ChevronRight,
} from '@lucide/vue'
import BaseModal from '@/components/BaseModal.vue'
import AdminHeader from '@/components/admin/AdminHeader.vue'
import { useRentalStore } from '@/stores/rental'
import { formatUGX, formatDate, formatPeriod, daysUntil, timeLeft } from '@/utils/format'

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

async function endTenancy() {
  if (!confirm(`End ${tenant.value.name}'s tenancy?\n\nThey move to Records with all their history kept, and this house becomes vacant. You can add them back any time.`)) return
  try {
    await rental.endTenancy(tenant.value.id)
    router.push('/landlord/records')
  } catch (e) {
    alert(e.message)
  }
}

async function removeProperty() {
  if (!confirm(`Delete "${property.value.name}"? This can't be undone.`)) return
  try {
    const back = parent.value ? `/landlord/rentals/${parent.value.id}` : '/landlord/properties'
    await rental.deleteProperty(props.id)
    router.push(back)
  } catch (e) {
    alert(e.message)
  }
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
</script>

<template>
  <div class="mx-auto max-w-6xl">
    <RouterLink :to="parent ? `/landlord/rentals/${parent.id}` : '/landlord/properties'" class="mb-4 inline-flex items-center gap-1.5 rounded-lg py-1 text-sm font-medium text-slate-500 hover:text-slate-900">
      <ArrowLeft class="size-4" /> {{ parent ? parent.name : 'My properties' }}
    </RouterLink>

    <div v-if="!property" class="py-20 text-center text-sm text-slate-500">House not found.</div>

    <template v-else>
      <!-- House -->
      <AdminHeader
        :eyebrow="`${parent ? parent.name : property.type} · ${tenant ? 'Occupied' : 'Vacant'}`"
        :title="property.name"
        :subtitle="parent ? `${property.location} · ${formatUGX(property.rent)} a month` : `${property.location} · ${formatUGX(property.rent)} a month · ${property.bedrooms} bed, ${property.bathrooms} bath`"
      >
        <button class="btn-secondary h-10" @click="openEdit"><Pencil class="size-4" /> {{ parent ? 'Rename or change rent' : 'Edit house' }}</button>
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
                <p v-if="tenant.userId" class="text-xs font-medium text-emerald-700">Uses the app</p>
                <p v-else-if="tenant.managedByLandlord" class="flex items-center gap-1 text-xs font-medium text-slate-600"><UserCog class="size-3.5" /> Managed by you · no smartphone</p>
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
              <div class="flex justify-between gap-3 px-5 py-3"><dt class="text-slate-500">Rental time</dt><dd class="text-right"><p class="font-medium text-slate-900">{{ timeLeft(tenant.leaseEnd ? daysUntil(tenant.leaseEnd) : null) }}</p><p v-if="tenant.leaseEnd" class="text-xs text-slate-500">{{ formatDate(tenant.leaseStart) }} – {{ formatDate(tenant.leaseEnd) }}</p></dd></div>
              <div class="flex justify-between gap-3 px-5 py-3"><dt class="text-slate-500">Balance</dt><dd class="font-semibold" :class="balance ? 'text-red-600' : 'text-emerald-700'">{{ formatUGX(balance) }}</dd></div>
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
                <p v-if="switchError" class="text-xs text-red-600">{{ switchError }}</p>
              </template>
              <RouterLink v-if="tenant.managedByLandlord && !tenant.userId" :to="`/landlord/managed/${tenant.id}`" class="flex items-center gap-3 rounded-xl bg-slate-50 px-4 py-3 text-sm font-medium text-slate-700 hover:bg-slate-100">
                <UserCog class="size-4 text-slate-500" /> <span class="flex-1">Open their account page</span> <ChevronRight class="size-4 text-slate-400" />
              </RouterLink>
              <p v-if="accessGiven" class="flex items-start gap-2 rounded-xl border border-emerald-200 bg-emerald-50 p-3 text-xs text-emerald-800">
                <CheckCircle2 class="mt-0.5 size-4 shrink-0" />
                <span>App access given. {{ tenant.name.split(' ')[0] }} can now sign in with <strong>{{ accessGiven }}</strong>. No code needed.</span>
              </p>
              <div class="grid grid-cols-2 gap-2">
                <button class="btn-secondary h-11" @click="showCash = true"><Banknote class="size-4" /> Cash</button>
                <button class="btn-secondary h-11" @click="endTenancy"><LogOut class="size-4" /> End tenancy</button>
              </div>
            </div>
          </div>

          <div v-else class="sheet flex flex-col items-center px-6 py-10 text-center">
            <span class="icon-disc disc-slate size-12 rounded-full"><UserX class="size-6" /></span>
            <p class="mt-3 font-semibold text-slate-900">This house is vacant</p>
            <p class="mt-1 text-sm text-slate-500">Add a tenant to start collecting rent.</p>
            <RouterLink to="/landlord/tenants" class="btn-primary mt-4 h-11">Add a tenant</RouterLink>
          </div>

          <button class="mt-3 flex w-full items-center justify-center gap-1.5 py-2 text-xs font-medium text-red-600 hover:text-red-700" @click="removeProperty">
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
            <p v-else class="px-5 py-12 text-center text-sm text-slate-500">No rent charges for this house yet.</p>
          </div>
        </section>
      </div>

      <template v-if="tenant">
        <CashPaymentModal v-model="showCash" :tenant-id="tenant.id" />
      </template>
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
          <p v-if="editError" class="text-sm text-red-600">{{ editError }}</p>
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
            <p v-if="accessError" class="rounded-lg bg-red-50 p-3 text-sm text-red-700">{{ accessError }}</p>
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
