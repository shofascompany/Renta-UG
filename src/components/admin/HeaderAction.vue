<script setup>
import { onBeforeUnmount, ref } from 'vue'

// The round "Add tenant" style button for page headers: an icon in the header card; its words show
// on hover / keyboard focus (and for 5 s when the page opens, if `intro`). Computers always show the words.
//   variant "solid": the main action (teal on computers).  "soft": a quieter action such as Edit.
const props = defineProps({
  icon: { type: [Object, Function], required: true },
  label: { type: String, required: true },
  variant: { type: String, default: 'solid' },
  intro: Boolean,
  disabled: Boolean,
})
const open = ref(props.intro)
const timer = props.intro ? setTimeout(() => (open.value = false), 5000) : null
onBeforeUnmount(() => clearTimeout(timer))
</script>

<template>
  <button type="button" class="head-act" :class="[`head-act-${variant}`, open && 'head-act-open']" :aria-label="label" :disabled="disabled">
    <component :is="icon" class="size-[1.35rem]" stroke-width="2.25" />
    <span class="head-act-label">{{ label }}</span>
  </button>
</template>

<style scoped>
.head-act {
  --color-white: #fff;
  display: inline-flex;
  height: 3rem;
  min-width: 3rem;
  align-items: center;
  justify-content: center;
  gap: 0;
  border-radius: 1rem;
  padding: 0 0.8rem;
  font-size: 0.9rem;
  font-weight: 600;
  color: #0a3b38;
  background: #fff;
  box-shadow: 0 10px 22px -10px rgb(0 0 0 / 0.45);
  transition: transform 0.15s ease, gap 0.25s ease, background-color 0.15s ease;
}
.head-act:active { transform: scale(0.95); }
.head-act:disabled { opacity: 0.6; }
.head-act-label {
  max-width: 0;
  overflow: hidden;
  white-space: nowrap;
  opacity: 0;
  transition: max-width 0.3s cubic-bezier(0.22, 1, 0.36, 1), opacity 0.2s ease;
}
.head-act:hover, .head-act:focus-visible, .head-act-open { gap: 0.5rem; }
.head-act:hover .head-act-label, .head-act:focus-visible .head-act-label, .head-act-open .head-act-label { max-width: 9rem; opacity: 1; }

@media (min-width: 1024px) {
  .head-act { height: 2.75rem; gap: 0.5rem; padding: 0 1.1rem 0 0.95rem; }
  .head-act-label { max-width: none; opacity: 1; }
  .head-act-solid { color: #fff; background: var(--color-brand-600); box-shadow: 0 8px 18px -10px rgb(15 118 110 / 0.7); }
  .head-act-solid:hover { background: var(--color-brand-700); }
  .head-act-soft { color: var(--color-slate-700); background: var(--color-white); box-shadow: inset 0 0 0 1px var(--color-slate-200); }
  .head-act-soft:hover { background: var(--color-slate-50); }
}
</style>
