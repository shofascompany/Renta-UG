import { onBeforeUnmount, ref, watch } from 'vue'

// Every dropdown in the app: the panel is teleported to <body> and pinned to its button, so a card, sheet
// or coloured header can never cut it off or change its colours. It opens upwards when there is no room
// below, stays inside the screen, and works with the arrow keys, Home / End, Escape and Tab.
//   open    ref(boolean)          anchor, panel  template refs
//   align   'left' | 'right'      match          as wide as the button (form fields)
export function useAnchoredMenu(open, anchor, panel, { align = 'left', match = false } = {}) {
  const GAP = 8
  const EDGE = 10
  const style = ref({})
  const upwards = ref(false)
  const close = () => (open.value = false)

  function place() {
    const a = anchor.value?.getBoundingClientRect()
    const el = panel.value
    if (!a || !el) return
    const vw = document.documentElement.clientWidth
    const vh = window.visualViewport?.height ?? window.innerHeight // smaller while the phone keyboard is up
    if (a.bottom < 0 || a.top > vh) return close() // its button has scrolled away
    const width = match ? a.width : el.offsetWidth
    const left = Math.max(EDGE, Math.min(align === 'right' ? a.right - width : a.left, vw - width - EDGE))
    const below = vh - a.bottom - GAP - EDGE
    const above = a.top - GAP - EDGE
    const wanted = Math.min(el.scrollHeight, 360)
    upwards.value = below < wanted && above > below
    style.value = {
      left: `${left}px`,
      maxHeight: `${Math.max(120, Math.min(360, upwards.value ? above : below))}px`,
      ...(match ? { width: `${width}px` } : {}),
      ...(upwards.value ? { bottom: `${window.innerHeight - a.top + GAP}px` } : { top: `${a.bottom + GAP}px` }),
    }
  }

  function onPointer(e) {
    if (!anchor.value?.contains(e.target) && !panel.value?.contains(e.target)) close()
  }
  function onScroll(e) {
    if (!panel.value?.contains(e.target)) place()
  }
  function onKey(e) {
    if (e.key === 'Escape') {
      e.stopPropagation() // only the menu closes, not the sheet it is in
      close()
      anchor.value?.querySelector('button')?.focus()
    } else if (e.key === 'Tab') {
      close()
    } else if (['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(e.key)) {
      const typing = document.activeElement?.tagName === 'INPUT'
      if (typing && (e.key === 'Home' || e.key === 'End')) return
      const items = [...(panel.value?.querySelectorAll('[role="option"], .menu-item') ?? [])].filter((x) => !x.disabled)
      if (!items.length) return
      e.preventDefault()
      const at = items.indexOf(document.activeElement)
      const to = e.key === 'Home' ? 0 : e.key === 'End' ? items.length - 1 : e.key === 'ArrowDown' ? at + 1 : at < 0 ? items.length - 1 : at - 1
      items[(to + items.length) % items.length].focus()
    }
  }

  let listening = false
  function listen(on) {
    if (on === listening) return
    listening = on
    const f = on ? 'addEventListener' : 'removeEventListener'
    document[f]('pointerdown', onPointer, true)
    document[f]('keydown', onKey, true)
    window[f]('scroll', onScroll, true)
    window[f]('resize', place)
    window.visualViewport?.[f]('resize', place)
  }
  watch(
    open,
    (v) => {
      listen(v)
      if (v) place()
    },
    { flush: 'post' },
  )
  onBeforeUnmount(() => listen(false))

  return { style, upwards, place, close }
}
