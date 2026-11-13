// Light / dark mode follows the phone or computer setting automatically, and switches live
// when the device changes (e.g. automatic dark mode at night).
const media = typeof window !== 'undefined' ? window.matchMedia?.('(prefers-color-scheme: dark)') : null

function apply() {
  const dark = Boolean(media?.matches)
  document.documentElement.classList.toggle('dark', dark)
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', dark ? '#111925' : '#0f766e')
}

export function initTheme() {
  try {
    localStorage.removeItem('renta-theme') // old manual choice from an earlier version
  } catch {
    /* storage blocked */
  }
  apply()
  media?.addEventListener?.('change', apply)
}
