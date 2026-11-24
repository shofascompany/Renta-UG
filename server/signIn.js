// Sign-in safety, shared by the Express server (server/index.js) and the Netlify Functions.
//
// · First sign-in (a landlord registered by the main admin, or a tenant given app access by their
//   landlord): email or phone only, no code (by the owner's choice), then they create their password.
//   (issueSetupCode / redeemSetupCode are kept but no longer used by any sign-in.)
// · Phone sign-in (password checked here on the server): 5 wrong passwords lock that account's phone
//   sign-in for 15 minutes, so passwords can't be guessed endlessly through this route.
import { createHash, randomInt } from 'node:crypto'
import { HttpError } from './admin.js'

const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' // no 0/O/1/I
const CODE_LENGTH = 6
const CODE_DAYS = 7
const CODE_TRIES = 5
const MAX_FAILS = 5
const LOCK_MINUTES = 15

const hash = (userId, code) => createHash('sha256').update(`${userId}:${String(code).toUpperCase()}`).digest('hex')
const cleanCode = (v) => String(v ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '')
const NEEDS_DB = 'This needs a database update: run database/update_existing.sql in Supabase.'
const dbError = (error) => new HttpError(500, /setup_codes|login_failures|does not exist|schema cache/i.test(error.message) ? NEEDS_DB : error.message)

// New code for an account (replaces any older one). Returns the plain code, to show / send once.
export async function issueSetupCode(db, userId) {
  const code = Array.from({ length: CODE_LENGTH }, () => ALPHABET[randomInt(ALPHABET.length)]).join('')
  const { error } = await db.from('setup_codes').upsert({
    user_id: userId,
    code_hash: hash(userId, code),
    expires_at: new Date(Date.now() + CODE_DAYS * 86_400_000).toISOString(),
    attempts: 0,
    created_at: new Date().toISOString(),
  })
  if (error) throw dbError(error)
  return code
}

// Checks the code; right → one-time sign-in token for the browser (the app then asks for a new password).
async function redeemSetupCode(db, profile, code) {
  const typed = cleanCode(code)
  if (typed.length !== CODE_LENGTH) throw new HttpError(400, 'Enter the 6-character setup code you were given.')
  const { data: row, error } = await db.from('setup_codes').select('*').eq('user_id', profile.id).maybeSingle()
  if (error) throw dbError(error)
  if (!row || new Date(row.expires_at) < new Date()) {
    throw new HttpError(400, 'This setup code has expired. Ask for a new one (landlords: Renta UG; tenants: your landlord).')
  }
  if (row.attempts >= CODE_TRIES) throw new HttpError(429, 'Too many wrong tries. Ask for a new setup code.')
  if (row.code_hash !== hash(profile.id, typed)) {
    await db.from('setup_codes').update({ attempts: row.attempts + 1 }).eq('user_id', profile.id)
    const left = CODE_TRIES - row.attempts - 1
    throw new HttpError(400, left > 0 ? `That setup code is not right. ${left} ${left === 1 ? 'try' : 'tries'} left.` : 'Too many wrong tries. Ask for a new setup code.')
  }
  await db.from('setup_codes').delete().eq('user_id', profile.id)
  return oneTimeSignIn(db, profile)
}

// One-time sign-in token for the browser (the app then asks for a new password)
async function oneTimeSignIn(db, profile) {
  const { data, error: linkError } = await db.auth.admin.generateLink({ type: 'magiclink', email: profile.email })
  if (linkError) throw new HttpError(400, linkError.message)
  return { tokenHash: data.properties.hashed_token }
}

