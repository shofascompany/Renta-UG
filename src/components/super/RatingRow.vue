<script setup>
import { computed } from 'vue'
import { ChevronRight, Star } from '@lucide/vue'
import { prettyPhone } from '@/lib/phone'
import { formatDate } from '@/utils/format'

// Main admin: one rating: who gave it, how many stars, when. Opens the person's page when they still have one.
const props = defineProps({ rating: { type: Object, required: true } })
const to = computed(() => {
  const r = props.rating
  if (r.role === 'landlord') return r.userId ? `/admin2026/landlords/${r.userId}` : null
  return r.tenantId ? `/admin2026/tenants/${r.tenantId}` : null
})
const about = computed(() => {
  const r = props.rating
  return [r.role === 'landlord' ? 'Landlord' : 'Tenant', r.phone ? prettyPhone(r.phone) : r.email].filter(Boolean).join(' · ')
})
</script>

<template>
  <li>
    <component :is="to ? 'RouterLink' : 'div'" :to="to || undefined" class="flex items-center gap-3.5 px-4 py-4 transition-colors sm:px-5" :class="to && 'hover:bg-slate-50 active:bg-slate-100'">
      <span class="icon-disc disc-amber text-sm font-bold">{{ rating.stars }}</span>
      <span class="min-w-0 flex-1">
        <span class="block truncate font-medium text-slate-900">{{ rating.userId ? rating.name || 'No name' : 'Deleted account' }}</span>
        <span class="mt-0.5 block truncate text-xs text-slate-500">{{ about }}</span>
      </span>
      <span class="shrink-0 text-right">
        <span class="flex justify-end gap-0.5" role="img" :aria-label="`${rating.stars} out of 5 stars`"><Star v-for="n in 5" :key="n" class="size-4" :class="n <= rating.stars ? 'fill-amber-400 text-amber-400' : 'text-slate-300'" stroke-width="1.5" /></span>
        <span class="mt-1 block text-[11px] text-slate-500">{{ formatDate(rating.createdAt) }}</span>
      </span>
      <ChevronRight v-if="to" class="size-4 shrink-0 text-slate-300" />
    </component>
  </li>
</template>
