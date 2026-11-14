// Sends new notifications to phones via Web Push:
//   • tenant notifications (messages, reminders, payment receipts) → the tenant's devices
//   • staff inbox (landlords, main admin: e.g. "payment received") → that user's devices
// Polls instead of relying on a live connection, so nothing is missed when the internet drops:
// each row is "claimed" once (pushed_at set) and delivered to all of the person's devices.
import * as webpush from 'web-push'

const EVERY_MS = 10_000
const TAGS = { reminder: 'lease-reminder', rent_due: 'rent-due', status: 'rent-status' }
const TO_PAYMENTS = new Set(['payment', 'rent_due', 'status'])

// Every phone notification is titled "Renta UG"; the stored title is the sender line
// ("From John Mukasa (Landlord)", "Rent reminder", …) and leads the message.
const brand = (n) => ({ title: 'Renta UG', body: `${n.title}: ${n.body}` })
const CATCH_UP = 24 * 60 * 60 * 1000 // also deliver anything from the last day after a restart

// Sets the keys once. Returns false when phone notifications aren't set up.
function configure(env) {
  const publicKey = env.VITE_VAPID_PUBLIC_KEY
  const privateKey = env.VAPID_PRIVATE_KEY
  if (!publicKey || !privateKey) return false
  webpush.setVapidDetails(env.VAPID_SUBJECT || 'mailto:admin@example.com', publicKey, privateKey)
  return true
}

// One round: send every new notification and inbox message to the person's phones.
// Used every 10 s by the local server, and every minute by the Netlify scheduled function.
export async function sendPendingPush(db, env = process.env) {
  if (!db || !configure(env)) return 0
  let sent = 0
  for (const n of await claim(db, 'notifications', 'id, tenant_id, title, body, type')) {
    const { data: t } = await db.from('tenants').select('user_id').eq('id', n.tenant_id).maybeSingle()
    if (!t?.user_id) continue // tenant hasn't connected an account
    await deliver(db, t.user_id, {
      ...brand(n),
      tag: TAGS[n.type] ?? n.id, // repeat reminders replace the older one instead of stacking
      url: TO_PAYMENTS.has(n.type) ? '/tenant/payments' : n.type === 'security' ? '/tenant/settings/password' : '/tenant/notifications',
    })
    sent++
  }
  for (const n of await claim(db, 'staff_notifications', 'id, user_id, title, body, url')) {
    await deliver(db, n.user_id, { ...brand(n), tag: n.id, url: n.url || '/' })
    sent++
  }
  return sent
}

export function startPushSender(db, env = process.env) {
  if (!db || !configure(env)) {
    console.log('  push:     disabled (VAPID keys missing)')
    return
  }
  console.log('  push:     enabled')
  let running = false
  async function tick() {
    if (running) return
    running = true
    try {
      await sendPendingPush(db, env)
    } catch (e) {
      console.warn(`[push] ${e.message}`)
    } finally {
      running = false
    }
  }
  tick()
  setInterval(tick, EVERY_MS)
}

// Atomically mark unsent rows as sent and return them
async function claim(db, table, columns) {
  const { data, error } = await db
    .from(table)
    .update({ pushed_at: new Date().toISOString() })
    .is('pushed_at', null)
    .gte('created_at', new Date(Date.now() - CATCH_UP).toISOString())
    .select(columns)
  if (error) throw new Error(`${table}: ${error.message}`)
  return data ?? []
}

async function deliver(db, userId, message) {
  const { data: subs } = await db.from('push_subscriptions').select('id, endpoint, p256dh, auth').eq('user_id', userId)
  const payload = JSON.stringify(message)
  for (const s of subs ?? []) {
    try {
      await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload, { TTL: 86400 })
    } catch (e) {
      if (e.statusCode === 404 || e.statusCode === 410) {
        await db.from('push_subscriptions').delete().eq('id', s.id) // phone unsubscribed / app removed
      } else {
        console.warn(`[push] could not reach a device: ${e.statusCode ?? ''} ${e.message}`)
      }
    }
  }
}
