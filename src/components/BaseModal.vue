<script setup>
import { onBeforeUnmount, watch } from 'vue'
import { X } from '@lucide/vue'

const open = defineModel({ type: Boolean, default: false })
defineProps({ title: String, width: { type: String, default: 'max-w-lg' } })

function onKey(e) {
  if (e.key === 'Escape') open.value = false
}
watch(open, (v) => (v ? window.addEventListener('keydown', onKey) : window.removeEventListener('keydown', onKey)))
onBeforeUnmount(() => window.removeEventListener('keydown', onKey))
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition-opacity duration-150"
      leave-active-class="transition-opacity duration-100"
      enter-from-class="opacity-0"
      leave-to-class="opacity-0"
    >
      <div v-if="open" class="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-slate-900/30 p-4 sm:items-center">
        <div class="absolute inset-0" @click="open = false" />
        <div class="relative w-full rounded-xl bg-white shadow-xl" :class="width" role="dialog" aria-modal="true">
          <div class="flex items-center justify-between border-b border-slate-100 px-5 py-4">
            <h2 class="text-base font-semibold text-slate-900">{{ title }}</h2>
            <button class="btn-ghost -mr-2 px-2" aria-label="Close" @click="open = false">
              <X class="size-4" />
            </button>
          </div>
          <div class="p-5">
            <slot />
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
