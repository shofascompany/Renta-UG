// Light / dark mode follows the phone or computer setting automatically, and switches live
// when the device changes (e.g. automatic dark mode at night).
// Exception: the public pages (landing site, sign in, sign up and the other pages before signing in)
// are always light. Dark mode applies inside the app only. Keep this list in step with public/boot.js.
const media = typeof window !== 'undefined' ? window.matchMedia?.('(prefers-color-scheme: dark)') : null

export const LIGHT_ONLY_PATHS = [
  '/', '/login', '/signup', '/verify-email', '/forgot-password', '/reset-password', '/admin2026',
  '/privacy', '/terms', '/delete-account',
]
const lightOnly = (path) => LIGHT_ONLY_PATHS.includes((path || '/').replace(/\/+$/, '') || '/')

let currentPath = typeof window !== 'undefined' ? window.location.pathname : '/'

function apply() {
  const root = document.documentElement
  const dark = Boolean(media?.matches) && !lightOnly(currentPath)
  root.style.colorScheme = dark ? 'dark' : 'light'
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', dark ? '#000000' : '#0f766e')
  if (root.classList.contains('dark') === dark) return // already right (e.g. set by boot.js)

  // Switch instantly: without this, every button / card with a colour transition fades slowly
  // from one theme to the other, which looks like the page is lagging.
  root.classList.add('theme-switching')
  root.classList.toggle('dark', dark)
  void root.offsetHeight // apply the new colours now, while transitions are off
  requestAnimationFrame(() => requestAnimationFrame(() => root.classList.remove('theme-switching')))
}

// Called by the router after every page change
export function updateThemeForPath(path) {
  currentPath = path
  apply()
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
