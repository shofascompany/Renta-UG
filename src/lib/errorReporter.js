// Catches errors anywhere in the app. Fixes what it can by itself, and reports everything to the
// main admin (Health & settings → Errors reported), where the same error is grouped and counted.
//   • An old version of a page can't load after an update → reload once (fixes itself)
//   • Sign-in expired → refresh the session (fixes itself)
//   • Internet drops are not reported (they are the network, not a bug; requests already retry)
import { supabase } from './supabase'

const SENT = new Map() // message → time, so one error isn't sent over and over
const MAX_PER_SESSION = 25
let sent = 0

const STALE_CODE = /Failed to fetch dynamically imported module|Importing a module script failed|Loading (CSS )?chunk|error loading dynamically imported module/i
const EXPIRED = /JWT expired|invalid JWT|refresh token/i
const IGNORE = /ResizeObserver loop|Failed to fetch$|NetworkError|Load failed|network connection|internet|Network request failed|AbortError|The user aborted/i

let currentRoute = ''

export async function reportError(err, { area, autoFixed = false } = {}) {
  const message = String(err?.message ?? err ?? 'Unknown error').slice(0, 500)
  if (!message || IGNORE.test(message)) return
  const key = `${area}|${message}`
  if (Date.now() - (SENT.get(key) ?? 0) < 60_000 || sent >= MAX_PER_SESSION) return
  SENT.set(key, Date.now())
  sent++
  try {
    await supabase.rpc('report_error', {
      p_source: 'app',
      p_area: area || currentRoute || null,
      p_message: message,
      p_detail: err?.stack ? String(err.stack).slice(0, 3500) : null,
      p_url: location.pathname + location.search,
      p_user_agent: navigator.userAgent,
      p_auto_fixed: autoFixed,
    })
  } catch {
    /* reporting must never cause another error */
  }
}

// Try to fix the error. Returns true when it was handled.
async function heal(err) {
  const message = String(err?.message ?? err ?? '')
  if (STALE_CODE.test(message)) {
    // A new version was published while this page was open: load it (once, so it can't loop)
    if (!sessionStorage.getItem('renta.reloaded')) {
      sessionStorage.setItem('renta.reloaded', '1')
      await reportError(err, { autoFixed: true })
      location.reload()
      return true
    }
  }
  if (EXPIRED.test(message)) {
    const { error } = await supabase.auth.refreshSession()
    await reportError(err, { autoFixed: !error })
    return !error
  }
  return false
}

export function installErrorReporting(app, router) {
  router.afterEach((to) => {
    currentRoute = String(to.name ?? to.path)
    sessionStorage.removeItem('renta.reloaded') // a page loaded fine: allow another fix later
  })
  router.onError(async (err) => {
    if (!(await heal(err))) reportError(err, { area: `route ${currentRoute}` })
  })
  app.config.errorHandler = async (err, _instance, info) => {
    console.error(err)
    if (!(await heal(err))) reportError(err, { area: `${currentRoute} · ${info}` })
  }
  window.addEventListener('error', (e) => {
    if (e.error || e.message) heal(e.error ?? e.message).then((ok) => ok || reportError(e.error ?? e.message))
  })
  window.addEventListener('unhandledrejection', (e) => {
    heal(e.reason).then((ok) => ok || reportError(e.reason))
  })
}
