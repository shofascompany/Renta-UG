// Main-admin account management, shared by the Express server (server/index.js) and the
// Netlify Function (netlify/functions/admin.mjs), so it works locally AND on the live site.
// `db` is a Supabase client created with the SERVICE ROLE key: never use this in the browser.
import { randomBytes } from 'node:crypto'

export class HttpError extends Error {
  constructor(status, message) {
    super(message)
    this.status = status
  }
}

const BAN_FOREVER = '876000h' // ~100 years

// Unusable random password: first-time landlords sign in by email only, then set their own.
export const placeholderPassword = () => randomBytes(24).toString('base64url')

function check(error) {
  if (error) throw new HttpError(500, error.message)
}

// The signed-in user behind a "Bearer <token>" header, who must be the main admin.
export async function requireSuperadmin(db, authorization) {
  const token = authorization?.replace(/^Bearer\s+/i, '')
  if (!token) throw new HttpError(401, 'Not signed in.')
  const { data, error } = await db.auth.getUser(token)
  if (error || !data.user) throw new HttpError(401, 'Session expired. Please sign in again.')
  const { data: profile, error: pErr } = await db.from('profiles').select('role').eq('id', data.user.id).maybeSingle()
  check(pErr)
  if (profile?.role !== 'superadmin') throw new HttpError(403, 'Only the main admin can do this.')
  return data.user
}

// Register a landlord: creates their login and marks them for a password-free first sign-in.
export async function createLandlord(db, body) {
  const name = body?.name?.trim()
  const email = body?.email?.trim().toLowerCase()
  const phone = body?.phone?.trim() || null
  if (!name || !email) throw new HttpError(400, 'Name and email are required.')

  const { data, error } = await db.auth.admin.createUser({
    email,
    password: placeholderPassword(), // never used: they set their own on first sign-in
    email_confirm: true,
    user_metadata: { full_name: name },
  })
  if (error) {
    const taken = /already|registered|exists/i.test(error.message)
    throw new HttpError(400, taken ? 'An account with this email already exists.' : error.message)
  }

  const { error: pErr } = await db
    .from('profiles')
    .upsert({ id: data.user.id, email, full_name: name, phone, role: 'landlord', active: true, must_change_password: true })
  check(pErr)
  return { id: data.user.id }
}

// Update a landlord's details, reset their password (→ first sign-in again), or suspend / reactivate.
export async function updateLandlord(db, id, body) {
  const { data: target, error: tErr } = await db.from('profiles').select('role').eq('id', id).maybeSingle()
  check(tErr)
  if (target?.role !== 'landlord') throw new HttpError(404, 'Landlord not found.')

  const { name, phone, resetPassword, active } = body ?? {}
  const authAttrs = {}
  const profile = {}
  if (typeof name === 'string' && name.trim()) {
    profile.full_name = name.trim()
    authAttrs.user_metadata = { full_name: name.trim() }
  }
  if (typeof phone === 'string') profile.phone = phone.trim() || null
  if (resetPassword === true) {
    authAttrs.password = placeholderPassword()
    profile.must_change_password = true
  }
  if (typeof active === 'boolean') {
    profile.active = active
    authAttrs.ban_duration = active ? 'none' : BAN_FOREVER
  }

  if (Object.keys(authAttrs).length) {
    const { error } = await db.auth.admin.updateUserById(id, authAttrs)
    if (error) throw new HttpError(400, error.message)
  }
  if (Object.keys(profile).length) {
    const { error } = await db.from('profiles').update(profile).eq('id', id)
    check(error)
  }
  return { ok: true }
}

// ── Tenants without a smartphone → app access ─────────────────────────────
// A tenant managed by their landlord has no app account. When they get a smartphone, the landlord
// gives them app access: we create their login straight away (already linked to the landlord, so
// no connection code). They sign in with their PHONE NUMBER the first time, then add their email
// and choose a password (completeTenantAccount).

// Stand-in email until the tenant adds their own (never shown, never emailed).
export const PHONE_ONLY_EMAIL_DOMAIN = 'phone-signin.example.com'
export const isPlaceholderEmail = (email) => String(email ?? '').endsWith(`@${PHONE_ONLY_EMAIL_DOMAIN}`)
const last9 = (v) => String(v ?? '').replace(/\D/g, '').slice(-9)

// The signed-in user behind a "Bearer <token>" header + their profile.
export async function requireUserProfile(db, authorization) {
  const token = authorization?.replace(/^Bearer\s+/i, '')
  if (!token) throw new HttpError(401, 'Not signed in.')
  const { data, error } = await db.auth.getUser(token)
  if (error || !data.user) throw new HttpError(401, 'Session expired. Please sign in again.')
  const { data: profile, error: pErr } = await db
    .from('profiles')
    .select('id, role, active, must_change_password, full_name')
    .eq('id', data.user.id)
    .maybeSingle()
  check(pErr)
  return { user: data.user, profile }
}

