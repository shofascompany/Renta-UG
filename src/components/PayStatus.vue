<script setup>
import { computed } from 'vue'
import { CircleCheck, CircleAlert, CircleDashed, DoorOpen } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'

// Paid / Part paid / Not paid badge for one tenant, the same everywhere (see utils/payState.js).
//   <PayStatus :tenant-id="t.id" />          badge only
//   <PayStatus :tenant-id="t.id" detail />   badge + "UGX 120,000 owed" / "Paid up to 12 Dec 2026"
const props = defineProps({
  tenantId: { type: String, default: null },
  detail: Boolean,
  size: { type: String, default: 'sm' }, // sm | md
})
const rental = useRentalStore()
const s = computed(() => (props.tenantId ? rental.payStateFor(props.tenantId) : null))
const icon = computed(() => ({ paid: CircleCheck, part: CircleDashed, unpaid: CircleAlert, left: DoorOpen })[s.value?.key])
</script>

<template>
  <span v-if="s" class="inline-flex flex-wrap items-center gap-x-2 gap-y-0.5">
    <span
      class="inline-flex shrink-0 items-center gap-1 rounded-full font-semibold whitespace-nowrap ring-1 ring-inset"
      :class="[s.pill, size === 'md' ? 'px-2.5 py-1 text-xs' : 'px-2 py-0.5 text-[11px]']"
    >
      <component :is="icon" :class="size === 'md' ? 'size-3.5' : 'size-3'" /> {{ s.label }}
    </span>
    <span v-if="detail" class="text-xs" :class="s.key === 'paid' ? 'text-slate-500' : s.text">{{ s.detail }}</span>
  </span>
</template>
