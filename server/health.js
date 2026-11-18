// System health: checks every part of Renta UG and keeps the result for the main admin.
// Runs every 20 minutes (Netlify scheduled function `health-check`, or `npm run server` locally) and
// whenever the main admin taps "Run checks now". Problems are also reported as errors, so the main
// admin gets a notification. Shared by the Express server and the Netlify Functions.
import { mailEnabled } from './mailer.js'
import { smsEnabled } from './sms.js'

const EVERY_MS = 20 * 60 * 1000
const ago = (ms) => new Date(Date.now() - ms).toISOString()

// The parts of the database every page needs
const TABLES = [
  ['profiles', 'Accounts'],
  ['properties', 'Houses and rooms'],
  ['tenants', 'Tenants'],
  ['payments', 'Rent charges'],
  ['payment_receipts', 'Receipts'],
  ['cash_payments', 'Payments to confirm'],
  ['landlord_pay_accounts', 'Mobile money numbers'],
  ['notifications', 'Tenant notifications'],
  ['staff_notifications', 'Inbox'],
  ['error_reports', 'Error reports'],
]

async function timed(fn) {
  const t = Date.now()
  try {
    const out = await fn()
    return { ...out, ms: Date.now() - t }
  } catch (e) {
    return { status: 'fail', detail: e.message, ms: Date.now() - t }
  }
}

export async function runHealthCheck(db, env = process.env, trigger = 'schedule') {
  if (!db) return { ok: false, results: [{ key: 'db', label: 'Database', status: 'fail', detail: 'The server has no Supabase key.' }] }
  const results = []
  const add = (key, label, r) => results.push({ key, label, ...r })

  // 1. Database: each table answers
  add('database', 'Database', await timed(async () => {
    const missing = []
    for (const [table, label] of TABLES) {
      const { error } = await db.from(table).select('*', { head: true, count: 'exact' }).limit(1)
      if (error) missing.push(`${label} (${error.message})`)
    }
    if (missing.length) {
      return { status: 'fail', detail: `Not working: ${missing.join('; ')}. Run database/update_existing.sql in Supabase.` }
    }
    return { status: 'ok', detail: `${TABLES.length} tables answering.` }
  }))

  // 2. Sign-in service
  add('auth', 'Sign-in', await timed(async () => {
    const { error } = await db.auth.admin.listUsers({ page: 1, perPage: 1 })
    return error ? { status: 'fail', detail: error.message } : { status: 'ok', detail: 'Accounts can sign in.' }
  }))

  // 3. Email (sign-up codes)
  add('email', 'Email codes', {
    status: mailEnabled(env) ? 'ok' : 'fail',
    detail: mailEnabled(env) ? 'Sign-up codes can be emailed.' : 'SMTP_USER / SMTP_PASS are missing: nobody can sign up.',
  })

  // 4. SMS (payment confirmations)
  add('sms', 'SMS', await timed(async () => {
    if (!smsEnabled(env)) return { status: 'warn', detail: 'Not switched on (AT_USERNAME / AT_API_KEY). Tenants only get in-app notifications.' }
    const { count } = await db
      .from('notifications')
      .select('id', { head: true, count: 'exact' })
      .not('sms_error', 'is', null)
      .gte('created_at', ago(EVERY_MS * 3))
    return count ? { status: 'warn', detail: `${count} text message(s) failed in the last hour.` } : { status: 'ok', detail: 'Texts are being sent.' }
  }))

  // 5. Phone notifications: nothing stuck
  add('push', 'Phone notifications', await timed(async () => {
    if (!env.VITE_VAPID_PUBLIC_KEY || !env.VAPID_PRIVATE_KEY) return { status: 'warn', detail: 'VAPID keys missing: no pop-ups on phones.' }
    const { count } = await db
      .from('notifications')
      .select('id', { head: true, count: 'exact' })
      .is('pushed_at', null)
      .lte('created_at', ago(10 * 60 * 1000))
      .gte('created_at', ago(24 * 60 * 60 * 1000))
    return count ? { status: 'warn', detail: `${count} notification(s) waiting more than 10 minutes to be sent.` } : { status: 'ok', detail: 'Delivered on time.' }
  }))

  // 6. Payments waiting too long for a landlord
  add('payments', 'Payments to confirm', await timed(async () => {
    const { count } = await db
      .from('cash_payments')
      .select('id', { head: true, count: 'exact' })
      .eq('status', 'pending')
      .lte('created_at', ago(3 * 24 * 60 * 60 * 1000))
    return count ? { status: 'warn', detail: `${count} payment(s) waiting more than 3 days for a landlord to confirm.` } : { status: 'ok', detail: 'Landlords are confirming payments.' }
  }))

  // 7. Errors reported by the app in the last 20 minutes
  add('errors', 'App errors', await timed(async () => {
    const { count } = await db
      .from('error_reports')
      .select('id', { head: true, count: 'exact' })
      .eq('status', 'open')
      .gte('last_seen', ago(EVERY_MS))
    return count ? { status: 'warn', detail: `${count} error(s) reported in the last 20 minutes.` } : { status: 'ok', detail: 'No new errors.' }
  }))

  const ok = results.every((r) => r.status === 'ok')
  await db.from('health_checks').insert({ ok, results, trigger }).then(({ error }) => error && console.warn(`[health] ${error.message}`))
  // Keep about a week of checks, and error reports for at most 12 months (as the Privacy policy says)
  await db.from('health_checks').delete().lt('run_at', ago(7 * 24 * 60 * 60 * 1000))
  await db.from('error_reports').delete().lt('last_seen', ago(365 * 24 * 60 * 60 * 1000))

  // Failures become error reports → the main admin is notified (once per problem, then counted)
  for (const r of results.filter((x) => x.status === 'fail')) {
    await reportServerError(db, `Health check · ${r.label}`, r.detail, 'health')
  }
  return { ok, results }
}

// Record a server-side error for the main admin (grouped with the same earlier error)
export async function reportServerError(db, area, err, source = 'server') {
  if (!db) return
  const message = typeof err === 'string' ? err : err?.message || 'Unknown error'
  try {
    await db.rpc('report_error', {
      p_source: source,
      p_area: area,
      p_message: message,
      p_detail: typeof err === 'object' && err?.stack ? String(err.stack).slice(0, 3000) : null,
      p_url: null,
      p_user_agent: 'server',
      p_auto_fixed: false,
    })
  } catch {
    /* reporting must never break anything */
  }
}

export function startHealthChecks(db, env = process.env) {
  if (!db) return
  console.log('  health:   checking every 20 minutes')
  const tick = () => runHealthCheck(db, env).catch((e) => console.warn(`[health] ${e.message}`))
  setTimeout(tick, 15_000)
  setInterval(tick, EVERY_MS)
}
