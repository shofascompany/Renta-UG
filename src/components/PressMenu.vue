<script setup>
import { ref } from 'vue'
import { useAnchoredMenu } from '@/composables/useAnchoredMenu'

// The menu of usePressMenu(): opens where the row was pressed, in the app's own menu design.
const props = defineProps({ menu: { type: Object, required: true }, label: { type: String, default: 'Options' } })
const anchor = ref(null)
const panel = ref(null)
const { style, upwards, close } = useAnchoredMenu(props.menu.open, anchor, panel, { align: 'left' })
</script>

<template>
  <Teleport to="body">
    <span ref="anchor" aria-hidden="true" class="pointer-events-none fixed size-0" :style="{ left: `${menu.at.value.x}px`, top: `${menu.at.value.y}px` }" />
    <Transition name="menu-pop">
      <div v-if="menu.open.value" ref="panel" class="menu-panel menu-from-left w-52" :class="upwards && 'menu-up'" :style="style" role="menu" :aria-label="label" @contextmenu.prevent>
        <div class="menu-scroll"><slot :item="menu.item.value" :close="close" /></div>
      </div>
    </Transition>
  </Teleport>
</template>
