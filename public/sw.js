// Renta UG service worker:
//   • shows notifications in the phone's notification panel
//   • keeps the app shell so it opens (and shows a friendly page) with no internet
// Pages are always fetched fresh when online, so the app is never out of date.
// Money, sign-in and database calls are never cached.

const VERSION = 'renta-v5' // a new number makes phones fetch the shell (offline page) again
const SHELL = ['/offline.html', '/icon-192.png', '/favicon.svg']

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(VERSION).then((c) => c.addAll(SHELL)).catch(() => {}))
  self.skipWaiting()
})
self.addEventListener('activate', (event) =>
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  ),
)

self.addEventListener('fetch', (event) => {
  const req = event.request
  if (req.method !== 'GET') return
  const url = new URL(req.url)
  if (url.origin !== self.location.origin) return // Supabase, fonts, etc.
  if (url.pathname.startsWith('/api/') || url.pathname.startsWith('/.netlify/')) return

  // Opening a page: network first; with no internet show the offline page
  if (req.mode === 'navigate') {
    event.respondWith(fetch(req).catch(() => caches.match('/offline.html')))
    return
  }
  // Built files have a fingerprint in their name, so they can be kept and reused
  if (url.pathname.startsWith('/assets/')) {
    event.respondWith(
      caches.match(req).then(
        (hit) =>
          hit ||
          fetch(req).then((res) => {
            if (res.ok) {
              const copy = res.clone()
              caches.open(VERSION).then((c) => c.put(req, copy))
            }
            return res
          }),
      ),
    )
  }
})
self.addEventListener('push', (event) => {
  let data = {}
  try {
    data = event.data ? event.data.json() : {}
  } catch {
    data = { body: event.data?.text() }
  }
  event.waitUntil(
    self.registration.showNotification('Renta UG', {
      body: data.body || '',
      icon: '/icon-192.png', // full-colour Renta logo
      badge: '/badge-96.png', // small status-bar icon (Android always shows this one in a single colour)
      timestamp: Date.now(),
      vibrate: [120, 60, 120],
      silent: false, // the phone's normal notification sound
      requireInteraction: false, // pops up, then goes to the notification centre by itself
      tag: data.tag, // same tag replaces an older notification instead of stacking
      renotify: Boolean(data.tag),
      data: { url: data.url || '/tenant/notifications' },
    }),
  )
})

// Tapping the notification opens (or focuses) the app on the right page
self.addEventListener('notificationclick', (event) => {
  event.notification.close()
  const url = new URL(event.notification.data?.url || '/', self.location.origin).href
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windows) => {
      for (const w of windows) {
        if (w.url.startsWith(self.location.origin) && 'focus' in w) {
          w.navigate(url)
          return w.focus()
        }
      }
      return self.clients.openWindow(url)
    }),
  )
})
