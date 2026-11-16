// Netlify Function: sign up with an emailed 6-character code. Same as POST /api/signup/* in server/index.js.
//   POST /api/signup/start   { name, email, password } → emails a code (valid 20 minutes)
//   POST /api/signup/verify  { email, code }           → creates the account, returns a one-time sign-in token
//   POST /api/signup/resend  { email }                 → a new code
// Needs (Netlify → Environment variables, scope: Functions): SUPABASE_SERVICE_ROLE_KEY, and email sending:
//   SMTP_USER + SMTP_PASS (Gmail app password)  or  RESEND_API_KEY + MAIL_FROM
import { createClient } from '@supabase/supabase-js'
import { HttpError } from '../../server/admin.js'
import * as verifyEmail from '../../server/verify.js'

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })

function urlFromKey(key) {
  try {
    const { ref } = JSON.parse(Buffer.from(key.split('.')[1], 'base64url').toString())
    return ref ? `https://${ref}.supabase.co` : null
  } catch {
    return null
  }
}

export default async (req) => {
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)
  const step = new URL(req.url).pathname.split('/').filter(Boolean).at(-1)
  if (!['start', 'verify', 'resend'].includes(step)) return json({ error: 'Not found' }, 404)

  const key = process.env.SUPABASE_SERVICE_ROLE_KEY
  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL || (key && urlFromKey(key))
  if (!key || !url) return json({ error: 'Sign-up is not set up yet. Add SUPABASE_SERVICE_ROLE_KEY to the Netlify environment variables.' }, 500)
  const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } })

  try {
    const body = await req.json().catch(() => ({}))
    return json(await verifyEmail[step](db, body))
  } catch (e) {
    if (!(e instanceof HttpError)) console.error(e)
    return json({ error: e.message || 'Server error' }, e.status || 500)
  }
}