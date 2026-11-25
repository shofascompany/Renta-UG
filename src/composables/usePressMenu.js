import { ref } from 'vue'
import { useLongPress } from './useLongPress'

// Right click (computer) or press and hold (phone) on a row → a small menu at that spot (see PressMenu.vue).
//   const menu = usePressMenu()
//   <button v-bind="menu.row(item)" @click="menu.consumed() || open(item)">
//   <PressMenu :menu="menu"> <template #default="{ item, close }"> … </template> </PressMenu>
export function usePressMenu() {
  const open = ref(false)
  const item = ref(null)
  const at = ref({ x: 0, y: 0 })
  const show = (point, it) => {
    at.value = point
    item.value = it
    open.value = true
  }
  const lp = useLongPress(show)
  const row = (it) => ({
    class: 'press-row',
    onPointerdown: (e) => lp.start(e, it),
    onPointermove: lp.move,
    onPointerup: lp.cancel,
    onPointerleave: lp.cancel,
    onPointercancel: lp.cancel,
    onContextmenu: (e) => {
      e.preventDefault() // the browser's own menu (phones also send this while holding)
      lp.cancel()
      if (open.value && item.value === it) return
      const r = e.currentTarget.getBoundingClientRect()
      show(e.clientX || e.clientY ? { x: e.clientX, y: e.clientY } : { x: r.left + 24, y: r.top + 24 }, it)
    },
  })
  return { open, item, at, row, consumed: lp.consumed }
}
