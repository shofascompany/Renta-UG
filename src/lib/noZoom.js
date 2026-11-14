// Keeps every page at the phone's own size: no pinch zoom, no double-tap zoom, no sideways drift.
// (iPhones ignore "user-scalable=no" in the viewport tag, so their zoom gestures are blocked here.)
export function installNoZoom() {
  if (typeof document === 'undefined') return
  const stop = (e) => e.preventDefault()

  // iOS Safari pinch gestures
  document.addEventListener('gesturestart', stop, { passive: false })
  document.addEventListener('gesturechange', stop, { passive: false })
  document.addEventListener('gestureend', stop, { passive: false })

  // Two-finger pinch on other browsers
  document.addEventListener(
    'touchmove',
    (e) => {
      if (e.touches.length > 1) e.preventDefault()
    },
    { passive: false },
  )

  // Double-tap zoom on plain text/backgrounds (buttons, links and fields already avoid it via CSS
  // touch-action, and must keep receiving fast repeated taps)
  let lastTap = 0
  document.addEventListener(
    'touchend',
    (e) => {
      const now = Date.now()
      const interactive = e.target.closest?.('a, button, input, textarea, select, label, [role="button"], [contenteditable]')
      if (now - lastTap < 300 && !interactive) e.preventDefault()
      lastTap = now
    },
    { passive: false },
  )

  // Ctrl + wheel / trackpad pinch on computers in phone-size windows
  window.addEventListener(
    'wheel',
    (e) => {
      if (e.ctrlKey) e.preventDefault()
    },
    { passive: false },
  )

  // If the page ever gets scrolled sideways (e.g. by focusing a field), snap it back
  window.addEventListener('scroll', () => {
    if (window.scrollX !== 0) window.scrollTo(0, window.scrollY)
  }, { passive: true })
}
