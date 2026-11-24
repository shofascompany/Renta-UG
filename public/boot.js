// Runs before the app, in <head> (a file, not inline, so the Content Security Policy can block inline scripts).
// Follow the device's dark mode before the page paints (avoids a white flash). See src/lib/theme.js.
// The public pages (landing, sign in, sign up…) always stay light: same list as LIGHT_ONLY_PATHS in theme.js.
try {
  var lightOnly = ['/', '/login', '/signup', '/verify-email', '/forgot-password', '/reset-password', '/admin2026', '/privacy', '/terms', '/delete-account']
  var path = location.pathname.replace(/\/+$/, '') || '/'
  if (matchMedia('(prefers-color-scheme: dark)').matches && lightOnly.indexOf(path) === -1) {
    document.documentElement.classList.add('dark')
  }
} catch (e) {}
// Landing page only: start downloading the first hero photo now, alongside the app code,
// instead of waiting for the page to be built. Phones pick the small 760-px version.
try {
  if (location.pathname === '/') {
    var l = document.createElement('link')
    l.rel = 'preload'
    l.as = 'image'
    l.href = '/landing/kampala-homes.webp'
    l.setAttribute('imagesrcset', '/landing/kampala-homes-sm.webp 760w, /landing/kampala-homes.webp 1600w')
    l.setAttribute('imagesizes', '100vw')
    l.setAttribute('fetchpriority', 'high')
    document.head.appendChild(l)
  }
} catch (e) {}
