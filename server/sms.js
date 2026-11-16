// Text messages (SMS) when a LANDLORD confirms (or rejects) a cash payment.
// Every tenant with a phone number gets one: those without a smartphone (who never see the app) and
// those with the app (who also get the normal in-app / phone notification). Online mobile money
// payments are not texted: the network already sends its own SMS for those.
// Works like the phone-notification sender: it polls for new payment notifications, claims each one once
// (sms_sent_at) and sends it. Uses Africa's Talking, which sends to MTN and Airtel numbers in Uganda.
import { normalizeUgPhone } from './momo.js'

const EVERY_MS = 10_000
const CATCH_UP = 6 * 60 * 60 * 1000 // after a restart, still send what is from the last 6 hours
const MAX_LENGTH = 300 // two SMS parts

export const smsEnabled = (env = process.env) => Boolean(env.AT_USERNAME && env.AT_API_KEY)

// Sends one text. `to` is any Ugandan number. Throws a readable error when it fails.
export async function sendSms(to, message, env = process.env) {
  if (!smsEnabled(env)) throw new Error('SMS is not set up (add AT_USERNAME and AT_API_KEY).')
  const local = normalizeUgPhone(to)
  if (!local) throw new Error('That is not a valid Ugandan phone number.')
  const sandbox = env.AT_USERNAME === 'sandbox'
  const res = await fetch(`https://api${sandbox ? '.sandbox' : ''}.africastalking.com/version1/messaging`, {
    method: 'POST',
    headers: { apiKey: env.AT_API_KEY, Accept: 'application/json', 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      username: env.AT_USERNAME,
      to: `+${local}`,
      message,
      ...(env.AT_SENDER_ID ? { from: env.AT_SENDER_ID } : {}),
    }),
  })
  const text = await res.text()
  let json = {}
  try { json = JSON.parse(text) } catch { /* not JSON: handled below */ }
  if (!res.ok) throw new Error(`SMS provider said ${res.status}: ${text.slice(0, 200)}`)
  const r = json?.SMSMessageData?.Recipients?.[0]
  if (!r || !/success|sent|queued/i.test(`${r.status}`) ) {
    throw new Error(`SMS not accepted: ${r?.status ?? json?.SMSMessageData?.Message ?? 'unknown reason'}`)
  }
}

const shorten = (s) => (s.length > MAX_LENGTH ? `${s.slice(0, MAX_LENGTH - 1).trimEnd()}…` : s)

// One round: text every new cash confirmation / rejection to the tenant it is for.
export async function sendPendingSms(db, env = process.env) {
  if (!db || !smsEnabled(env)) return 0
  const { data: rows, error } = await db
    .from('notifications')
    .update({ sms_sent_at: new Date().toISOString() })
    .is('sms_sent_at', null)
    .eq('type', 'payment')
    .ilike('body', '%cash payment%') // written by the database when the landlord confirms or rejects cash
    .gte('created_at', new Date(Date.now() - CATCH_UP).toISOString())
    .select('id, tenant_id, body')
  if (error) throw new Error(`sms: ${error.message}`)

  let sent = 0
  for (const n of rows ?? []) {
    const { data: t } = await db.from('tenants').select('phone, user_id').eq('id', n.tenant_id).maybeSingle()
    if (!t) continue
    // The number on the tenant record, or the one on their app account
    let phone = t.phone
    if (!phone && t.user_id) ({ data: { phone } = {} } = await db.from('profiles').select('phone').eq('id', t.user_id).maybeSingle())
    if (!phone) continue
    try {
      await sendSms(phone, shorten(`Renta UG: ${n.body}`), env)
      sent++
    } catch (e) {
      console.warn(`[sms] ${e.message}`)
      await db.from('notifications').update({ sms_error: e.message.slice(0, 300) }).eq('id', n.id)
    }
  }
  return sent
}

export function startSmsSender(db, env = process.env) {
  if (!db || !smsEnabled(env)) {
    console.log('  sms:      disabled (add AT_USERNAME + AT_API_KEY to text tenants when cash is confirmed)')
    return
  }
  console.log(`  sms:      enabled${env.AT_USERNAME === 'sandbox' ? ' (SANDBOX: no real texts)' : ''}`)
  let running = false
  async function tick() {
    if (running) return
    running = true
    try {
      await sendPendingSms(db, env)
    } catch (e) {
      console.warn(`[sms] ${e.message}`)
    } finally {
      running = false
    }
  }
  tick()
  setInterval(tick, EVERY_MS)
}
