// Phone notifications (Web Push): register the service worker, ask permission, and save this
// device so the server can send notifications to the phone's notification panel.
import { supabase, must } from './supabase'

const VAPID_PUBLIC_KEY = import.meta.env.VITE_VAPID_PUBLIC_KEY

export const pushSupported = () =>
  typeof window !== 'undefined' && 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window

// iPhones only allow notifications for apps added to the Home Screen
export const isIOS = () => /iphone|ipad|ipod/i.test(navigator.userAgent)
export const isStandalone = () =>
  window.matchMedia?.('(display-mode: standalone)').matches || window.navigator.standalone === true

export function registerServiceWorker() {
  if (!('serviceWorker' in navigator)) return
  navigator.serviceWorker.register('/sw.js').catch((e) => console.warn('Service worker not registered:', e))
}

function keyToBytes(base64) {
  const padded = (base64 + '='.repeat((4 - (base64.length % 4)) % 4)).replace(/-/g, '+').replace(/_/g, '/')
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0))
}

async function currentSubscription() {
  if (!pushSupported()) return null
  const reg = await navigator.serviceWorker.getRegistration('/')
  return reg ? reg.pushManager.getSubscription() : null
}

// 'unsupported' | 'needs-install' (iPhone not on Home Screen) | 'denied' | 'on' | 'off'
export async function pushStatus() {
  if (!pushSupported()) return isIOS() && !isStandalone() ? 'needs-install' : 'unsupported'
  if (!VAPID_PUBLIC_KEY) return 'unsupported'
  if (Notification.permission === 'denied') return 'denied'
  const sub = Notification.permission === 'granted' ? await currentSubscription() : null
  return sub ? 'on' : 'off'
}

// Asks permission (must be called from a tap/click) and registers this device for the signed-in user.
export async function enablePush() {
  if (!pushSupported() || !VAPID_PUBLIC_KEY) throw new Error('This browser cannot receive notifications.')
  const permission = await Notification.requestPermission()
  if (permission !== 'granted') throw new Error('Notifications were not allowed.')

  registerServiceWorker()
  const reg = await navigator.serviceWorker.ready
  let sub = await reg.pushManager.getSubscription()
  if (!sub) sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: keyToBytes(VAPID_PUBLIC_KEY) })

  const json = sub.toJSON()
  must(await supabase.rpc('save_push_subscription', { p_endpoint: json.endpoint, p_p256dh: json.keys.p256dh, p_auth: json.keys.auth }))
}

// Re-saves an existing subscription for whoever is signed in now (keeps it tied to the right account).
export async function refreshPushSubscription() {
  try {
    if (!pushSupported() || Notification.permission !== 'granted') return
    const sub = await currentSubscription()
    if (!sub) return
    const json = sub.toJSON()
    await supabase.rpc('save_push_subscription', { p_endpoint: json.endpoint, p_p256dh: json.keys.p256dh, p_auth: json.keys.auth })
  } catch {
    /* best effort */
  }
}

// Settings → Notifications: turn phone notifications off for this device.
export async function disablePush() {
  const sub = await currentSubscription()
  if (!sub) return
  must(await supabase.rpc('delete_push_subscription', { p_endpoint: sub.endpoint }))
  await sub.unsubscribe()
}

// On sign-out: stop sending this account's notifications to this device.
export async function disablePushForThisDevice() {
  try {
    const sub = await currentSubscription()
    if (sub) await supabase.rpc('delete_push_subscription', { p_endpoint: sub.endpoint })
  } catch {
    /* best effort */
  }
}
