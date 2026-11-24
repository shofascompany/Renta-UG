<script>
// Open sheets and dialogs, front one last
const stack = []
</script>

<script setup>
import { onBeforeUnmount, ref, watch } from 'vue'
import { X } from '@lucide/vue'

// Phones: a sheet that slides up from the bottom (thumb reach, drag the handle down to close).
// Computers: a centred dialog.
const open = defineModel({ type: Boolean, default: false })
// center: a card in the middle of the screen on phones too (instead of a bottom sheet)
const props = defineProps({ title: String, width: { type: String, default: 'max-w-lg' }, center: Boolean, top: Boolean, bare: Boolean })

const drag = ref(0)
// Several can be open at once (a question on top of a form): Escape closes the front one only, and the
// page behind scrolls again only when the last one has closed.
const me = {}
function onKey(e) {
  if (e.key === 'Escape' && stack.at(-1) === me) open.value = false
}
function leave() {
  const i = stack.indexOf(me)
  if (i >= 0) stack.splice(i, 1)
  window.removeEventListener('keydown', onKey)
  document.documentElement.style.overflow = stack.length ? 'hidden' : ''
}
watch(
  open,
  (v, was) => {
    if (v) {
      if (!stack.includes(me)) stack.push(me)
      window.addEventListener('keydown', onKey)
      document.documentElement.style.overflow = 'hidden'
    } else if (was) leave()
    drag.value = 0
  },
  { immediate: true },
)
onBeforeUnmount(leave)

// Drag-to-close on the handle / header
let startY = null
function down(e) {
  if (window.innerWidth >= 640 || props.center) return
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
      <div v-if="open" class="sheet-wrap fixed inset-0 flex justify-center" :class="[top ? 'z-[70]' : 'z-50', center ? 'is-center items-center p-4' : 'items-end sm:items-center sm:p-4']">
        <div class="sheet-backdrop absolute inset-0 bg-slate-900/45 backdrop-blur-[3px]" @click="open = false" />
        <div
          class="sheet-panel relative flex w-full flex-col overflow-hidden bg-white shadow-2xl"
          :class="[width, center ? 'max-h-[88dvh] rounded-3xl' : 'max-h-[92dvh] rounded-t-[1.75rem] sm:max-h-[88vh] sm:rounded-2xl']"
          :style="drag ? { transform: `translateY(${drag}px)`, transition: 'none' } : null"
          role="dialog"
          aria-modal="true"
          :aria-label="title"
        >
          <div
            v-if="!bare"
            class="shrink-0 touch-none select-none sm:touch-auto"
            @pointerdown="down"
            @pointermove="move"
            @pointerup="up"
            @pointercancel="up"
          >
            <div v-if="!center" class="mx-auto mt-2.5 h-1.5 w-11 rounded-full bg-slate-200 sm:hidden" />
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
/* centred card (and computers): gentle zoom */
.is-center.sheet-enter-from .sheet-panel,
.is-center.sheet-leave-to .sheet-panel {
  transform: translateY(10px) scale(0.95);
  opacity: 0;
}
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
