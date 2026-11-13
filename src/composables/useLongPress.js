// Press-and-hold detection that works for touch, pen and mouse.
// Usage on an element:
//   @pointerdown="lp.start($event, item)" @pointermove="lp.move" @pointerup="lp.cancel"
//   @pointerleave="lp.cancel" @pointercancel="lp.cancel" @click="lp.consumed() || onTap(item)"
export function useLongPress(onLongPress, { delay = 500, tolerance = 10 } = {}) {
  let timer = null
  let origin = null
  let fired = false

  function start(event, payload) {
    if (event.button !== undefined && event.button !== 0) return // primary button / touch only
    fired = false
    origin = { x: event.clientX, y: event.clientY }
    clearTimeout(timer)
    timer = setTimeout(() => {
      fired = true
      navigator.vibrate?.(15) // small haptic tick on phones that support it
      onLongPress({ x: origin.x, y: origin.y }, payload)
    }, delay)
  }

  function move(event) {
    if (origin && Math.hypot(event.clientX - origin.x, event.clientY - origin.y) > tolerance) cancel()
  }

  function cancel() {
    clearTimeout(timer)
    origin = null
  }

  // Call from @click: returns true (and resets) if this click ended a long press,
  // so the normal tap action is skipped.
  function consumed() {
    const was = fired
    fired = false
    return was
  }

  return { start, move, cancel, consumed }
}
