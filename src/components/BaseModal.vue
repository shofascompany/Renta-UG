<script setup>
import { onBeforeUnmount, ref, watch } from 'vue'
import { X } from '@lucide/vue'

// Phones: a sheet that slides up from the bottom (thumb reach, drag the handle down to close).
// Computers: a centred dialog.
const open = defineModel({ type: Boolean, default: false })
defineProps({ title: String, width: { type: String, default: 'max-w-lg' } })

function onKey(e) {
  if (e.key === 'Escape') open.value = false
}
// Stop the page behind from scrolling while the sheet is open
function lock(v) {
  document.documentElement.style.overflow = v ? 'hidden' : ''
}
watch(open, (v) => {
  if (v) window.addEventListener('keydown', onKey)
  else window.removeEventListener('keydown', onKey)
  lock(v)
  drag.value = 0
})
onBeforeUnmount(() => {
  window.removeEventListener('keydown', onKey)
  lock(false)
})

// Drag-to-close on the handle / header
const drag = ref(0)
let startY = null
function down(e) {
  if (window.innerWidth >= 640) return
  startY = e.clientY
}
function move(e) {
  if (startY === null) return
  drag.value = Math.max(0, e.clientY - startY)
}
function up() {
  if (startY === null) return
  if (drag.value > 110) open.value = false
  else drag.value = 0
  startY = null
}
</script>

<template>
  <Teleport to="body">
    <Transition name="sheet">
      <div v-if="open" class="sheet-wrap fixed inset-0 z-50 flex items-end justify-center sm:items-center sm:p-4">
        <div class="sheet-backdrop absolute inset-0 bg-slate-900/40 backdrop-blur-[2px]" @click="open = false" />
        <div
          class="sheet-panel relative flex max-h-[92dvh] w-full flex-col rounded-t-[1.75rem] bg-white shadow-2xl sm:max-h-[88vh] sm:rounded-2xl"
          :class="width"
          :style="drag ? { transform: `translateY(${drag}px)`, transition: 'none' } : null"
          role="dialog"
          aria-modal="true"
          :aria-label="title"
        >
          <div
            class="shrink-0 touch-none select-none sm:touch-auto"
            @pointerdown="down"
            @pointermove="move"
            @pointerup="up"
            @pointercancel="up"
          >
            <div class="mx-auto mt-2.5 h-1.5 w-11 rounded-full bg-slate-200 sm:hidden" />
            <div class="flex items-center justify-between gap-3 border-b border-slate-100 px-5 pt-3 pb-3.5 sm:pt-4">
              <h2 class="text-[17px] font-semibold text-slate-900 sm:text-base">{{ title }}</h2>
              <button class="flex size-10 items-center justify-center rounded-full bg-slate-100 text-slate-600 hover:bg-slate-200 sm:size-8 sm:bg-transparent" aria-label="Close" @click="open = false">
                <X class="size-[1.1rem] sm:size-4" />
              </button>
            </div>
          </div>
          <div class="sheet-body overflow-y-auto overscroll-contain p-5 pb-[max(1.25rem,env(safe-area-inset-bottom))]">
            <slot />
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.sheet-panel {
  transition: transform 0.3s cubic-bezier(0.22, 1, 0.36, 1);
}
.sheet-enter-active,
.sheet-leave-active {
  transition: opacity 0.25s ease;
}
.sheet-enter-active .sheet-panel,
.sheet-leave-active .sheet-panel {
  transition: transform 0.32s cubic-bezier(0.22, 1, 0.36, 1), opacity 0.2s ease;
}
.sheet-enter-from,
.sheet-leave-to {
  opacity: 0;
}
/* phones: slide up from the bottom */
.sheet-enter-from .sheet-panel,
.sheet-leave-to .sheet-panel {
  transform: translateY(100%);
}
/* computers: gentle zoom */
@media (min-width: 640px) {
  .sheet-enter-from .sheet-panel,
  .sheet-leave-to .sheet-panel {
    transform: translateY(8px) scale(0.98);
    opacity: 0;
  }
}
@media (prefers-reduced-motion: reduce) {
  .sheet-panel,
  .sheet-enter-active .sheet-panel,
  .sheet-leave-active .sheet-panel {
    transition: none;
  }
}
</style>
