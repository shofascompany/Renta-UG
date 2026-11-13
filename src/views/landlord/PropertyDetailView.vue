<script setup>
import { computed, ref } from 'vue'
import { useRouter } from 'vue-router'
import ConnectCodeModal from '@/components/ConnectCodeModal.vue'
import CashPaymentModal from '@/components/CashPaymentModal.vue'
import { ArrowLeft, MapPin, BedDouble, Bath, Phone, Mail, UserX } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { formatUGX, formatDate, formatPeriod } from '@/utils/format'
import StatusBadge from '@/components/StatusBadge.vue'
import EmptyState from '@/components/EmptyState.vue'

const props = defineProps({ id: String })
const rental = useRentalStore()
const router = useRouter()
const showCode = ref(false)
const showCash = ref(false)

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
    await rental.deleteProperty(props.id)
    router.push('/landlord/properties')
  } catch (e) {
    alert(e.message)
  }
}

const property = computed(() => rental.propertyById(props.id))
const tenant = computed(() => rental.tenantForProperty(props.id))
const payments = computed(() => rental.payments.filter((p) => p.propertyId === props.id).sort((a, b) => b.period.localeCompare(a.period)))
const balance = computed(() => payments.value.reduce((s, p) => s + p.balance, 0))
</script>

<template>
  <RouterLink to="/landlord/properties" class="mb-6 inline-flex items-center gap-1.5 text-sm text-slate-500 hover:text-slate-900">
    <ArrowLeft class="size-4" /> Properties
  </RouterLink>

  <div v-if="!property" class="py-20 text-center text-sm text-slate-500">Property not found.</div>

  <template v-else>
    <div class="mb-8 flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
      <div>
        <p class="text-xs font-medium tracking-wide text-slate-400 uppercase">{{ property.type }}</p>
        <h1 class="mt-1 text-2xl font-semibold tracking-tight text-slate-900">{{ property.name }}</h1>
        <div class="mt-2 flex flex-wrap items-center gap-4 text-sm text-slate-500">
          <span class="flex items-center gap-1.5"><MapPin class="size-4" /> {{ property.location }}</span>
          <span class="flex items-center gap-1.5"><BedDouble class="size-4" /> {{ property.bedrooms }} bed</span>
          <span class="flex items-center gap-1.5"><Bath class="size-4" /> {{ property.bathrooms }} bath</span>
        </div>
      </div>
      <div class="text-left sm:text-right">
        <p class="text-2xl font-semibold tracking-tight text-slate-900">{{ formatUGX(property.rent) }}</p>
        <p class="text-sm text-slate-500">per month</p>
        <button class="mt-2 text-xs font-medium text-red-600 hover:text-red-700" @click="removeProperty">Delete property</button>
      </div>
    </div>

    <div class="grid gap-6 lg:grid-cols-3">
      <section class="card p-5">
        <div class="flex items-center justify-between">
          <h2 class="text-sm font-semibold text-slate-900">Tenant</h2>
          <StatusBadge :status="tenant ? 'occupied' : 'vacant'" />
        </div>
        <template v-if="tenant">
          <p class="mt-4 font-medium text-slate-900">{{ tenant.name }}</p>
          <a :href="`tel:${tenant.phone}`" class="mt-2 flex items-center gap-2 text-sm text-slate-600 hover:text-brand-600"><Phone class="size-4" /> {{ tenant.phone }}</a>
          <a :href="`mailto:${tenant.email}`" class="mt-1 flex items-center gap-2 text-sm text-slate-600 hover:text-brand-600"><Mail class="size-4" /> {{ tenant.email }}</a>
          <dl class="mt-4 space-y-2 border-t border-slate-100 pt-4 text-sm">
            <div class="flex justify-between"><dt class="text-slate-500">Lease start</dt><dd class="text-slate-900">{{ formatDate(tenant.leaseStart) }}</dd></div>
            <div class="flex justify-between"><dt class="text-slate-500">Lease end</dt><dd class="text-slate-900">{{ formatDate(tenant.leaseEnd) }}</dd></div>
            <div class="flex justify-between"><dt class="text-slate-500">Balance</dt><dd class="font-medium" :class="balance ? 'text-red-600' : 'text-slate-900'">{{ formatUGX(balance) }}</dd></div>
            <div class="flex justify-between"><dt class="text-slate-500">Account</dt><dd :class="tenant.userId ? 'text-emerald-700' : 'text-slate-500'">{{ tenant.userId ? 'Connected' : 'Not connected yet' }}</dd></div>
          </dl>
          <button v-if="!tenant.userId" class="btn-primary mt-4 w-full" @click="showCode = true">Get connection code</button>
          <button v-if="balance" class="btn-secondary mt-2 w-full" @click="showCash = true">Record cash payment</button>
          <button class="btn-secondary mt-2 w-full" @click="endTenancy">End tenancy</button>
          <CashPaymentModal v-model="showCash" :tenant-id="tenant.id" />
          <ConnectCodeModal v-if="showCode" v-model="showCode" :tenant-id="tenant.id" />
        </template>
        <template v-else>
          <EmptyState :icon="UserX" title="No tenant" text="This property is vacant." />
          <RouterLink to="/landlord/tenants" class="btn-secondary w-full">Add a tenant</RouterLink>
        </template>
      </section>

      <section class="card overflow-hidden lg:col-span-2">
        <div class="border-b border-slate-100 px-5 py-4">
          <h2 class="text-sm font-semibold text-slate-900">Payments</h2>
        </div>
        <div class="overflow-x-auto">
          <table v-if="payments.length" class="min-w-full divide-y divide-slate-100">
            <thead><tr><th class="table-head">Period</th><th class="table-head">Amount</th><th class="table-head">Due</th><th class="table-head">Paid</th><th class="table-head">Status</th></tr></thead>
            <tbody class="divide-y divide-slate-100">
              <tr v-for="p in payments" :key="p.id">
                <td class="table-cell font-medium text-slate-900">{{ formatPeriod(p.period) }}</td>
                <td class="table-cell">{{ formatUGX(p.amount) }}</td>
                <td class="table-cell">{{ formatDate(p.dueDate) }}</td>
                <td class="table-cell">{{ formatDate(p.paidAt) }}</td>
                <td class="table-cell"><StatusBadge :status="p.status" /></td>
              </tr>
            </tbody>
          </table>
          <p v-else class="px-5 py-8 text-center text-sm text-slate-500">No payments recorded.</p>
        </div>
      </section>

    </div>
  </template>
</template>
