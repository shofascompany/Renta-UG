// Sign-up with an emailed verification code, shared by the Express server and the Netlify Function.
//   start   { name, email, password }  → checks the details, emails a 6-character code (valid 20 minutes)
//   verify  { email, code }            → right code: creates the account and returns a one-time sign-in token
//   resend  { email }                  → a fresh code for a sign-up that is waiting
// The account does NOT exist until the code is entered, so nobody can register an email they don't own.
// The password waits in the database only encrypted, and is removed the moment the account is created.
import { createCipheriv, createDecipheriv, createHash, randomBytes, randomInt, timingSafeEqual } from 'node:crypto'
import { HttpError } from './admin.js'
import { sendMail } from './mailer.js'
import { verificationEmail } from './emailTemplates.js'
import { checkDeliverable } from './emailCheck.js'

export const CODE_MINUTES = 20
const CODE_LENGTH = 6
const MAX_TRIES = 5
const RESEND_AFTER_S = 45
const HOURLY_LIMIT = 150 // new codes per hour, across everyone: stops mail abuse
// Letters and numbers, without the look-alikes (0/O, 1/I/L)
const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'

const secret = () => process.env.SUPABASE_SERVICE_ROLE_KEY || ''
const newCode = () => Array.from({ length: CODE_LENGTH }, () => ALPHABET[randomInt(ALPHABET.length)]).join('')
const normalCode = (v) => String(v ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '')
const hashCode = (email, code) => createHash('sha256').update(`${email}:${normalCode(code)}:${secret()}`).digest('hex')
const normalEmail = (v) => String(v ?? '').trim().toLowerCase()

function encrypt(text) {
  const key = createHash('sha256').update(`renta-signup:${secret()}`).digest()
  const iv = randomBytes(12)
  const cipher = createCipheriv('aes-256-gcm', key, iv)
  const enc = Buffer.concat([cipher.update(text, 'utf8'), cipher.final()])
  return [iv, cipher.getAuthTag(), enc].map((b) => b.toString('base64')).join('.')
}
function decrypt(blob) {
  const [iv, tag, enc] = String(blob).split('.').map((s) => Buffer.from(s, 'base64'))
  const key = createHash('sha256').update(`renta-signup:${secret()}`).digest()
  const decipher = createDecipheriv('aes-256-gcm', key, iv)
  decipher.setAuthTag(tag)
  return Buffer.concat([decipher.update(enc), decipher.final()]).toString('utf8')
}

function dbError(error) {
  if (!error) return
  if (/email_verifications/.test(error.message) && /schema cache|does not exist|relation/i.test(error.message)) {
    throw new HttpError(500, 'The database needs updating: run database/update_existing.sql in Supabase → SQL Editor.')
  }
  throw error
}

async function emailCode(email, name, code) {
  const { subject, html, text } = verificationEmail({ name, code, minutes: CODE_MINUTES })
  await sendMail({ to: email, subject, text, html })
}

// Step 1: details in, code out.
export async function start(db, body) {
  const name = String(body?.name ?? '').trim()
  const email = normalEmail(body?.email)
  const password = String(body?.password ?? '')
  if (name.length < 2) throw new HttpError(400, 'Enter your full name.')
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) throw new HttpError(400, 'Enter a valid email address.')
  if (password.length < 8 || !/[A-Za-z]/.test(password) || !/\d/.test(password)) {
    throw new HttpError(400, 'Your password needs at least 8 characters, with letters and numbers.')
  }
  await checkDeliverable(email) // typos like gmial.com, or a domain that can't get mail

  const { data: taken, error: tErr } = await db.from('profiles').select('id').ilike('email', email.replace(/[\\%_]/g, '\\$&')).limit(1).maybeSingle() // same email in any letter case
  if (tErr) throw tErr
  if (taken) throw new HttpError(409, 'An account with this email already exists. Please sign in instead.')

  const { data: existing, error: eErr } = await db.from('email_verifications').select('sent_at').eq('email', email).maybeSingle()
  dbError(eErr)
  const wait = existing ? RESEND_AFTER_S - Math.floor((Date.now() - new Date(existing.sent_at).getTime()) / 1000) : 0
  if (wait > 0) throw new HttpError(429, `A code was just sent. You can ask for a new one in ${wait} seconds.`)

  await checkHourlyLimit(db)
  const code = newCode()
  const { error } = await db.from('email_verifications').upsert({
    email,
    full_name: name,
    password_enc: encrypt(password),
    code_hash: hashCode(email, code),
    expires_at: new Date(Date.now() + CODE_MINUTES * 60_000).toISOString(),
    attempts: 0,
    sent_at: new Date().toISOString(),
  })
  dbError(error)

  try {
    await emailCode(email, name, code)
  } catch (e) {
    await db.from('email_verifications').delete().eq('email', email)
    throw e
  }
  return { email, expiresInMinutes: CODE_MINUTES, resendAfterSeconds: RESEND_AFTER_S }
}

