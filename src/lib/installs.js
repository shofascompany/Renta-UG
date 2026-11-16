// Counts app installs for the main admin's Downloads page.
// A phone registers itself once with a random code (nothing personal), then just refreshes "last seen"
// at most once a day. Only the store apps count:
//   android → the Google Play app        ios → the App Store app
// The website in a browser tab, or added to the home screen, is never counted.
import { supabase } from '@/lib/supabase'

const ID_KEY = 'renta.device'
const SEEN_KEY = 'renta.device.seen'

function platform() {
  try {
    const cap = window.Capacitor
    if (cap?.isNativePlatform?.()) return cap.getPlatform?.() === 'ios' ? 'ios' : 'android'
    if (document.referrer.startsWith('android-app://') || sessionStorage.getItem('renta.store') === 'android') {
      sessionStorage.setItem('renta.store', 'android') // the Play Store referrer is only there on the first page
      return 'android'
    }
  } catch {
    /* ignore */
  }
  return null
}

export async function trackInstall() {
  try {
    const kind = platform()
    if (!kind) return
    const today = new Date().toISOString().slice(0, 10)
    if (localStorage.getItem(SEEN_KEY) === `${kind}:${today}`) return
    let id = localStorage.getItem(ID_KEY)
    if (!id) {
      id = (crypto.randomUUID?.() ?? `${Date.now()}${Math.random().toString(16).slice(2)}`).replace(/-/g, '')
      localStorage.setItem(ID_KEY, id)
    }
    const { error } = await supabase.rpc('register_install', { p_device: id, p_platform: kind })
    if (!error) localStorage.setItem(SEEN_KEY, `${kind}:${today}`)
  } catch {
    /* counting must never get in the way of the app */
  }
}
