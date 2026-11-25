// Counts for the main admin (Downloads & visits). Everything goes to the database the moment it happens.
//   • VISIT      the official website is opened, on any system. Signing in there is part of the visit.
//                iPhone, Windows and Mac are always visits, also from a home-screen or desktop shortcut.
//   • DOWNLOAD   an account signs in inside the ANDROID APP (installed from the website, or from Google Play).
//   • INSTALLED  Android says the app was installed, but nobody has signed in there yet.
// Never counted: a test copy, a preview link, localhost, search robots and the main admin.
import { watch } from 'vue'
import { supabase } from '@/lib/supabase'
import { insideApp, onInstallEvent } from '@/lib/installApp'
import { deviceName } from '@/lib/device'
import { SITE } from '@/lib/site'

const ID_KEY = 'renta.device'
const APP_KEY = 'renta.app.seen'
const INSTALL_KEY = 'renta.web.seen'
const VISIT_KEY = 'renta.visit'
const VISIT_USER_KEY = 'renta.visit.user'
const VISIT_GAP = 30 * 60_000
// A link opened from another app (WhatsApp…) also has an "android-app://" referrer: only ours is the Play Store app
const PLAY_APP = 'android-app://ug.renta.app'

const official = () => window.location.origin === SITE.url
const today = () => new Date().toLocaleDateString('en-CA')

export function systemName(nav = navigator) {
  const ua = nav.userAgent ?? ''
  if (/Android/i.test(ua)) return 'android'
  if (/iP(hone|ad|od)/.test(ua) || (/Mac/.test(ua) && nav.maxTouchPoints > 1)) return 'ios'
  if (/Windows/i.test(ua)) return 'windows'
  return /Mac/.test(ua) ? 'mac' : 'other'
}

// Inside the Android app? 'play' | 'website' | null (a browser, or another system)
export function androidApp() {
  try {
    if (systemName() !== 'android') return null
    if (window.Capacitor?.isNativePlatform?.()) return 'play'
    if (document.referrer.startsWith(PLAY_APP) || sessionStorage.getItem('renta.play') === '1') {
      sessionStorage.setItem('renta.play', '1') // the Play Store referrer is only there on the first page
      return 'play'
    }
    return insideApp() && official() ? 'website' : null
  } catch {
    return null
  }
}

function deviceCode() {
  let id = localStorage.getItem(ID_KEY)
  if (!id) {
    id = (crypto.randomUUID?.() ?? `${Date.now()}${Math.random().toString(16).slice(2)}`).replace(/-/g, '')
    localStorage.setItem(ID_KEY, id)
  }
  return id
}

// Counting must never get in the way of the app
const quietly = (fn) => async (...args) => {
  try {
    await fn(...args)
  } catch {
    /* offline or storage blocked: the next page tries again */
  }
}

// An account signed in inside the app (told again once a day, so "last used" stays true)
const countDownload = quietly(async (userId) => {
  const source = androidApp()
  if (!source || !userId) return
  const mark = `${userId}:${today()}`
  if (localStorage.getItem(APP_KEY) === mark) return
  localStorage.setItem(APP_KEY, mark)
  const { error } = await supabase.rpc('register_app_sign_in', { p_device: deviceCode(), p_source: source, p_name: await deviceName() })
  if (error) localStorage.removeItem(APP_KEY)
})

// Installed on this phone, whether or not anyone signs in (justInstalled = the browser has just said so)
const countInstalled = quietly(async (justInstalled = false) => {
  if (!official() || systemName() !== 'android' || (!justInstalled && androidApp() !== 'website')) return
  if (localStorage.getItem(INSTALL_KEY) === today()) return
  const { error } = await supabase.rpc('register_web_install', { p_device: deviceCode(), p_platform: 'android' })
  if (!error) localStorage.setItem(INSTALL_KEY, today())
})

let visiting = Promise.resolve() // one at a time, so opening and signing in never count twice
const countVisit = quietly(async (userId) => {
  if (!official() || document.visibilityState === 'hidden' || androidApp() || window.location.pathname.startsWith('/admin2026')) return
  if (navigator.webdriver || /bot|crawl|spider|lighthouse|headless|preview/i.test(navigator.userAgent)) return
  const now = Date.now()
  const last = Number(localStorage.getItem(VISIT_KEY)) || 0
  const before = localStorage.getItem(VISIT_USER_KEY) ?? ''
  const isNew = now - last >= VISIT_GAP
  const signedIn = Boolean(userId) && userId !== before
  localStorage.setItem(VISIT_KEY, String(now))
  if (!userId && before) localStorage.setItem(VISIT_USER_KEY, '') // signed out: signing in again is noted again
  if (!isNew && !signedIn) return
  if (userId) localStorage.setItem(VISIT_USER_KEY, userId)
  const { error } = await supabase.rpc('record_visit', { p_visitor: deviceCode(), p_system: systemName(), p_device: await deviceName(), p_new: isNew })
  if (!error) return
  // Not saved (e.g. offline): the next page tries again
  if (isNew) localStorage.setItem(VISIT_KEY, String(last))
  localStorage.setItem(VISIT_USER_KEY, before)
})

// Started once from main.js. Not on a developer's computer.
export function startCounting(router, auth) {
  if (import.meta.env.DEV) return
  const user = () => (auth.isAuthenticated && auth.profile && !auth.isSuperadmin ? auth.session.user.id : null)
  const count = () => {
    if (auth.isSuperadmin) return
    countDownload(user())
    visiting = visiting.then(() => countVisit(user()))
  }
  countInstalled()
  onInstallEvent((what) => what === 'installed' && countInstalled(true))
  router.isReady().then(() => {
    count()
    router.afterEach(count)
    document.addEventListener('visibilitychange', count)
    window.addEventListener('online', count)
    watch(user, count) // signed in or out
  })
}
