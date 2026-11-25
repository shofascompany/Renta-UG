// Installing the Renta app from the browser (ANDROID ONLY), and moving the person into it.
//   • Android Chrome / Edge / Samsung Internet say when the app can be installed (beforeinstallprompt) and when
//     it was (appinstalled). Every other system (iPhone, Windows, Mac…) simply uses the website.
//   • The browser always asks the person to confirm the install: a page cannot skip that question, and it does
//     not tell the page how many bytes are downloaded, only when it starts and when it is done.
// Started once from main.js, so the event is caught however early it fires.

const FLAG = 'renta.installedApp' // the browser reported the app was installed on this device
const ONLY = 'renta.appOnly'
const DEVICE = 'renta.linkDevice'
let deferred = null
const listeners = new Set()
const tell = (what) => listeners.forEach((fn) => fn(what))

const read = (key) => {
  try {
    return localStorage.getItem(key)
  } catch {
    return null
  }
}
const write = (key, value) => {
  try {
    if (value === null) localStorage.removeItem(key)
    else localStorage.setItem(key, value)
  } catch {
    /* storage blocked */
  }
}

export const isAndroid = () => {
  try {
    return /Android/i.test(navigator.userAgent) || navigator.userAgentData?.platform === 'Android'
  } catch {
    return false
  }
}

// Really inside the installed app? Stricter than isInstalledApp() (lib/runtime.js): a link opened FROM another
// app, such as WhatsApp, also has an "android-app://" referrer, and that is still the browser.
export function insideApp() {
  try {
    const m = (q) => window.matchMedia?.(q).matches
    if (m('(display-mode: standalone)') || m('(display-mode: fullscreen)') || m('(display-mode: minimal-ui)')) return true
    return window.navigator.standalone === true || Boolean(window.Capacitor?.isNativePlatform?.())
  } catch {
    return false
  }
}

export function watchInstall() {
  if (typeof window === 'undefined') return
  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault() // keep it: the Install button uses it
    deferred = e
    write(FLAG, null) // it can be installed, so it is not on this phone (any more)
    tell('available')
  })
  window.addEventListener('appinstalled', () => {
    deferred = null
    write(FLAG, '1')
    tell('installed')
  })
}

export const onInstallEvent = (fn) => {
  listeners.add(fn)
  return () => listeners.delete(fn)
}
export const canInstallNow = () => Boolean(deferred)

// true = the browser confirms the app is on this phone; false = it says no; null = it can't tell
export async function confirmedInstalled() {
  if (typeof navigator.getInstalledRelatedApps !== 'function') return null
  try {
    return (await navigator.getInstalledRelatedApps()).length > 0
  } catch {
    return null
  }
}
export const rememberedInstalled = () => read(FLAG) === '1'

// Shows the browser's install question; resolves 'accepted' | 'dismissed' | 'unavailable'
export async function promptInstall() {
  if (!deferred) return 'unavailable'
  const ev = deferred
  deferred = null
  await ev.prompt()
  const { outcome } = await ev.userChoice
  return outcome
}

// Waits a few seconds for the browser to say the app can be installed (it fires shortly after the page loads)
export function waitForInstallable(ms = 3000) {
  if (deferred) return Promise.resolve(true)
  return new Promise((resolve) => {
    let timer = null
    const stop = onInstallEvent((what) => {
      if (what !== 'available') return
      stop()
      clearTimeout(timer)
      resolve(true)
    })
    timer = setTimeout(() => {
      stop()
      resolve(false)
    }, ms)
  })
}

// A link that hands this page over to the installed app. If Android finds no app for it, it comes back to the
// same page in the browser.
export function openInAppUrl(path = '/') {
  const u = new URL(path, window.location.origin)
  if (!isAndroid()) return u.href
  return `intent://${u.host}${u.pathname}${u.search}#Intent;scheme=${u.protocol.replace(':', '')};action=android.intent.action.VIEW;category=android.intent.category.BROWSABLE;S.browser_fallback_url=${encodeURIComponent(u.href)};end`
}

// ── Invite link (Android): the account is used in the app, not in the browser ──
export const setAppOnly = () => write(ONLY, '1')
export const clearAppOnly = () => write(ONLY, null)
export const appOnlyDevice = () => isAndroid() && read(ONLY) === '1' && !insideApp()

// "Sign in to a different account" on the install page: this tab may open the sign-in page, so a landlord who
// opens an invite link on their own phone is never locked out. (Tenants are still sent to the app: see the router.)
const OTHER = 'renta.otherAccount'
export const allowOtherAccount = () => {
  try {
    sessionStorage.setItem(OTHER, '1')
  } catch {
    /* storage blocked */
  }
}
export const otherAccountAllowed = () => {
  try {
    return sessionStorage.getItem(OTHER) === '1'
  } catch {
    return false
  }
}

// A random number for this browser, so a one-time link still works if the same phone opens it again
export function deviceId() {
  let id = read(DEVICE)
  if (!id || !/^[\w-]{16,64}$/.test(id)) {
    id = [...crypto.getRandomValues(new Uint8Array(18))].map((b) => b.toString(16).padStart(2, '0')).join('')
    write(DEVICE, id)
  }
  return id
}