// Landlord gives one of their tenants app access (sign-in with their phone number).
export async function giveTenantAppAccess(db, landlordId, tenantId) {
  const { data: t, error } = await db
    .from('tenants')
    .select('id, landlord_id, user_id, property_id, full_name, phone')
    .eq('id', tenantId)
    .maybeSingle()
  check(error)
  if (!t || t.landlord_id !== landlordId) throw new HttpError(404, 'Tenant not found.')
  if (!t.property_id) throw new HttpError(400, 'This tenant is not renting a house right now.')
  if (t.user_id) throw new HttpError(400, 'This tenant already has app access.')
  if (last9(t.phone).length < 9) throw new HttpError(400, "Add the tenant's phone number first. They sign in with it.")

  // The phone number must not already belong to another account
  const { data: others, error: oErr } = await db.from('profiles').select('id, phone').not('phone', 'is', null)
  check(oErr)
  if ((others ?? []).some((p) => last9(p.phone) === last9(t.phone))) {
    throw new HttpError(400, 'This phone number is already used by another Renta account.')
  }

  const email = `tenant-${t.id}@${PHONE_ONLY_EMAIL_DOMAIN}`
  const { data: created, error: cErr } = await db.auth.admin.createUser({
    email,
    password: placeholderPassword(), // never used: they set their own on first sign-in
    email_confirm: true,
    user_metadata: { full_name: t.full_name },
  })
  if (cErr) throw new HttpError(400, cErr.message)
  const userId = created.user.id

  const { error: pErr } = await db.from('profiles').upsert({
    id: userId,
    email,
    full_name: t.full_name,
    phone: t.phone,
    role: 'tenant',
    must_change_password: true,
  })
  if (pErr) {
    await db.auth.admin.deleteUser(userId)
    check(pErr)
  }

  // Link the login to the tenant record: no connection code needed
  const { error: lErr } = await db
    .from('tenants')
    .update({ user_id: userId, managed_by_landlord: false, connect_code: null, connect_code_expires_at: null })
    .eq('id', t.id)
  if (lErr) {
    await db.auth.admin.deleteUser(userId)
    check(lErr)
  }
  return { ok: true, phone: t.phone }
}

// Tenant's first sign-in (after app access was given): add their email and choose a password.
export async function completeTenantAccount(db, user, profile, body) {
  if (profile?.role !== 'tenant' || !profile.must_change_password) {
    throw new HttpError(400, 'Your account is already set up.')
  }
  const email = String(body?.email ?? '').trim().toLowerCase()
  const password = String(body?.password ?? '')
  if (!/^[^\s@]+@[^\s@]+\.[a-z]{2,}$/i.test(email)) throw new HttpError(400, 'Enter a valid email address.')
  if (isPlaceholderEmail(email)) throw new HttpError(400, 'Enter your own email address.')
  if (password.length < 8) throw new HttpError(400, 'Your password needs at least 8 characters.')

  const { data: taken, error: tErr } = await db.from('profiles').select('id').ilike('email', email).neq('id', user.id).limit(1)
  check(tErr)
  if (taken?.length) throw new HttpError(400, 'This email is already used by another account.')

  const { error } = await db.auth.admin.updateUserById(user.id, { email, email_confirm: true, password })
  if (error) {
    const dup = /already|registered|exists/i.test(error.message)
    throw new HttpError(400, dup ? 'This email is already used by another account.' : error.message)
  }
  const { error: pErr } = await db.from('profiles').update({ email, must_change_password: false }).eq('id', user.id)
  check(pErr)
  await db.from('tenants').update({ email }).eq('user_id', user.id)
  return { ok: true, email }
}

// Permanently delete an inactive account: a suspended landlord, or a tenant with no current rental.
// Main admin: archive everything, then delete every landlord + tenant (data AND login accounts).
// The main admin types the exact phrase to confirm. The archive stays readable by the main admin only.
export const CLEAR_PHRASE = 'DELETE ALL USERS'
export async function archiveAndClear(db, meId, body) {
  if (String(body?.confirm ?? '').trim().toUpperCase() !== CLEAR_PHRASE) {
    throw new HttpError(400, `Type ${CLEAR_PHRASE} to confirm.`)
  }
  const { data, error } = await db.rpc('admin_archive_and_clear', { p_actor: meId, p_note: body?.note ?? null })
  if (error) {
    if (/could not find the function|does not exist/i.test(error.message)) {
      throw new HttpError(500, 'This needs a database update: run database/update_existing.sql in Supabase.')
    }
    throw new HttpError(500, error.message)
  }
  // Remove the login accounts too (their data is already archived and cleared)
  const failed = []
  for (const id of data.user_ids ?? []) {
    if (id === meId) continue
    const { error: dErr } = await db.auth.admin.deleteUser(id)
    if (dErr && !/not found/i.test(dErr.message)) failed.push(id)
  }
  return { archiveId: data.archive_id, counts: data.counts, accountsDeleted: (data.user_ids?.length ?? 0) - failed.length, failed: failed.length }
}

export async function deleteUser(db, meId, id) {
  if (id === meId) throw new HttpError(400, 'You cannot delete the main admin account.')
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
  if (delErr) throw new HttpError(400, delErr.message)
  return { ok: true }
}
