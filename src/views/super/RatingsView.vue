<script setup>
import { computed } from 'vue'
import { TriangleAlert } from '@lucide/vue'
import { useSiteStats } from '@/composables/useSiteStats'
import { useFilter } from '@/composables/useFilter'
import SuperHero from '@/components/super/SuperHero.vue'
import RatingSummary from '@/components/super/RatingSummary.vue'
import RatingRow from '@/components/super/RatingRow.vue'
import EmptyState from '@/components/EmptyState.vue'

// Main admin only: the stars people gave Renta UG, the average, and who gave them.
const { data, missing, error } = useSiteStats('admin_ratings', ['app_ratings'])

const total = computed(() => data.value?.total ?? 0)
const stars = useFilter('stars', 0) // 0 = all
const who = useFilter('who', 'all', ['all', 'landlord', 'tenant'])
const list = computed(() =>
  (data.value?.list ?? []).filter((r) => (!stars.value || r.stars === stars.value) && (who.value === 'all' || r.role === who.value)),
)
</script>

<template>
  <div class="mx-auto max-w-3xl">
    <SuperHero eyebrow="Growth" title="Ratings" subtitle="Stars from landlords and tenants, asked after 7 days of use. Only you see them." tone="amber" />

    <p v-if="missing" class="mb-4 flex items-start gap-2 rounded-xl bg-amber-50 p-3 text-sm text-amber-800">
      <TriangleAlert class="mt-0.5 size-4 shrink-0" />
      <span>Ratings aren't set up yet. Run <strong>database/update_existing.sql</strong> in Supabase → SQL Editor, then refresh.</span>
    </p>
    <p v-else-if="error" class="form-error mb-4" role="alert">{{ error }}</p>

    <section class="sheet p-5 sm:p-7"><RatingSummary v-model="stars" :data="data" pick /></section>

    <div class="mt-6 flex flex-wrap items-center justify-between gap-3">
      <h2 class="section-title mb-0!">{{ stars ? `${stars} star${stars === 1 ? '' : 's'}` : 'All ratings' }}</h2>
      <div class="flex rounded-lg bg-slate-100 p-0.5 text-xs">
        <button v-for="f in [['all', 'Everyone'], ['landlord', 'Landlords'], ['tenant', 'Tenants']]" :key="f[0]" type="button" class="h-8 rounded-md px-3 font-medium" :class="who === f[0] ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500'" @click="who = f[0]">{{ f[1] }}</button>
      </div>
    </div>
    <div class="sheet mt-3">
      <ul v-if="list.length" class="divide-y divide-slate-100">
        <RatingRow v-for="r in list" :key="r.id" :rating="r" />
      </ul>
      <EmptyState v-else kind="activity" title="No ratings here yet" :text="total ? 'No rating matches this filter.' : 'They appear here as soon as someone sends their stars.'" />
    </div>
  </div>
</template>
