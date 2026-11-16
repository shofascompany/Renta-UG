// Is the app running as an installed app (home-screen PWA, Android TWA / Play Store app, or an
// iPhone/Android wrapper) or just in a browser tab? In a browser, the first page is the landing site;
// inside the installed app the person goes straight to the app.
const KEY = 'renta.installed'

function detect() {
  try {
    const m = (q) => window.matchMedia?.(q).matches
    if (m('(display-mode: standalone)') || m('(display-mode: fullscreen)') || m('(display-mode: minimal-ui)')) return true
    if (window.navigator.standalone === true) return true // iPhone Home Screen app
    if (document.referrer.startsWith('android-app://')) return true // Play Store (Trusted Web Activity)
    if (window.Capacitor?.isNativePlatform?.()) return true // store app built with Capacitor
    if (new URLSearchParams(location.search).get('source') === 'pwa') return true // manifest start_url
  } catch {
    /* ignore */
  }
  return false
}

// Decided once at the start of the visit and remembered: the Play Store referrer is only there on the first load.
export function isInstalledApp() {
  try {
    if (sessionStorage.getItem(KEY) === '1') return true
    if (detect()) {
      sessionStorage.setItem(KEY, '1')
      return true
    }
  } catch {
    return detect()
  }
  return false
}
