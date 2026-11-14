<script setup>
import { ArrowUpRight } from '@lucide/vue'

// Gradient KPI tile for the main admin. Pass `to` to make it a link.
//   glass = for use INSIDE a SuperHero (translucent white on the dark gradient)
defineProps({
  label: String,
  value: [String, Number],
  hint: String,
  icon: [Object, Function],
  tile: { type: String, default: 'tile-teal' },
  to: { type: [String, Object], default: null },
  glass: Boolean,
  alert: Boolean, // amber accent when something needs attention
})
</script>

<template>
  <component
    :is="to ? 'RouterLink' : 'div'"
    :to="to || undefined"
    class="stat group relative block overflow-hidden rounded-2xl p-4 transition"
    :class="[glass ? 'glass' : 'solid', to && 'link', alert && 'is-alert']"
  >
    <div class="flex items-start justify-between gap-3">
      <span v-if="icon" class="icon-tile size-10 rounded-xl" :class="tile"><component :is="icon" class="size-5" /></span>
      <ArrowUpRight v-if="to" class="arrow size-4.5 transition group-hover:-translate-y-0.5 group-hover:translate-x-0.5" />
    </div>
    <p class="label mt-3 text-xs font-semibold tracking-wide uppercase">{{ label }}</p>
    <p class="value mt-0.5 truncate text-[1.45rem] leading-tight font-bold tracking-tight tabular-nums">{{ value }}</p>
    <p v-if="hint" class="hint mt-0.5 truncate text-xs">{{ hint }}</p>
  </component>
</template>

<style scoped>
.solid {
  border: 1px solid var(--color-slate-200);
  background:
    radial-gradient(120% 90% at 100% 0%, var(--color-brand-50) 0%, transparent 55%),
    var(--color-white);
  box-shadow: 0 1px 2px rgb(15 23 42 / 0.04), 0 12px 30px -24px rgb(15 23 42 / 0.4);
}
.solid .label { color: var(--color-slate-500); }
.solid .value { color: var(--color-slate-900); }
.solid .hint, .solid .arrow { color: var(--color-slate-400); }
.solid.is-alert {
  border-color: var(--color-amber-200);
  background: radial-gradient(120% 90% at 100% 0%, var(--color-amber-50) 0%, transparent 60%), var(--color-white);
}
.solid.is-alert .value { color: var(--color-amber-700); }

.glass {
  --color-white: #fff;
  color: #fff;
  background: rgb(255 255 255 / 0.09);
  box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.14);
  backdrop-filter: blur(6px);
}
.glass .label { color: rgb(255 255 255 / 0.65); }
.glass .hint, .glass .arrow { color: rgb(255 255 255 / 0.6); }
.glass.is-alert { box-shadow: inset 0 0 0 1px rgb(251 191 36 / 0.55); }
.glass.is-alert .value { color: #fde68a; }

.link:hover { transform: translateY(-2px); }
.solid.link:hover { box-shadow: 0 16px 34px -20px rgb(15 23 42 / 0.45); }
.glass.link:hover { background: rgb(255 255 255 / 0.15); }
.link:active { transform: scale(0.98); }
</style>