async function checkHourlyLimit(db) {
  const since = new Date(Date.now() - 3_600_000).toISOString()
  const { count } = await db.from('email_verifications').select('email', { count: 'exact', head: true }).gte('sent_at', since)
  if ((count ?? 0) >= HOURLY_LIMIT) throw new HttpError(429, 'Too many sign-ups right now. Please try again in a few minutes.')
}

// Step 2: right code → the account is created and a one-time token signs the browser in.
export async function verify(db, body) {
  const email = normalEmail(body?.email)
  const code = normalCode(body?.code)
  if (code.length !== CODE_LENGTH) throw new HttpError(400, `Enter the ${CODE_LENGTH}-character code from your email.`)

  const { data: row, error } = await db.from('email_verifications').select('*').eq('email', email).maybeSingle()
  dbError(error)
  if (!row) throw new HttpError(400, 'No sign-up is waiting for this email. Please start again.')
  if (new Date(row.expires_at).getTime() < Date.now()) {
    await db.from('email_verifications').delete().eq('email', email)
    throw new HttpError(410, `This code has expired (codes last ${CODE_MINUTES} minutes). Request a new one.`)
  }
  if (row.attempts >= MAX_TRIES) throw new HttpError(429, 'Too many wrong tries. Request a new code.')

  const a = Buffer.from(hashCode(email, code))
  const b = Buffer.from(row.code_hash)
  if (a.length !== b.length || !timingSafeEqual(a, b)) {
    await db.from('email_verifications').update({ attempts: row.attempts + 1 }).eq('email', email)
    const left = MAX_TRIES - row.attempts - 1
    throw new HttpError(400, left > 0 ? `That code is not right. ${left} ${left === 1 ? 'try' : 'tries'} left.` : 'Too many wrong tries. Request a new code.')
  }

  const created = await db.auth.admin.createUser({
    email,
    password: decrypt(row.password_enc),
    email_confirm: true,
    user_metadata: { full_name: row.full_name },
  })
  if (created.error) {
    if (/already|registered|exists/i.test(created.error.message)) {
      await db.from('email_verifications').delete().eq('email', email)
      throw new HttpError(409, 'An account with this email already exists. Please sign in instead.')
    }
    throw new HttpError(400, created.error.message)
  }
  await db.from('email_verifications').delete().eq('email', email)

  const { data, error: linkError } = await db.auth.admin.generateLink({ type: 'magiclink', email })
  if (linkError) throw new HttpError(400, linkError.message)
  return { tokenHash: data.properties.hashed_token }
}

// A fresh code for a sign-up that is waiting (the old one stops working).
export async function resend(db, body) {
  const email = normalEmail(body?.email)
  const { data: row, error } = await db.from('email_verifications').select('*').eq('email', email).maybeSingle()
  dbError(error)
  if (!row) throw new HttpError(400, 'No sign-up is waiting for this email. Please start again.')
  const wait = RESEND_AFTER_S - Math.floor((Date.now() - new Date(row.sent_at).getTime()) / 1000)
  if (wait > 0) throw new HttpError(429, `You can ask for a new code in ${wait} seconds.`)

  await checkHourlyLimit(db)
  const code = newCode()
  const { error: uErr } = await db
    .from('email_verifications')
    .update({
      code_hash: hashCode(email, code),
      expires_at: new Date(Date.now() + CODE_MINUTES * 60_000).toISOString(),
      attempts: 0,
      sent_at: new Date().toISOString(),
    })
    .eq('email', email)
  dbError(uErr)
  await emailCode(email, row.full_name, code)
  return { email, expiresInMinutes: CODE_MINUTES, resendAfterSeconds: RESEND_AFTER_S }
}
