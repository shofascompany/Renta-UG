<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'

// Values over time, as columns (type 'bar') or as a line (type 'line'): the same axes, tooltip and hover. Optional
// `ghost` per point (e.g. billed) is drawn as a lighter track behind each column, or a dashed line, so "how much of
// the target" reads at a glance. One y-axis only. Many points (every day of a month): only some labels are written.
const props = defineProps({
  data: { type: Array, required: true }, // [{ label, value, ghost? }]
  valueLabel: { type: String, default: 'Value' },
  ghostLabel: { type: String, default: '' },
  format: { type: Function, default: (v) => String(v) }, // tooltip / cap values
  tick: { type: Function, default: (v) => String(v) }, // axis ticks (compact)
  height: { type: Number, default: 220 },
  type: { type: String, default: 'bar' }, // 'bar' | 'line'
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
// Labels that fit: about one every 36px, always the latest one, never one squeezed in just before it
const labelStep = computed(() => Math.max(1, Math.ceil(props.data.length / Math.max(1, Math.floor(plotW.value / 36)))))
const showLabel = (i) => i === lastIndex.value || (i % labelStep.value === 0 && lastIndex.value - i >= labelStep.value)

// Line: through the middle of each band
const line = computed(() => (props.type === 'line' ? props.data.map((d, i) => `${i ? 'L' : 'M'}${x(i)},${y(d.value)}`).join(' ') : ''))
const ghostLine = computed(() => (props.type === 'line' && hasGhost.value ? props.data.map((d, i) => `${i ? 'L' : 'M'}${x(i)},${y(d.ghost ?? 0)}`).join(' ') : ''))
const area = computed(() => {
  if (props.type !== 'line' || !props.data.length) return ''
  const base = pad.top + plotH.value
  return `${line.value} L${x(lastIndex.value)},${base} L${x(0)},${base} Z`
})
</script>

<template>
  <div ref="el" class="viz relative select-none">
    <!-- Legend (2 series) -->
    <div v-if="hasGhost" class="mb-3 flex flex-wrap gap-x-4 gap-y-1 text-xs text-slate-600">
      <span class="flex items-center gap-1.5"><span v-if="type === 'line'" class="key-line" /><span v-else class="size-2.5 rounded-sm" style="background: var(--series-1)" /> {{ valueLabel }}</span>
      <span class="flex items-center gap-1.5"><span v-if="type === 'line'" class="key-line key-ghost" /><span v-else class="size-2.5 rounded-sm" style="background: var(--series-track)" /> {{ ghostLabel }}</span>
    </div>

    <svg class="block max-w-full" :width="width" :height="height" :viewBox="`0 0 ${width} ${height}`" role="img" :aria-label="`${valueLabel} over time, ${type === 'line' ? 'line' : 'bar'} graph`" :data-chart="type" @mouseleave="hover = null">
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

      <!-- line: a soft area under it, the target dashed -->
      <g v-if="type === 'line'">
        <path :d="area" fill="var(--series-1)" fill-opacity="0.12" />
        <path v-if="ghostLine" :d="ghostLine" fill="none" stroke="var(--viz-muted)" stroke-width="1.75" stroke-dasharray="4 4" />
        <path :d="line" fill="none" stroke="var(--series-1)" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round" />
      </g>

      <!-- columns (or the points of the line) -->
      <g v-for="(d, i) in data" :key="`${i}-${d.label}`">
        <template v-if="type === 'line'">
          <circle :cx="x(i)" :cy="y(d.value)" :r="hover === i ? 5 : data.length > 16 ? 2.2 : 3.4" fill="var(--color-white)" stroke="var(--series-1)" stroke-width="2" />
        </template>
        <template v-else>
          <path v-if="d.ghost" :d="colPath(i, d.ghost)" fill="var(--series-track)" />
          <path :d="colPath(i, d.value)" fill="var(--series-1)" :opacity="hover == null || hover === i ? 1 : 0.55" />
        </template>
        <text v-if="showLabel(i)" :x="x(i)" :y="height - 8" text-anchor="middle" class="tick" :class="i === lastIndex && 'tick-strong'">{{ d.label }}</text>
        <!-- value on the cap of the latest column (or above the latest point) only -->
        <text v-if="i === lastIndex && d.value" :x="x(i)" :y="(type === 'line' ? y(d.value) - 4 : y(Math.max(d.value, d.ghost ?? 0))) - 7" text-anchor="middle" class="cap">{{ tick(d.value) }}</text>
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
.key-line { display: inline-block; width: 0.95rem; border-top: 2.5px solid var(--series-1); border-radius: 2px; }
.key-ghost { border-top: 2px dashed var(--viz-muted); }
</style>
