<script setup>
import { computed } from 'vue'
import { ArrowRight, Check, CalendarCheck, CircleAlert, DoorOpen, HandCoins, Hourglass } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { formatUGX, formatDate } from '@/utils/format'

// What ending a tenancy means, at a glance: who leaves which room, how the stay stands (paid, owed,
// days left) and what happens next. Used wherever a tenancy can be ended, so it reads the same everywhere.
//   by       landlord | admin
//   approve  true when the tenant asked to leave (their app signs them out with a goodbye)
//   placeId  the room, when the tenant record may no longer have it
const props = defineProps({
  tenant: { type: Object, required: true },
  by: { type: String, default: 'landlord' },
  approve: Boolean,
  placeId: { type: String, default: null },
})
// record: the landlord wants to record a payment before ending the tenancy
const emit = defineEmits(['record', 'leave'])

const rental = useRentalStore()
const first = computed(() => props.tenant.name.split(' ')[0])
const initials = computed(() => props.tenant.name.split(' ').map((p) => p[0]).slice(0, 2).join('').toUpperCase())
const roomId = computed(() => props.tenant.propertyId ?? props.placeId ?? props.tenant.lastPropertyId)
const property = computed(() => rental.propertyById(roomId.value))
const building = computed(() => (property.value?.rentalId ? rental.rentalById(property.value.rentalId)?.name : property.value?.location))
const kind = computed(() => (property.value?.rentalId ? 'room' : 'house'))

const plural = (n, word) => `${n} ${word}${n === 1 ? '' : 's'}`
const since = computed(() => props.tenant.leaseStart ?? props.tenant.createdAt)
const stayed = computed(() => {
  if (!since.value) return ''
  const days = Math.max(1, Math.round((Date.now() - new Date(since.value).getTime()) / 86400000))
  return days < 30 ? plural(days, 'day') : plural(Math.floor(days / 30), 'month') // a rent month is 30 days
})

const pay = computed(() => rental.payStateFor(props.tenant.id)) // Paid / Part paid / Not paid
const paid = computed(() => rental.paymentsForTenant(props.tenant.id).reduce((s, p) => s + p.amountPaid, 0))
const owed = computed(() => rental.duesForTenant(props.tenant.id).reduce((s, p) => s + p.balance, 0))
const waiting = computed(() => rental.cashForTenant(props.tenant.id).filter((c) => c.status === 'pending').reduce((s, c) => s + c.amount, 0))

const total = computed(() => pay.value?.owed || owed.value) // every month in debt
// Money not settled. After the stay ends no payment can be recorded for it, so say so now.
const debt = computed(() => {
  if (owed.value) return `${formatUGX(total.value)} still owed`
  if (pay.value?.key !== 'unpaid') return ''
  return pay.value.ended ? `${pay.value.daysLeft ? plural(-pay.value.daysLeft, 'debt day') : 'Rent'} not paid${total.value ? ` · ${formatUGX(total.value)}` : ''}` : 'No rent paid yet'
})
const daysLeft = computed(() => (pay.value?.key === 'paid' && pay.value.daysLeft > 0 ? pay.value.daysLeft : 0))

const next = computed(() =>
  [
    `The ${kind.value} becomes vacant straight away`,
    'All payments and receipts stay in Records',
    props.approve
      ? `${first.value} is signed out of the app`
      : props.tenant.userId && `${first.value}'s app is no longer linked to this ${kind.value}`,
    props.by === 'admin' ? `${first.value} and the landlord are both told` : `You can add ${first.value} back any time as a new stay`,
  ].filter(Boolean),
)
</script>

