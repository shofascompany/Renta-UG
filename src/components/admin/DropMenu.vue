<script setup>
import { onBeforeUnmount, ref, watch } from 'vue'

// A button that opens a small menu under it. Closes on outside tap, Escape, or when an item calls close().
//   <DropMenu align="right">
//     <template #trigger="{ open }"> …button content… </template>
//     <template #default="{ close }"> …items… </template>
//   </DropMenu>
const props = defineProps({
  align: { type: String, default: 'right' }, // which edge the menu lines up with
  width: { type: String, default: 'w-64' },
  label: { type: String, default: 'Open menu' },
  triggerClass: { type: String, default: '' },
})
const open = ref(false)
const root = ref(null)

const close = () => (open.value = false)
function outside(e) {
  if (root.value && !root.value.contains(e.target)) close()
}
function key(e) {
  if (e.key === 'Escape') close()
}
watch(open, (v) => {
  if (v) {
    document.addEventListener('pointerdown', outside, true)
    document.addEventListener('keydown', key)
  } else {
    document.removeEventListener('pointerdown', outside, true)
    document.removeEventListener('keydown', key)
  }
})
onBeforeUnmount(close)
</script>

<template>
  <div ref="root" class="relative">
    <button
      type="button"
      :class="triggerClass"
      :aria-label="label"
      aria-haspopup="menu"
      :aria-expanded="open"
      @click="open = !open"
    >
      <slot name="trigger" :open="open" />
    </button>
    <Transition
      enter-active-class="transition duration-150 ease-out"
      enter-from-class="opacity-0 -translate-y-1 scale-95"
      leave-active-class="transition duration-100 ease-in"
      leave-to-class="opacity-0 -translate-y-1 scale-95"
    >
      <div
        v-if="open"
        class="absolute top-full z-40 mt-2 max-w-[calc(100vw-2rem)] origin-top overflow-hidden rounded-2xl border border-slate-200 bg-white p-1.5 shadow-[0_18px_40px_-14px_rgb(15_23_42/0.35)]"
        :class="[width, props.align === 'left' ? 'left-0' : 'right-0']"
        role="menu"
      >
        <slot :close="close" />
      </div>
    </Transition>
  </div>
</template>
