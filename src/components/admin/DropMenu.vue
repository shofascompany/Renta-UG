<script setup>
import { ref, watch } from 'vue'
import { useAnchoredMenu } from '@/composables/useAnchoredMenu'

// A button that opens a small menu next to it. Closes on outside tap, Escape, or when an item calls close().
//   <DropMenu align="right" title="Show">
//     <template #trigger="{ open }"> …button content… </template>
//     <template #default="{ close }"> …items: class "menu-item", optional "menu-ico" / "menu-sub"… </template>
//   </DropMenu>
const props = defineProps({
  align: { type: String, default: 'right' }, // which edge the menu lines up with
  width: { type: String, default: 'w-64' },
  label: { type: String, default: 'Open menu' },
  title: { type: String, default: '' }, // small heading inside the menu
  triggerClass: { type: String, default: '' },
})
const emit = defineEmits(['open']) // each time it opens (a menu with pages starts on its first one)
const open = ref(false)
const root = ref(null)
const panel = ref(null)
const { style, upwards, close } = useAnchoredMenu(open, root, panel, { align: props.align })
watch(open, (v) => v && emit('open'))
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
    <Teleport to="body">
      <Transition name="menu-pop">
        <div v-if="open" ref="panel" class="menu-panel" :class="[width, upwards && 'menu-up', align === 'left' ? 'menu-from-left' : 'menu-from-right']" :style="style" role="menu" :aria-label="label">
          <p v-if="title" class="menu-title">{{ title }}</p>
          <div class="menu-scroll"><slot :close="close" /></div>
        </div>
      </Transition>
    </Teleport>
  </div>
</template>
