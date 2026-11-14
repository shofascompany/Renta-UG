<script setup>
import { computed } from 'vue'

// Horizontal bars, largest first, value at the tip. One series → no legend (the card title names it).
// `ramp` = colour each bar by its position on an ordinal scale (e.g. how late rent is).
const props = defineProps({
  rows: { type: Array, required: true }, // [{ label, value, sub? }]
  format: { type: Function, default: (v) => String(v) },
  ramp: Boolean,
  limit: { type: Number, default: 8 },
})
const shown = computed(() => props.rows.slice(0, props.limit))
const max = computed(() => Math.max(1, ...shown.value.map((r) => r.value)))
const rampColors = ['var(--seq-1)', 'var(--seq-2)', 'var(--seq-3)', 'var(--seq-4)', 'var(--seq-4)']
const color = (i) => (props.ramp ? rampColors[Math.min(i, rampColors.length - 1)] : 'var(--series-1)')
</script>

<template>
  <ul class="viz space-y-3">
    <li v-for="(r, i) in shown" :key="r.label" :title="`${r.label}: ${format(r.value)}`">
      <div class="flex items-baseline justify-between gap-3 text-sm">
        <span class="min-w-0 truncate text-slate-700">{{ r.label }}<span v-if="r.sub" class="ml-1.5 text-xs text-slate-400">{{ r.sub }}</span></span>
        <span class="shrink-0 font-semibold text-slate-900 tabular-nums">{{ format(r.value) }}</span>
      </div>
      <div class="mt-1.5 h-2 rounded-full bg-slate-100">
        <div
          class="h-full rounded-full transition-[width] duration-700 ease-out"
          :style="{ width: `${r.value ? Math.max(2, (r.value / max) * 100) : 0}%`, background: color(i) }"
        />
      </div>
    </li>
    <li v-if="!shown.length" class="py-6 text-center text-sm text-slate-500">Nothing to show yet.</li>
  </ul>
</template>
