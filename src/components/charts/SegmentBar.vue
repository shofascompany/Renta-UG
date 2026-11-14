<script setup>
import { computed } from 'vue'

// One whole split into parts (e.g. how rent was paid). Tall segmented bar + a legend that doubles
// as the table view (name, amount, share), so identity never relies on colour alone.
const props = defineProps({
  parts: { type: Array, required: true }, // [{ label, value }]
  format: { type: Function, default: (v) => String(v) },
})
const colors = ['var(--series-1)', 'var(--series-2)', 'var(--series-3)', 'var(--series-4)']
const total = computed(() => props.parts.reduce((s, p) => s + p.value, 0))
const rows = computed(() =>
  props.parts.map((p, i) => ({ ...p, color: colors[i % colors.length], pct: total.value ? (p.value / total.value) * 100 : 0 })),
)
// Label inside a block only when it's wide enough to fit; yellow takes near-black text
const ink = (i) => (i === 3 ? '#0b0b0b' : '#ffffff')
</script>

<template>
  <div class="viz">
    <div
      v-if="total"
      class="flex h-7 w-full gap-0.5 overflow-hidden"
      role="img"
      :aria-label="rows.map((r) => `${r.label} ${Math.round(r.pct)}%`).join(', ')"
    >
      <div
        v-for="(r, i) in rows"
        :key="r.label"
        class="flex h-full items-center rounded px-2 text-[11px] font-semibold"
        :style="{ width: `${r.pct}%`, background: r.color, color: ink(i) }"
        :title="`${r.label}: ${format(r.value)} (${Math.round(r.pct)}%)`"
      >
        <span v-if="r.pct >= 14">{{ Math.round(r.pct) }}%</span>
      </div>
    </div>
    <div v-else class="h-7 rounded bg-slate-100" />

    <ul class="mt-4 divide-y divide-slate-100 text-sm">
      <li v-for="r in rows" :key="r.label" class="flex items-center gap-3 py-2">
        <span class="size-2.5 shrink-0 rounded-sm" :style="{ background: r.color }" />
        <span class="flex-1 text-slate-700">{{ r.label }}</span>
        <span class="font-semibold text-slate-900 tabular-nums">{{ format(r.value) }}</span>
        <span class="w-10 text-right text-xs text-slate-500 tabular-nums">{{ Math.round(r.pct) }}%</span>
      </li>
      <li v-if="!rows.length" class="py-3 text-center text-sm text-slate-500">No payments yet.</li>
    </ul>
  </div>
</template>
