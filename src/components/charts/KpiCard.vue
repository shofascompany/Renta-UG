<script setup>
import { computed } from 'vue'
import { ArrowUpRight, ArrowDownRight, Minus } from '@lucide/vue'

// Stat tile: label · value · optional delta vs a named period · optional sparkline.
const props = defineProps({
  label: String,
  value: String,
  icon: [Object, Function],
  delta: { type: Number, default: null }, // % change
  deltaLabel: { type: String, default: 'vs last month' },
  upIsGood: { type: Boolean, default: true },
  hint: String,
  trend: { type: Array, default: null }, // numbers, oldest → newest
  tone: { type: String, default: 'brand' }, // icon disc colour: brand | emerald | amber | red | sky | slate
})

const good = computed(() => (props.delta == null || props.delta === 0 ? null : (props.delta > 0) === props.upIsGood))
const spark = computed(() => {
  const t = props.trend
  if (!t || t.length < 2) return null
  const w = 96
  const h = 28
  const max = Math.max(...t)
  const min = Math.min(...t)
  const span = max - min || 1
  const pts = t.map((v, i) => [(i / (t.length - 1)) * w, h - 3 - ((v - min) / span) * (h - 6)])
  return { w, h, d: pts.map((p, i) => `${i ? 'L' : 'M'}${p[0].toFixed(1)},${p[1].toFixed(1)}`).join(' '), last: pts.at(-1) }
})
</script>

<template>
  <div class="viz rounded-2xl border border-slate-200 bg-white p-4 sm:p-5">
    <div class="flex items-start justify-between gap-3">
      <p class="text-sm font-medium text-slate-500">{{ label }}</p>
      <span v-if="icon" class="icon-disc size-9 rounded-xl" :class="`disc-${tone}`"><component :is="icon" class="size-[1.05rem]" /></span>
    </div>
    <p class="mt-2 text-2xl font-bold tracking-tight text-slate-900">{{ value }}</p>
    <div class="mt-2 flex min-h-7 items-end justify-between gap-2">
      <p v-if="delta != null" class="flex items-center gap-1 text-xs">
        <span
          class="inline-flex items-center gap-0.5 rounded-md px-1.5 py-0.5 font-semibold"
          :class="good === null ? 'bg-slate-100 text-slate-600' : good ? 'bg-emerald-50 text-emerald-700' : 'bg-red-50 text-red-700'"
        >
          <ArrowUpRight v-if="delta > 0" class="size-3.5" />
          <ArrowDownRight v-else-if="delta < 0" class="size-3.5" />
          <Minus v-else class="size-3.5" />
          {{ delta > 0 ? '+' : '' }}{{ delta }}%
        </span>
        <span class="text-slate-400">{{ deltaLabel }}</span>
      </p>
      <p v-else-if="hint" class="text-xs text-slate-500">{{ hint }}</p>
      <span v-else />
      <svg v-if="spark" :width="spark.w" :height="spark.h" class="shrink-0" aria-hidden="true">
        <path :d="spark.d" fill="none" stroke="var(--viz-axis)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
        <circle :cx="spark.last[0]" :cy="spark.last[1]" r="3.5" fill="var(--series-1)" stroke="var(--viz-surface)" stroke-width="2" />
      </svg>
    </div>
    <p v-if="delta != null && hint" class="mt-1 text-xs text-slate-500">{{ hint }}</p>
  </div>
</template>