// ── Wrong-password lockout ──
async function assertNotLocked(db, key) {
  const { data, error } = await db.from('login_failures').select('locked_until').eq('key', key).maybeSingle()
  if (error) throw dbError(error)
  const until = data?.locked_until ? new Date(data.locked_until) : null
  if (until && until > new Date()) {
    const mins = Math.ceil((until - Date.now()) / 60_000)
    throw new HttpError(429, `Too many wrong passwords. Try again in ${mins} minute${mins === 1 ? '' : 's'}, or use "Forgot password?".`)
  }
}
async function recordFailure(db, key) {
  const { data } = await db.from('login_failures').select('fails, locked_until').eq('key', key).maybeSingle()
  const expired = data?.locked_until && new Date(data.locked_until) <= new Date()
  const fails = (expired ? 0 : data?.fails ?? 0) + 1
  const locked = fails >= MAX_FAILS
  await db.from('login_failures').upsert({
    key,
    fails: locked ? 0 : fails,
    locked_until: locked ? new Date(Date.now() + LOCK_MINUTES * 60_000).toISOString() : null,
    updated_at: new Date().toISOString(),
  })
}
const clearFailures = (db, key) => db.from('login_failures').delete().eq('key', key)

// ── Lookups ──
const digits = (v) => String(v ?? '').replace(/\D/g, '')

export async function profileByPhone(db, phone) {
  const want = digits(phone).slice(-9)
  if (want.length < 9) return null
  // Numbers are stored in many formats (0772 123 456, +256…), so compare digits here
  const { data, error } = await db
    .from('profiles')
    .select('id, email, phone, role, active, must_change_password, created_at')
    .not('phone', 'is', null)
  if (error) throw new HttpError(500, error.message)
  return (
    (data ?? [])
      .filter((p) => digits(p.phone).slice(-9) === want)
      .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)))[0] ?? null
  )
}

export function phoneStatus(p) {
  if (!p) return 'not_found'
  if (p.role === 'landlord' && !p.active) return 'suspended'
  if (p.role === 'landlord' && p.must_change_password) return 'first_login'
  if (p.role === 'tenant' && p.must_change_password) return 'tenant_first_login'
  return p.role === 'landlord' || p.role === 'tenant' ? p.role : 'not_found'
}

// POST { email } → { tokenHash }: a landlord's first sign-in by email (no setup code for landlords)
export async function firstLoginByEmail(db, body) {
  const email = String(body?.email ?? '').trim().toLowerCase()
  if (!email) throw new HttpError(400, 'Enter your email.')
  const { data: profile, error } = await db
    .from('profiles')
    .select('id, email, role, active, must_change_password')
    .eq('email', email)
    .maybeSingle()
  if (error) throw new HttpError(500, error.message)
  if (!(profile?.role === 'landlord' && profile.active && profile.must_change_password)) {
    throw new HttpError(400, 'Please enter your password.')
  }
  return oneTimeSignIn(db, profile)
}

// POST { phone, password } → { accessToken, refreshToken }   normal sign-in
// POST { phone, setupCode } → { tokenHash }                  first sign-in (no password yet)
// POST { phone, check: true } → { status }                   live check while typing
// `signInClient` is a throwaway Supabase client used only to check the password.
export async function phoneSignIn(db, signInClient, body) {
  const profile = await profileByPhone(db, body?.phone)
  const status = phoneStatus(profile)
  if (body?.check) return { status }
  if (status === 'not_found' || !profile?.email) throw new HttpError(400, 'No account uses this phone number.')
  if (status === 'suspended') throw new HttpError(403, 'This account has been suspended. Please contact Renta UG.')

  // First sign-in (landlord, or tenant given app access): no code, straight to creating a password
  if (status === 'first_login' || status === 'tenant_first_login') return oneTimeSignIn(db, profile)

  const password = String(body?.password ?? '')
  if (!password) throw new HttpError(400, 'Please enter your password.')
  const key = `phone:${digits(profile.phone).slice(-9)}`
  await assertNotLocked(db, key)
  const { data, error } = await signInClient.auth.signInWithPassword({ email: profile.email, password })
  if (error) {
    if (/invalid login/i.test(error.message)) await recordFailure(db, key)
    throw new HttpError(400, error.message)
  }
  await clearFailures(db, key)
  return { accessToken: data.session.access_token, refreshToken: data.session.refresh_token }
}