<template>
  <div class="space-y-4">
    <!-- Who leaves which room -->
    <div class="leave rounded-3xl px-4 pt-5 pb-4">
      <div class="flex items-start">
        <div class="min-w-0 flex-1 text-center">
          <span class="leave-avatar mx-auto">{{ initials }}</span>
          <p class="mt-2.5 text-sm leading-tight font-semibold text-slate-900">{{ tenant.name }}</p>
          <p class="mt-1 text-xs text-slate-500">moves out</p>
        </div>
        <div class="leave-path" aria-hidden="true"><span class="leave-arrow"><ArrowRight class="size-4" /></span></div>
        <div class="min-w-0 flex-1 text-center">
          <span class="leave-door mx-auto"><DoorOpen class="size-7" stroke-width="1.75" /></span>
          <p class="mt-2.5 text-sm leading-tight font-semibold text-slate-900">{{ property?.name ?? 'Their room' }}</p>
          <p v-if="building" class="mt-1 truncate text-xs text-slate-500">{{ building }}</p>
        </div>
      </div>
      <p v-if="stayed" class="leave-since mt-4 flex items-center justify-center gap-1.5 pt-3 text-xs text-slate-500">
        <CalendarCheck class="size-3.5 shrink-0" />
        <span>Since {{ formatDate(since) }} · <strong class="font-semibold text-slate-700">{{ stayed }}</strong></span>
      </p>
    </div>

    <!-- How the stay stands -->
    <dl class="grid grid-cols-2 gap-2.5">
      <div class="fact">
        <dt class="text-xs text-slate-500">Paid in total</dt>
        <dd class="mt-1 text-base font-bold text-slate-900 tabular-nums">{{ formatUGX(paid) }}</dd>
      </div>
      <div class="fact">
        <dt class="text-xs text-slate-500">Rent</dt>
        <dd class="mt-1 text-base font-bold" :class="pay?.text">{{ pay?.label ?? '—' }}</dd>
      </div>
    </dl>

    <!-- Worth settling first -->
    <div v-if="waiting && by === 'landlord'" class="note note-amber">
      <Hourglass class="note-ico" />
      <div class="min-w-0 flex-1">
        <p class="text-sm font-semibold text-slate-900">{{ formatUGX(waiting) }} waiting for you to confirm</p>
        <p class="mt-0.5 text-xs leading-relaxed text-slate-600">Check it first so it counts towards this stay.</p>
        <RouterLink to="/landlord/payments" class="note-act" @click="emit('leave')">Check the payment</RouterLink>
      </div>
    </div>
    <div v-if="debt" class="note note-amber">
      <CircleAlert class="note-ico" />
      <div class="min-w-0 flex-1">
        <p class="text-sm font-semibold text-slate-900">{{ debt }}</p>
        <p class="mt-0.5 text-xs leading-relaxed text-slate-600">
          <template v-if="owed">This stays on their record. </template>Payments can't be recorded once the stay has ended.
        </p>
        <button v-if="by === 'landlord' && tenant.propertyId" type="button" class="note-act" @click="emit('record', total)">
          <HandCoins class="size-3.5" /> Record a payment first
        </button>
      </div>
    </div>
    <div v-else-if="daysLeft" class="note note-sky">
      <Hourglass class="note-ico" />
      <div class="min-w-0 flex-1">
        <p class="text-sm font-semibold text-slate-900">{{ plural(daysLeft, 'paid day') }} left</p>
        <p class="mt-0.5 text-xs leading-relaxed text-slate-600">Paid up to {{ formatDate(tenant.leaseEnd) }}. Ending now does not refund unused days.</p>
      </div>
    </div>

    <!-- What happens next -->
    <ul class="space-y-2 px-1">
      <li v-for="x in next" :key="x" class="flex items-start gap-2.5 text-sm text-slate-600">
        <span class="tick"><Check class="size-3" stroke-width="3" /></span> <span class="min-w-0 flex-1">{{ x }}</span>
      </li>
    </ul>
  </div>
</template>

<style scoped>
.leave { background: linear-gradient(180deg, var(--color-slate-50), var(--color-white)); box-shadow: inset 0 0 0 1px var(--color-slate-200); }
.leave-avatar,
.leave-door {
  display: flex;
  width: 3.5rem;
  height: 3.5rem;
  align-items: center;
  justify-content: center;
  border-radius: 1.15rem;
}
.leave-avatar {
  color: #fff;
  font-size: 1.05rem;
  font-weight: 700;
  background: linear-gradient(140deg, #14b8a6, #0f766e 60%, #0a3b38);
  box-shadow: 0 10px 20px -12px rgb(15 118 110 / 0.9);
}
/* An empty room: outline only */
.leave-door { color: var(--color-slate-500); background: var(--color-white); border: 2px dashed var(--color-slate-300); }
.leave-path { position: relative; display: flex; width: 4rem; height: 3.5rem; flex-shrink: 0; align-items: center; justify-content: center; }
.leave-path::before {
  content: '';
  position: absolute;
  inset-inline: -0.35rem;
  top: 50%;
  height: 2px;
  margin-top: -1px;
  background: repeating-linear-gradient(90deg, var(--color-slate-300) 0 5px, transparent 5px 10px);
}
.leave-arrow {
  position: relative;
  display: flex;
  width: 2rem;
  height: 2rem;
  align-items: center;
  justify-content: center;
  border-radius: 9999px;
  color: var(--color-slate-600);
  background: var(--color-white);
  box-shadow: inset 0 0 0 1px var(--color-slate-200);
}
.leave-since { border-top: 1px solid var(--color-slate-200); }

.fact { border-radius: 1rem; padding: 0.75rem 0.9rem; background: var(--color-slate-50); }

.note { display: flex; align-items: flex-start; gap: 0.75rem; border-radius: 1rem; padding: 0.85rem 0.9rem; }
.note-ico { width: 1.15rem; height: 1.15rem; flex-shrink: 0; margin-top: 0.1rem; }
.note-amber { background: var(--color-amber-50); }
.note-amber .note-ico { color: var(--color-amber-600); }
.note-sky { background: var(--color-sky-50); }
.note-sky .note-ico { color: var(--color-sky-600); }
.note-act {
  display: inline-flex;
  min-height: 2.25rem;
  align-items: center;
  gap: 0.4rem;
  margin-top: 0.55rem;
  border-radius: 0.7rem;
  padding: 0 0.8rem;
  font-size: 0.8125rem;
  font-weight: 600;
  cursor: pointer;
  color: var(--color-amber-800);
  background: var(--color-white);
  box-shadow: inset 0 0 0 1px var(--color-amber-200);
}
.note-act:active { transform: scale(0.98); }

.tick {
  display: flex;
  width: 1.15rem;
  height: 1.15rem;
  flex-shrink: 0;
  align-items: center;
  justify-content: center;
  margin-top: 0.1rem;
  border-radius: 9999px;
  color: var(--color-brand-700);
  background: var(--color-brand-50);
}
</style>
