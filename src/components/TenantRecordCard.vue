<script setup>
import { computed, ref, watch } from 'vue'
import { Home, CalendarDays, Wallet, Bell, ChevronDown, Mail, Phone } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { formatUGX, formatDate, formatPeriod } from '@/utils/format'
import BaseModal from './BaseModal.vue'
import StatusBadge from './StatusBadge.vue'

// Landlord: everything about one person, split into separate stays (one per house and period).
const props = defineProps({ record: { type: Object, default: null } }) // an entry from rental.tenantRecords
const open = defineModel({ type: Boolean, default: false })

const rental = useRentalStore()
const openStay = ref(null)

watch(open, (v) => {
  if (v) openStay.value = props.record?.stays[0]?.id ?? null
})

const houseName = (id) => rental.propertyById(id)?.name ?? 'Removed house'

const stays = computed(() =>
  (props.record?.stays ?? []).map((t) => {
    const payments = rental.paymentsForTenant(t.id)
    return {
      ...t,
      house: houseName(t.propertyId ?? t.lastPropertyId),
      rent: rental.propertyById(t.propertyId ?? t.lastPropertyId)?.rent,
      payments,
      notifications: rental.notificationsForTenant(t.id),
      paid: payments.reduce((s, p) => s + p.amountPaid, 0),
      owed: payments.reduce((s, p) => s + p.balance, 0),
    }
  }),
)
</script>

<template>
  <BaseModal v-model="open" :title="record?.name ?? 'Tenant record'" width="max-w-2xl">
    <template v-if="record">
      <!-- Person -->
      <div class="mb-5 flex flex-wrap items-center gap-x-5 gap-y-2 text-sm text-slate-600">
        <StatusBadge :status="record.status" />
        <span v-if="record.email" class="flex items-center gap-1.5"><Mail class="size-4 text-slate-400" /> {{ record.email }}</span>
        <span v-if="record.phone" class="flex items-center gap-1.5"><Phone class="size-4 text-slate-400" /> {{ record.phone }}</span>
        <span class="text-slate-400">{{ stays.length }} stay{{ stays.length === 1 ? '' : 's' }}</span>
      </div>

      <!-- One section per stay -->
      <div class="space-y-3">
        <section v-for="s in stays" :key="s.id" class="rounded-xl border border-slate-200">
          <button
            class="flex w-full items-center gap-3 px-4 py-3 text-left"
            :aria-expanded="openStay === s.id"
            @click="openStay = openStay === s.id ? null : s.id"
          >
            <div class="flex size-9 shrink-0 items-center justify-center rounded-full bg-slate-50">
              <Home class="size-4 text-slate-500" />
            </div>
            <div class="min-w-0 flex-1">
              <p class="truncate text-sm font-medium text-slate-900">{{ s.house }}</p>
              <p class="flex items-center gap-1 text-xs text-slate-500">
                <CalendarDays class="size-3.5" />
                {{ formatDate(s.leaseStart ?? s.createdAt) }} – {{ s.propertyId ? 'present' : formatDate(s.endedAt) }}
              </p>
            </div>
            <StatusBadge :status="s.propertyId ? 'active' : 'ended'" />
            <ChevronDown class="size-4 shrink-0 text-slate-400 transition-transform" :class="openStay === s.id && 'rotate-180'" />
          </button>

          <div v-if="openStay === s.id" class="space-y-5 border-t border-slate-100 px-4 py-4">
            <!-- Summary -->
            <dl class="grid grid-cols-3 gap-3 text-sm">
              <div class="rounded-lg bg-slate-50 p-3">
                <dt class="text-xs text-slate-500">Rent</dt>
                <dd class="mt-0.5 font-medium text-slate-900">{{ s.rent ? formatUGX(s.rent) : '—' }}</dd>
              </div>
              <div class="rounded-lg bg-slate-50 p-3">
                <dt class="text-xs text-slate-500">Paid</dt>
                <dd class="mt-0.5 font-medium text-slate-900">{{ formatUGX(s.paid) }}</dd>
              </div>
              <div class="rounded-lg bg-slate-50 p-3">
                <dt class="text-xs text-slate-500">Owed</dt>
                <dd class="mt-0.5 font-medium" :class="s.owed ? 'text-red-600' : 'text-slate-900'">{{ formatUGX(s.owed) }}</dd>
              </div>
            </dl>

            <!-- Payments -->
            <div>
              <h4 class="mb-2 flex items-center gap-1.5 text-xs font-medium tracking-wide text-slate-500 uppercase">
                <Wallet class="size-3.5" /> Payments
              </h4>
              <table v-if="s.payments.length" class="min-w-full text-sm">
                <tbody class="divide-y divide-slate-100">
                  <tr v-for="p in s.payments" :key="p.id">
                    <td class="py-2 pr-3 text-slate-900">{{ formatPeriod(p.period) }}</td>
                    <td class="py-2 pr-3 text-slate-700">{{ formatUGX(p.amount) }}</td>
                    <td class="hidden py-2 pr-3 text-slate-500 sm:table-cell">
                      {{ p.paidAt ? `Paid ${formatDate(p.paidAt)}${p.method ? ' · ' + p.method : ''}` : `Due ${formatDate(p.dueDate)}` }}
                    </td>
                    <td class="py-2 text-right"><StatusBadge :status="p.status" /></td>
                  </tr>
                </tbody>
              </table>
              <p v-else class="text-sm text-slate-500">No payments in this stay.</p>
            </div>


            <!-- Notifications -->
            <div>
              <h4 class="mb-2 flex items-center gap-1.5 text-xs font-medium tracking-wide text-slate-500 uppercase">
                <Bell class="size-3.5" /> Notifications
              </h4>
              <ul v-if="s.notifications.length" class="divide-y divide-slate-100 text-sm">
                <li v-for="n in s.notifications" :key="n.id" class="flex items-center justify-between gap-3 py-2">
                  <span class="truncate text-slate-800">{{ n.title }}</span>
                  <span class="shrink-0 text-xs text-slate-400">{{ formatDate(n.createdAt) }}</span>
                </li>
              </ul>
              <p v-else class="text-sm text-slate-500">None.</p>
            </div>
          </div>
        </section>
      </div>
    </template>
  </BaseModal>
</template>
