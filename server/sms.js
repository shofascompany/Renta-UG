// Text messages (SMS) from "Renta UG" when a LANDLORD confirms (or rejects) a payment: cash or
// mobile money, recorded by the landlord or sent by the tenant. Every tenant with a phone number gets
// one: those without a smartphone (who never see the app) and those with the app (who also get the
// normal in-app / phone notification).
// Works like the phone-notification sender: it polls for new payment notifications, claims each one once
// (sms_sent_at) and sends it. Uses Africa's Talking, which sends to MTN and Airtel numbers in Uganda.

import AfricasTalking from 'africastalking'

// Any Ugandan mobile number → 2567XXXXXXXX (null if it isn't one)
export function normalizeUgPhone(input) {
  const d = String(input ?? '').replace(/\D/g, '')
  let local = null
  if (d.length === 12 && d.startsWith('256')) local = d.slice(3)
  else if (d.length === 10 && d.startsWith('0')) local = d.slice(1)
  else if (d.length === 9) local = d
  return local && local.startsWith('7') ? `256${local}` : null
}

// Notification titles written by the database when a landlord confirms / rejects a payment
const TEXTED = ['Payment confirmation', 'Payment not confirmed', 'Cash payment not confirmed']

const EVERY_MS = 10_000
const CATCH_UP = 6 * 60 * 60 * 1000 // after a restart, still send what is from the last 6 hours
const MAX_LENGTH = 300 // two SMS parts
const RETRY_FOR = 2 * 60 * 60 * 1000 // keep retrying a text that failed for a brief reason for up to 2 hours

export const smsEnabled = (env = process.env) => Boolean(env.AT_USERNAME && env.AT_API_KEY)

// Africa's Talking client (their official package), made once per username + key
let client = null
let clientFor = ''
function atClient(env) {
  const id = `${env.AT_USERNAME}:${env.AT_API_KEY}`
  if (!client || clientFor !== id) {
    client = AfricasTalking({ username: env.AT_USERNAME, apiKey: env.AT_API_KEY })
    clientFor = id
  }
  return client
}

const reason = (e) => {
  const d = e?.response?.data
  return `${e?.response?.status ?? ''} ${typeof d === 'string' ? d : d ? JSON.stringify(d) : e?.message ?? e}`.trim().slice(0, 200)
}

// Sends one text. `to` is any Ugandan number. Throws a readable error when it fails.
export async function sendSms(to, message, env = process.env) {
  if (!smsEnabled(env)) throw new Error('SMS is not set up (add AT_USERNAME and AT_API_KEY).')
  const local = normalizeUgPhone(to)
  if (!local) throw new Error('That is not a valid Ugandan phone number.')
  // A refused login (401), a server hiccup (5xx) or a dropped connection is often brief:
  // try up to 4 times, waiting 1 s, 2 s, then 3 s (stays inside Netlify's 10 s function limit)
  const isTransient = (e) => {
    const status = e?.response?.status
    return !status || status === 401 || status === 429 || status >= 500
  }
  const send = async (from) => {
    for (let attempt = 1; ; attempt++) {
      try {
        return await atClient(env).SMS.send({ to: [`+${local}`], message, ...(from ? { from } : {}) })
      } catch (e) {
        if (attempt >= 4 || !isTransient(e)) throw e
        await new Promise((r) => setTimeout(r, attempt * 1000))
      }
    }
  }
  const fail = (e) => Object.assign(new Error(`SMS provider said ${reason(e)}`), { transient: isTransient(e) })

  let res
  try {
    res = await send(env.AT_SENDER_ID)
  } catch (e) {
    throw fail(e)
  }
  let r = res?.SMSMessageData?.Recipients?.[0]
  // Sender name not approved yet: send it from the default number instead
  if (env.AT_SENDER_ID && r && /sender/i.test(`${r.status}`)) {
    try {
      res = await send(null)
    } catch (e) {
      throw fail(e)
    }
    r = res?.SMSMessageData?.Recipients?.[0]
  }
  if (!r || !/success|sent|queued/i.test(`${r.status}`)) {
    throw new Error(`SMS not accepted: ${r?.status ?? res?.SMSMessageData?.Message ?? 'unknown reason'}`)
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
    .in('title', TEXTED)
    .gte('created_at', new Date(Date.now() - CATCH_UP).toISOString())
    .select('id, tenant_id, body, created_at')
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
      await db.from('notifications').update({ sms_error: null }).eq('id', n.id).not('sms_error', 'is', null) // sent after a retry
    } catch (e) {
      console.warn(`[sms] ${e.message}`)
      // A brief problem (provider refused for a moment, connection dropped): put it back in the queue
      // so the next round tries again. Real problems (bad number, no credit) are not retried.
      const retry = e.transient && Date.now() - new Date(n.created_at).getTime() < RETRY_FOR
      await db
        .from('notifications')
        .update({ sms_error: e.message.slice(0, 300), ...(retry ? { sms_sent_at: null } : {}) })
        .eq('id', n.id)
    }
  }
  return sent
}

export function startSmsSender(db, env = process.env) {
  if (!db || !smsEnabled(env)) {
    console.log('  sms:      disabled (add AT_USERNAME + AT_API_KEY to text tenants when a payment is confirmed)')
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
