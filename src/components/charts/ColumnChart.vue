<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'

// Columns over time. Optional `ghost` per column (e.g. billed) is drawn as a lighter track behind the
// main value (e.g. collected), so "how much of the target" reads at a glance. One y-axis only.
const props = defineProps({
  data: { type: Array, required: true }, // [{ label, value, ghost? }]
  valueLabel: { type: String, default: 'Value' },
  ghostLabel: { type: String, default: '' },
  format: { type: Function, default: (v) => String(v) }, // tooltip / cap values
  tick: { type: Function, default: (v) => String(v) }, // axis ticks (compact)
  height: { type: Number, default: 220 },
})

const el = ref(null)
const width = ref(600)
let ro = null
onMounted(() => {
  // Always exactly as wide as its card, on any phone (never wider, so the page never scrolls sideways)
  ro = new ResizeObserver(([e]) => (width.value = Math.max(160, Math.floor(e.contentRect.width))))
  ro.observe(el.value)
})
onBeforeUnmount(() => ro?.disconnect())

const pad = { top: 22, right: 8, bottom: 28, left: 44 }
const plotW = computed(() => width.value - pad.left - pad.right)
const plotH = computed(() => props.height - pad.top - pad.bottom)
const hasGhost = computed(() => props.data.some((d) => d.ghost != null))

// Clean ticks: 0 and three steps above
const max = computed(() => {
  const m = Math.max(1, ...props.data.map((d) => Math.max(d.value, d.ghost ?? 0)))
  const mag = 10 ** Math.floor(Math.log10(m))
  const step = [1, 2, 2.5, 5, 10].map((s) => s * mag).find((s) => s * 3 >= m) ?? mag * 10
  return step * 3
})
const ticks = computed(() => [0, 1, 2, 3].map((i) => (max.value / 3) * i))
const y = (v) => pad.top + plotH.value - (v / max.value) * plotH.value

const band = computed(() => plotW.value / Math.max(1, props.data.length))
const barW = computed(() => Math.min(24, band.value * 0.55))
const x = (i) => pad.left + band.value * i + band.value / 2

// Column with a 4px rounded top, square at the baseline
function colPath(i, v) {
  const h = (v / max.value) * plotH.value
  if (h <= 0) return ''
  const w = barW.value
  const r = Math.min(4, h, w / 2)
  const x0 = x(i) - w / 2
  const yb = pad.top + plotH.value
  const yt = yb - h
  return `M${x0},${yb} V${yt + r} Q${x0},${yt} ${x0 + r},${yt} H${x0 + w - r} Q${x0 + w},${yt} ${x0 + w},${yt + r} V${yb} Z`
}

const hover = ref(null)
const tip = computed(() => {
  if (hover.value == null) return null
  const d = props.data[hover.value]
  const edge = Math.min(90, width.value / 2)
  const left = Math.min(Math.max(x(hover.value), edge), width.value - edge)
  return { d, left }
})
const lastIndex = computed(() => props.data.length - 1)
</script>

<template>
  <div ref="el" class="viz relative select-none">
    <!-- Legend (2 series) -->
    <div v-if="hasGhost" class="mb-3 flex flex-wrap gap-x-4 gap-y-1 text-xs text-slate-600">
      <span class="flex items-center gap-1.5"><span class="size-2.5 rounded-sm" style="background: var(--series-1)" /> {{ valueLabel }}</span>
      <span class="flex items-center gap-1.5"><span class="size-2.5 rounded-sm" style="background: var(--series-track)" /> {{ ghostLabel }}</span>
    </div>

    <svg class="block max-w-full" :width="width" :height="height" :viewBox="`0 0 ${width} ${height}`" role="img" :aria-label="`${valueLabel} by month`" @mouseleave="hover = null">
      <!-- grid + ticks -->
      <g>
        <line
          v-for="t in ticks"
          :key="t"
          :x1="pad.left"
          :x2="width - pad.right"
          :y1="y(t)"
          :y2="y(t)"
          :stroke="t === 0 ? 'var(--viz-axis)' : 'var(--viz-grid)'"
          stroke-width="1"
        />
        <text v-for="t in ticks" :key="`t${t}`" :x="pad.left - 8" :y="y(t) + 4" text-anchor="end" class="tick">{{ tick(t) }}</text>
      </g>

      <!-- columns -->
      <g v-for="(d, i) in data" :key="d.label">
        <path v-if="d.ghost" :d="colPath(i, d.ghost)" fill="var(--series-track)" />
        <path :d="colPath(i, d.value)" fill="var(--series-1)" :opacity="hover == null || hover === i ? 1 : 0.55" />
        <text :x="x(i)" :y="height - 8" text-anchor="middle" class="tick" :class="i === lastIndex && 'tick-strong'">{{ d.label }}</text>
        <!-- value on the cap of the latest column only -->
        <text v-if="i === lastIndex && d.value" :x="x(i)" :y="y(Math.max(d.value, d.ghost ?? 0)) - 7" text-anchor="middle" class="cap">{{ tick(d.value) }}</text>
        <!-- hit target: the whole band -->
        <rect
          :x="pad.left + band * i"
          :y="pad.top"
          :width="band"
          :height="plotH"
          fill="transparent"
          @mouseenter="hover = i"
          @touchstart.passive="hover = i"
        />
      </g>
    </svg>

    <!-- tooltip -->
    <div
      v-if="tip"
      class="pointer-events-none absolute top-6 z-10 w-44 max-w-[calc(100%-0.5rem)] -translate-x-1/2 rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-xs shadow-lg"
      :style="{ left: `${tip.left}px` }"
    >
      <p class="font-semibold text-slate-900">{{ tip.d.full ?? tip.d.label }}</p>
      <p class="mt-1 flex items-center justify-between gap-2 text-slate-600">
        <span class="flex items-center gap-1.5"><span class="size-2 rounded-sm" style="background: var(--series-1)" />{{ valueLabel }}</span>
        <span class="font-semibold text-slate-900 tabular-nums">{{ format(tip.d.value) }}</span>
      </p>
      <p v-if="tip.d.ghost != null" class="mt-0.5 flex items-center justify-between gap-2 text-slate-600">
        <span class="flex items-center gap-1.5"><span class="size-2 rounded-sm" style="background: var(--series-track)" />{{ ghostLabel }}</span>
        <span class="font-medium text-slate-900 tabular-nums">{{ format(tip.d.ghost) }}</span>
      </p>
      <p v-if="tip.d.ghost" class="mt-1 border-t border-slate-100 pt-1 text-slate-500">{{ Math.round((tip.d.value / tip.d.ghost) * 100) }}% collected</p>
    </div>
  </div>
</template>

<style scoped>
.tick {
  font-size: 11px;
  fill: var(--viz-muted);
  font-variant-numeric: tabular-nums;
}
.tick-strong {
  fill: var(--color-slate-700);
  font-weight: 600;
}
.cap {
  font-size: 11px;
  font-weight: 600;
  fill: var(--color-slate-900);
}
svg {
  display: block;
  max-width: 100%;
}
</style>
