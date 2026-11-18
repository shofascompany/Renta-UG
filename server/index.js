// Renta UG API: sign-up codes, phone notifications, SMS, health checks and landlord accounts, backed by Supabase.
// (Mobile money goes straight from the tenant's phone to the landlord's number; the landlord confirms it
// in the app, so there is no payment company or payment server.)
// Uses the Supabase service role key, so it must only ever run on a server.
import express from 'express'
import cors from 'cors'
import { createClient } from '@supabase/supabase-js'
import { existsSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { retryFetch, isNetworkError, NETWORK_MESSAGE } from '../src/lib/retryFetch.js'
import { startPushSender } from './push.js'
import { startSmsSender } from './sms.js'
import { startHealthChecks, runHealthCheck, reportServerError } from './health.js'
import * as admin from './admin.js'
import * as verifyEmail from './verify.js'
import * as passwordReset from './passwordReset.js'

const { HttpError } = admin

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


const handle = (fn) => async (req, res) => {
  try {
    await fn(req, res)
  } catch (err) {
    if (!(err instanceof HttpError) && isNetworkError(err)) {
      console.warn(`[${req.method} ${req.path}] network problem reaching Supabase: ${err.message}`)
      return res.status(503).json({ error: NETWORK_MESSAGE })
    }
    if (!(err instanceof HttpError)) {
      console.error(err)
      reportServerError(db, `${req.method} ${req.path}`, err) // shows on the main admin's System page
    }
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

app.use(express.json())

// ── Routes ────────────────────────────────────────────────────

app.get('/api/health', (_req, res) => {
  res.json({ ok: true, supabase: Boolean(db) })
})

// ── Main admin: manage landlord accounts (logic in ./admin.js, shared with Netlify) ──

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

// ── Sign up with an emailed 6-character code (logic in ./verify.js, shared with the Netlify Function) ──
for (const step of ['start', 'verify', 'resend']) {
  app.post(
    `/api/signup/${step}`,
    handle(async (req, res) => {
      requireDb()
      res.json(await verifyEmail[step](db, req.body))
    }),
  )
}

// ── Forgot password: the app emails the reset link (logic in ./passwordReset.js, shared with Netlify) ──
app.post(
  '/api/password/forgot',
  handle(async (req, res) => {
    requireDb()
    res.json(await passwordReset.forgot(db, req.body))
  }),
)

// ── Sign in with a PHONE NUMBER (same box as email on the login page) ──
// The account's email is looked up here on the server, so it is never revealed to the browser.
// Numbers match on their last 9 digits: 0772 123456 = +256772123456 = 256772123456.

const phoneDigits = (v) => String(v ?? '').replace(/\D/g, '')

async function profileByPhone(phone) {
  const want = phoneDigits(phone).slice(-9)
  if (want.length < 9) return null
  const { data, error } = await db
    .from('profiles')
    .select('id, email, phone, role, active, must_change_password, created_at')
    .not('phone', 'is', null)
  check(error)
  return (
    (data ?? [])
      .filter((p) => phoneDigits(p.phone).slice(-9) === want)
      .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)))[0] ?? null
  )
}

function phoneStatus(p) {
  if (!p) return 'not_found'
  if (p.role === 'landlord' && !p.active) return 'suspended'
  if (p.role === 'landlord' && p.must_change_password) return 'first_login'
  if (p.role === 'tenant' && p.must_change_password) return 'tenant_first_login' // app access just given by the landlord
  return p.role === 'landlord' || p.role === 'tenant' ? p.role : 'not_found'
}

