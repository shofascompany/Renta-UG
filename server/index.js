// Renta UG API: mobile money rent payments, phone notifications and landlord accounts, backed by Supabase.
// Uses the Supabase service role key, so it must only ever run on a server.
import express from 'express'
import cors from 'cors'
import { createClient } from '@supabase/supabase-js'
import { randomBytes } from 'node:crypto'
import { existsSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { retryFetch, isNetworkError, NETWORK_MESSAGE } from '../src/lib/retryFetch.js'
import * as momo from './momo.js'
import { startPushSender } from './push.js'

const { providerName } = momo
const PORT = process.env.PORT || 4242
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY

const db =
  SUPABASE_URL && SERVICE_KEY
    ? createClient(SUPABASE_URL, SERVICE_KEY, {
        auth: { persistSession: false, autoRefreshToken: false },
        global: { fetch: retryFetch() }, // retries + timeouts for unstable connections
      })
    : null

const app = express()
app.use(cors({ origin: process.env.CLIENT_URL || 'http://localhost:5173' }))

// ── Helpers ───────────────────────────────────────────────────

class HttpError extends Error {
  constructor(status, message) {
    super(message)
    this.status = status
  }
}

const handle = (fn) => async (req, res) => {
  try {
    await fn(req, res)
  } catch (err) {
    if (!(err instanceof HttpError) && isNetworkError(err)) {
      console.warn(`[${req.method} ${req.path}] network problem reaching Supabase: ${err.message}`)
      return res.status(503).json({ error: NETWORK_MESSAGE })
    }
    if (!(err instanceof HttpError)) console.error(err)
    res.status(err.status || 500).json({ error: err.message || 'Server error' })
  }
}

// Throw on a Supabase error; network failures become a 503 the app can explain.
function check(error) {
  if (!error) return
  if (isNetworkError(error)) throw new HttpError(503, NETWORK_MESSAGE)
  throw error
}

function requireDb() {
  if (!db) throw new HttpError(500, 'Supabase is not configured on the server (SUPABASE_SERVICE_ROLE_KEY).')
}

async function requireSuperadmin(req) {
  requireDb()
  const user = await requireUser(req)
  const { data, error } = await db.from('profiles').select('role').eq('id', user.id).maybeSingle()
  check(error)
  if (data?.role !== 'superadmin') throw new HttpError(403, 'Only the main admin can do this.')
  return user
}

async function requireUser(req) {
  const token = req.headers.authorization?.replace(/^Bearer\s+/i, '')
  if (!token) throw new HttpError(401, 'Not signed in.')
  const { data, error } = await db.auth.getUser(token)
  if (error && isNetworkError(error)) throw new HttpError(503, NETWORK_MESSAGE) // not the user's fault
  if (error || !data.user) throw new HttpError(401, 'Session expired. Please sign in again.')
  return data.user
}

// Loads a payment and checks it belongs to the signed-in tenant.
async function ownedPayment(paymentId, userId) {
  if (!paymentId) throw new HttpError(400, 'Missing payment.')
  const { data, error } = await db
    .from('payments')
    .select('id, amount, amount_paid, period, status, tenant_id, landlord_id, tenants!inner(user_id)')
    .eq('id', paymentId)
    .maybeSingle()
  check(error)
  if (!data || data.tenants.user_id !== userId) throw new HttpError(404, 'Payment not found.')
  return data
}

const ugx = (n) => `UGX ${Number(n).toLocaleString('en-UG')}`
const monthOf = (period) => {
  const [y, m] = period.split('-').map(Number)
  return new Date(y, m - 1, 1).toLocaleDateString('en-GB', { month: 'long', year: 'numeric' })
}

// Online payment verified → pay off the rent charge (idempotent), keep a receipt, confirm to the
// tenant, and send a "payment received" confirmation to the landlord's and main admin's accounts.
async function markPaid(paymentId, reference, method, phone) {
  const { data: before, error: bErr } = await db
    .from('payments')
    .select('id, amount, amount_paid, status, landlord_id, tenant_id, property_id, period')
    .eq('id', paymentId)
    .maybeSingle()
  check(bErr)
  if (!before || before.status === 'paid') return
  const received = Number(before.amount) - Number(before.amount_paid ?? 0)
  const paidAt = new Date().toISOString()

  const { data: rows, error } = await db
    .from('payments')
    .update({ status: 'paid', amount_paid: before.amount, paid_at: paidAt, method, reference })
    .eq('id', paymentId)
    .eq('status', 'pending') // only the first caller gets past here
    .select('id')
  check(error)
  if (!rows?.length) return

  await db.from('payment_receipts').insert({
    payment_id: before.id,
    tenant_id: before.tenant_id,
    landlord_id: before.landlord_id,
    amount: received,
    method,
    reference,
    received_at: paidAt,
  })

  const [{ data: tenant }, { data: house }, { data: rest }] = await Promise.all([
    db.from('tenants').select('full_name').eq('id', before.tenant_id).maybeSingle(),
    db.from('properties').select('name').eq('id', before.property_id).maybeSingle(),
    db.from('payments').select('amount, amount_paid').eq('tenant_id', before.tenant_id).eq('status', 'pending'),
  ])
  const balance = (rest ?? []).reduce((s, p) => s + Number(p.amount) - Number(p.amount_paid ?? 0), 0)
  const month = monthOf(before.period)

  // Tenant confirmation
  await db.from('notifications').insert({
    landlord_id: before.landlord_id,
    tenant_id: before.tenant_id,
    type: 'payment',
    title: 'Payment confirmation', // sender line; the notification title is always "Renta UG"
    body:
      `Your ${method} payment of ${ugx(received)} for ${month} rent has been received and verified. ` +
      (balance === 0 ? 'You have no outstanding balance. Thank you.' : `Outstanding balance: ${ugx(balance)}.`),
  })

  // Company confirmation: the landlord + the main admin
  const { data: admins } = await db.from('profiles').select('id').eq('role', 'superadmin')
  const body =
    `${tenant?.full_name ?? 'A tenant'} has paid ${ugx(received)} for ${month} rent${house?.name ? ` at ${house.name}` : ''} via ${method}` +
    `${phone ? ` (${String(phone).replace(/^256/, '0')})` : ''}. The payment was verified automatically. Reference: ${reference}.`
  await db.from('staff_notifications').insert([
    { user_id: before.landlord_id, type: 'payment', title: 'Payment received', body, url: '/landlord/inbox' },
    ...(admins ?? []).map((a) => ({ user_id: a.id, type: 'payment', title: 'Payment received', body, url: '/admin2026/inbox' })),
  ])
}

app.use(express.json())

// ── Routes ────────────────────────────────────────────────────

app.get('/api/health', (_req, res) => {
  res.json({ ok: true, supabase: Boolean(db), mobileMoney: providerName() })
})

// ── Mobile money (MTN / Airtel) ──────────────────────────────

const attemptView = (a) => ({
  attemptId: a.id,
  status: a.status,
  network: a.network,
  phone: a.phone,
  redirectUrl: a.redirect_url,
  reason: a.failure_reason,
  testMode: a.provider === 'test',
})

// Checks one attempt with the provider and records the outcome. Safe to call repeatedly.
async function checkAttempt(attempt) {
  if (attempt.status !== 'pending') return attempt

  let result
  try {
    result = await momo.verify(attempt)
  } catch (e) {
    console.warn(`[momo] verify ${attempt.tx_ref}: ${e.message}`)
    return attempt // try again on the next check
  }

  let update = null
  if (result.status === 'successful') {
    // Never trust a success that doesn't match what we asked for
    if (result.currency === 'UGX' && Number(result.amount) >= Number(attempt.amount)) {
      update = { status: 'successful', provider_ref: result.providerRef ?? attempt.provider_ref }
    } else {
      update = { status: 'failed', failure_reason: 'Amount or currency did not match. Contact support.' }
    }
  } else if (result.status === 'failed') {
    update = { status: 'failed', failure_reason: result.reason || 'The payment was declined or cancelled.' }
  } else if (Date.now() - new Date(attempt.created_at).getTime() > momo.ATTEMPT_TIMEOUT_MS) {
    update = { status: 'failed', failure_reason: 'The payment was not approved in time.' }
  }
  if (!update) return attempt

  // Only the first checker to flip it from pending gets to act on it
  const { data: rows, error } = await db
    .from('momo_attempts')
    .update({ ...update, updated_at: new Date().toISOString() })
    .eq('id', attempt.id)
    .eq('status', 'pending')
    .select()
  check(error)
  const updated = rows?.[0]
  if (!updated) {
    const { data: fresh } = await db.from('momo_attempts').select('*').eq('id', attempt.id).single()
    return fresh ?? attempt
  }
  if (updated.status === 'successful') {
    await markPaid(updated.payment_id, updated.provider_ref ?? updated.tx_ref, momo.NETWORK_LABEL[updated.network], updated.phone)
  }
  return updated
}

// Tenant starts paying a rent charge with MTN or Airtel.
app.post(
  '/api/momo/pay',
  handle(async (req, res) => {
    requireDb()
    const user = await requireUser(req)
    const payment = await ownedPayment(req.body?.paymentId, user.id)
    if (payment.status === 'paid') throw new HttpError(400, 'This rent has already been paid.')

    const network = String(req.body?.network ?? '').toUpperCase()
    if (!['MTN', 'AIRTEL'].includes(network)) throw new HttpError(400, 'Choose MTN or Airtel.')
    const msisdn = momo.normalizeUgPhone(req.body?.phone)
    if (!msisdn) throw new HttpError(400, 'Enter a valid Ugandan mobile number, e.g. 0772 123456.')
    const actual = momo.networkOf(msisdn)
    if (actual && actual !== network) {
      throw new HttpError(400, `That looks like an ${actual === 'MTN' ? 'MTN' : 'Airtel'} number. Choose ${actual === 'MTN' ? 'MTN' : 'Airtel'} or use a different number.`)
    }

    // Don't send a second prompt while one is still waiting for approval
    const { data: open, error: oErr } = await db
      .from('momo_attempts')
      .select('*')
      .eq('payment_id', payment.id)
      .eq('status', 'pending')
      .order('created_at', { ascending: false })
      .limit(1)
    check(oErr)
    if (open?.[0]) {
      const current = await checkAttempt(open[0])
      if (current.status === 'pending') return res.json({ ...attemptView(current), resumed: true })
      if (current.status === 'successful') return res.json(attemptView(current))
    }

    // Only what's still owed (part of it may already have been paid in cash)
    const due = Number(payment.amount) - Number(payment.amount_paid ?? 0)
    const txRef = momo.newTxRef()
    const provider = providerName()
    const { data: attempt, error } = await db
      .from('momo_attempts')
      .insert({
        payment_id: payment.id,
        tenant_id: payment.tenant_id,
        landlord_id: payment.landlord_id,
        network,
        phone: msisdn,
        amount: due,
        tx_ref: txRef,
        provider,
      })
      .select()
      .single()
    check(error)

    try {
      const { providerRef, redirectUrl } = await momo.initiate({
        txRef,
        amount: due,
        msisdn,
        network,
        email: user.email || process.env.PAYMENT_EMAIL_FALLBACK || 'payments@example.com',
        fullname: user.user_metadata?.full_name,
      })
      const { data: saved } = await db
        .from('momo_attempts')
        .update({ provider_ref: providerRef, redirect_url: redirectUrl, updated_at: new Date().toISOString() })
        .eq('id', attempt.id)
        .select()
        .single()
      res.json(attemptView(saved ?? attempt))
    } catch (e) {
      await db.from('momo_attempts').update({ status: 'failed', failure_reason: e.message }).eq('id', attempt.id)
      if (isNetworkError(e)) throw new HttpError(503, NETWORK_MESSAGE)
      throw new HttpError(502, `Could not start the payment: ${e.message}`)
    }
  }),
)

// The app polls this while the tenant approves the prompt on their phone.
app.post(
  '/api/momo/status',
  handle(async (req, res) => {
    requireDb()
    const user = await requireUser(req)
    const { data: attempt, error } = await db.from('momo_attempts').select('*').eq('id', req.body?.attemptId).maybeSingle()
    check(error)
    if (!attempt) throw new HttpError(404, 'Payment not found.')
    await ownedPayment(attempt.payment_id, user.id) // must be this tenant's
    res.json(attemptView(await checkAttempt(attempt)))
  }),
)

// Flutterwave calls this when a payment completes. The body is never trusted: we re-verify with the API.
app.post(
  '/api/momo/webhook',
  handle(async (req, res) => {
    requireDb()
    const expected = process.env.FLW_WEBHOOK_HASH
    if (!expected || req.headers['verif-hash'] !== expected) throw new HttpError(401, 'Invalid webhook signature.')
    const txRef = req.body?.data?.tx_ref ?? req.body?.txRef
    if (txRef) {
      const { data: attempt } = await db.from('momo_attempts').select('*').eq('tx_ref', txRef).maybeSingle()
      if (attempt) await checkAttempt(attempt)
    }
    res.json({ received: true })
  }),
)

// Background: keep checking pending payments, so they're confirmed even if the tenant closed the app.
function startMomoWatcher() {
  if (!db) return
  let running = false
  setInterval(async () => {
    if (running) return
    running = true
    try {
      const { data: pending } = await db.from('momo_attempts').select('*').eq('status', 'pending').order('created_at').limit(25)
      for (const a of pending ?? []) await checkAttempt(a)
    } catch (e) {
      console.warn(`[momo] watcher: ${e.message}`)
    } finally {
      running = false
    }
  }, 15_000)
}

// ── Main admin: manage landlord accounts ─────────────────────

const BAN_FOREVER = '876000h' // ~100 years

// Unusable random password: first-time landlords sign in by email only, then set their own.
const placeholderPassword = () => randomBytes(24).toString('base64url')

// ── Landlord first sign-in (email only) ──────────────────────
// NOTE: by design, a landlord who hasn't set a password yet can be signed in with just
// their email. Anyone who knows that email could do the same until the landlord sets one.

async function firstLoginLandlord(email) {
  const { data, error } = await db
    .from('profiles')
    .select('id, role, active, must_change_password')
    .eq('email', email)
    .maybeSingle()
  check(error)
  return data?.role === 'landlord' && data.active && data.must_change_password ? data : null
}

// Login page asks this in the background while the email is typed.
app.post(
  '/api/auth/status',
  handle(async (req, res) => {
    requireDb()
    const email = req.body?.email?.trim().toLowerCase()
    res.json({ firstLogin: Boolean(email && (await firstLoginLandlord(email))) })
  }),
)

// Signs a first-time landlord in without a password: returns a one-time token the browser
// exchanges for a session. The app then forces them to the "set your password" page.
app.post(
  '/api/auth/first-login',
  handle(async (req, res) => {
    requireDb()
    const email = req.body?.email?.trim().toLowerCase()
    if (!email || !(await firstLoginLandlord(email))) throw new HttpError(400, 'Please enter your password.')

    const { data, error } = await db.auth.admin.generateLink({ type: 'magiclink', email })
    if (error && isNetworkError(error)) throw new HttpError(503, NETWORK_MESSAGE)
    if (error) throw new HttpError(400, error.message)
    res.json({ tokenHash: data.properties.hashed_token })
  }),
)

// Register a landlord: creates their login and marks the profile as landlord.
app.post(
  '/api/admin/landlords',
  handle(async (req, res) => {
    await requireSuperadmin(req)
    const name = req.body?.name?.trim()
    const email = req.body?.email?.trim().toLowerCase()
    const phone = req.body?.phone?.trim() || null
    if (!name || !email) throw new HttpError(400, 'Name and email are required.')

    const { data, error } = await db.auth.admin.createUser({
      email,
      password: placeholderPassword(), // never used: they set their own on first sign-in
      email_confirm: true,
      user_metadata: { full_name: name },
    })
    if (error && isNetworkError(error)) throw new HttpError(503, NETWORK_MESSAGE)
    if (error) {
      const taken = /already|registered|exists/i.test(error.message)
      throw new HttpError(400, taken ? 'An account with this email already exists.' : error.message)
    }

    const { error: pErr } = await db
      .from('profiles')
      // First sign-in by email only, then the landlord must choose their own password
      .upsert({ id: data.user.id, email, full_name: name, phone, role: 'landlord', active: true, must_change_password: true })
    check(pErr)
    res.json({ id: data.user.id })
  }),
)

// Update a landlord's details, reset their password, or suspend / reactivate them.
app.patch(
  '/api/admin/landlords/:id',
  handle(async (req, res) => {
    await requireSuperadmin(req)
    const { id } = req.params
    const { data: target, error: tErr } = await db.from('profiles').select('role').eq('id', id).maybeSingle()
    check(tErr)
    if (target?.role !== 'landlord') throw new HttpError(404, 'Landlord not found.')

    const { name, phone, resetPassword, active } = req.body ?? {}
    const authAttrs = {}
    const profile = {}
    if (typeof name === 'string' && name.trim()) {
      profile.full_name = name.trim()
      authAttrs.user_metadata = { full_name: name.trim() }
    }
    if (typeof phone === 'string') profile.phone = phone.trim() || null
    if (resetPassword === true) {
      // Old password stops working; next sign-in is by email only, then they set a new one
      authAttrs.password = placeholderPassword()
      profile.must_change_password = true
    }
    if (typeof active === 'boolean') {
      profile.active = active
      authAttrs.ban_duration = active ? 'none' : BAN_FOREVER
    }

    if (Object.keys(authAttrs).length) {
      const { error } = await db.auth.admin.updateUserById(id, authAttrs)
      if (error && isNetworkError(error)) throw new HttpError(503, NETWORK_MESSAGE)
      if (error) throw new HttpError(400, error.message)
    }
    if (Object.keys(profile).length) {
      const { error } = await db.from('profiles').update(profile).eq('id', id)
      check(error)
    }
    res.json({ ok: true })
  }),
)

// Permanently delete an account that is no longer active:
//   - a SUSPENDED landlord (also deletes all their properties, tenants, payments, notices, alerts)
//   - a tenant account with no current rental (never connected, or their tenancy ended)
app.delete(
  '/api/admin/users/:id',
  handle(async (req, res) => {
    const me = await requireSuperadmin(req)
    const { id } = req.params
    if (id === me.id) throw new HttpError(400, 'You cannot delete the main admin account.')

    const { data: target, error } = await db.from('profiles').select('role, active').eq('id', id).maybeSingle()
    check(error)
    if (!target) throw new HttpError(404, 'User not found.')
    if (target.role === 'superadmin') throw new HttpError(400, 'The main admin account cannot be deleted.')

    if (target.role === 'landlord' && target.active) {
      throw new HttpError(400, 'Suspend this landlord first. Only inactive landlords can be deleted.')
    }
    if (target.role === 'tenant') {
      const { data: rental, error: rErr } = await db
        .from('tenants')
        .select('id')
        .eq('user_id', id)
        .not('property_id', 'is', null)
        .maybeSingle()
      check(rErr)
      if (rental) throw new HttpError(400, 'This tenant still has an active rental. Their landlord must end the tenancy first.')
    }

    const { error: delErr } = await db.auth.admin.deleteUser(id)
    if (delErr && isNetworkError(delErr)) throw new HttpError(503, NETWORK_MESSAGE)
    if (delErr) throw new HttpError(400, delErr.message)
    res.json({ ok: true })
  }),
)

// ── The web app itself (after `npm run build`), so one address serves app + API ──
const DIST = fileURLToPath(new URL('../dist', import.meta.url))
if (existsSync(join(DIST, 'index.html'))) {
  app.use(express.static(DIST, { index: false }))
  app.use((req, res, next) => {
    if (req.method !== 'GET' || req.path.startsWith('/api')) return next()
    res.sendFile(join(DIST, 'index.html')) // client-side routes like /tenant/payments
  })
}
app.use('/api', (_req, res) => res.status(404).json({ error: 'Not found' }))

app.listen(PORT, () => {
  console.log(`Renta API on http://localhost:${PORT}`)
  console.log(`  supabase: ${db ? 'configured' : 'NOT configured'}`)
  console.log(`  momo:     ${providerName() === 'test' ? 'TEST MODE (no real money; payments auto-approve)' : 'Flutterwave (live/sandbox per your key)'}`)
  startPushSender(db)
  startMomoWatcher()
})
