<script setup>
import { computed } from 'vue'
import { Star } from '@lucide/vue'

// Main admin: the average rating and how many gave 5, 4, 3, 2 and 1 stars.
// Pick a row to filter by it (v-model: 0 = all).
const props = defineProps({ data: { type: Object, default: null }, pick: Boolean })
const stars = defineModel({ type: Number, default: 0 })

const total = computed(() => props.data?.total ?? 0)
const average = computed(() => (total.value ? Number(props.data.average).toFixed(1) : '—'))
const rows = computed(() =>
  [5, 4, 3, 2, 1].map((n) => {
    const count = props.data?.counts?.[n] ?? 0
    return { n, count, share: total.value ? Math.round((count / total.value) * 100) : 0 }
  }),
)
const choose = (n) => props.pick && (stars.value = stars.value === n ? 0 : n)
</script>

<template>
  <div class="grid gap-6 sm:grid-cols-[auto_1fr] sm:items-center sm:gap-8">
    <div class="text-center">
      <p class="text-5xl font-bold tracking-tight text-slate-900 tabular-nums">{{ average }}</p>
      <p class="mt-2 flex justify-center gap-0.5" role="img" :aria-label="total ? `${average} out of 5 stars` : 'No ratings yet'">
        <Star v-for="n in 5" :key="n" class="size-5" :class="total && n <= Math.round(data.average) ? 'fill-amber-400 text-amber-400' : 'text-slate-300'" stroke-width="1.5" />
      </p>
      <p class="mt-2 text-sm text-slate-500">{{ total.toLocaleString() }} rating{{ total === 1 ? '' : 's' }}</p>
    </div>
    <div class="space-y-1">
      <component
        :is="pick ? 'button' : 'div'"
        v-for="r in rows"
        :key="r.n"
        :type="pick ? 'button' : undefined"
        class="flex w-full items-center gap-3 rounded-lg px-2 py-1.5 text-sm transition-colors"
        :class="[pick && 'hover:bg-slate-50', pick && stars === r.n && 'bg-slate-100']"
        :aria-pressed="pick ? stars === r.n : undefined"
        :aria-label="pick ? `${r.n} stars: ${r.count}` : undefined"
        @click="choose(r.n)"
      >
        <span class="flex w-8 items-center gap-1 font-medium text-slate-700 tabular-nums">{{ r.n }} <Star class="size-3.5 fill-amber-400 text-amber-400" /></span>
        <span class="h-2.5 flex-1 overflow-hidden rounded-full bg-slate-100"><span class="block h-full rounded-full bg-amber-400" :style="{ width: `${r.share}%` }" /></span>
        <span class="w-20 text-right text-slate-600 tabular-nums">{{ r.count.toLocaleString() }} · {{ r.share }}%</span>
      </component>
    </div>
  </div>
</template>