// { phone, password }   → { accessToken, refreshToken }  (normal sign-in)
// { phone }             → { tokenHash }                   (landlord's first sign-in, no password yet)
// { phone, check: true } → { status }  live check fallback if 20_login_phone_check.sql hasn't been run
app.post(
  '/api/auth/phone-sign-in',
  handle(async (req, res) => {
    requireDb()
    const profile = await profileByPhone(req.body?.phone)
    const status = phoneStatus(profile)
    if (req.body?.check) return res.json({ status })
    if (status === 'not_found' || !profile?.email) throw new HttpError(400, 'No account uses this phone number.')
    if (status === 'suspended') throw new HttpError(403, 'This account has been suspended. Please contact Renta UG.')

    const password = String(req.body?.password ?? '')
    if ((status === 'first_login' || status === 'tenant_first_login') && !password) {
      const { data, error } = await db.auth.admin.generateLink({ type: 'magiclink', email: profile.email })
      if (error && isNetworkError(error)) throw new HttpError(503, NETWORK_MESSAGE)
      if (error) throw new HttpError(400, error.message)
      return res.json({ tokenHash: data.properties.hashed_token })
    }
    if (!password) throw new HttpError(400, 'Please enter your password.')

    // A throwaway client so this server never keeps the user's session.
    const client = createClient(SUPABASE_URL, SERVICE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { fetch: retryFetch() },
    })
    const { data, error } = await client.auth.signInWithPassword({ email: profile.email, password })
    if (error && isNetworkError(error)) throw new HttpError(503, NETWORK_MESSAGE)
    if (error) throw new HttpError(400, error.message)
    res.json({ accessToken: data.session.access_token, refreshToken: data.session.refresh_token })
  }),
)

// ── Tenants without a smartphone → app access (logic in ./admin.js, shared with Netlify) ──

// Landlord: create the tenant's login (signs in with their phone number; no connection code).
app.post(
  '/api/landlord/tenants/:id/app-access',
  handle(async (req, res) => {
    requireDb()
    const { user, profile } = await admin.requireUserProfile(db, req.headers.authorization)
    if (profile?.role !== 'landlord' || !profile.active) throw new HttpError(403, 'Only landlords can do this.')
    res.json(await admin.giveTenantAppAccess(db, user.id, req.params.id))
  }),
)

// Tenant's first sign-in: add their email + choose a password.
app.post(
  '/api/auth/complete-tenant',
  handle(async (req, res) => {
    requireDb()
    const { user, profile } = await admin.requireUserProfile(db, req.headers.authorization)
    res.json(await admin.completeTenantAccount(db, user, profile, req.body))
  }),
)

// Register a landlord: creates their login and marks the profile as landlord.
app.post(
  '/api/admin/landlords',
  handle(async (req, res) => {
    await requireSuperadmin(req)
    res.json(await admin.createLandlord(db, req.body)) // shared with the Netlify Function
  }),
)

// Update a landlord's details, reset their password, or suspend / reactivate them.
app.patch(
  '/api/admin/landlords/:id',
  handle(async (req, res) => {
    await requireSuperadmin(req)
    res.json(await admin.updateLandlord(db, req.params.id, req.body))
  }),
)

// Archive everything, then delete every landlord and tenant (main admin only, typed confirmation).
app.post(
  '/api/admin/clear',
  handle(async (req, res) => {
    const me = await requireSuperadmin(req)
    res.json(await admin.archiveAndClear(db, me.id, req.body))
  }),
)

// Permanently delete an account. Without { force: true } only inactive ones (a suspended landlord,
// a tenant with no current rental). With force (Danger zone, typed confirmation): any landlord or tenant.
app.delete(
  '/api/admin/users/:id',
  handle(async (req, res) => {
    const me = await requireSuperadmin(req)
    res.json(await admin.deleteUser(db, me.id, req.params.id, req.body ?? {}))
  }),
)

// Main admin: run every health check now (they also run every 20 minutes)
app.post(
  '/api/admin/health',
  handle(async (req, res) => {
    await requireSuperadmin(req)
    res.json(await runHealthCheck(db, process.env, 'manual'))
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

// Broken or oversized request bodies: a short JSON answer, never a page with server details
// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  const status = err.status || err.statusCode || 500
  if (status >= 500) console.error(err)
  res.status(status).json({ error: status === 400 ? 'The request was not valid.' : status === 413 ? 'The request is too large.' : 'Server error' })
})

app.listen(PORT, () => {
  console.log(`Renta API on http://localhost:${PORT}`)
  console.log(`  supabase: ${db ? 'configured' : 'NOT configured'}`)
  startPushSender(db)
  startSmsSender(db)
  startHealthChecks(db)
})
