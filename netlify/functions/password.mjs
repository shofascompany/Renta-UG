// Netlify Function: "forgot password". Same as POST /api/password/forgot in server/index.js.
//   POST /api/password/forgot { email } → emails a reset link (sent by the app, not Supabase)
// Needs (Netlify → Environment variables, scope: Functions): SUPABASE_SERVICE_ROLE_KEY, and email sending:
//   SMTP_USER + SMTP_PASS (Gmail app password)  or  RESEND_API_KEY + MAIL_FROM
import { createClient } from '@supabase/supabase-js'
import { HttpError } from '../../server/admin.js'
import { forgot } from '../../server/passwordReset.js'

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
  if (new URL(req.url).pathname.split('/').filter(Boolean).at(-1) !== 'forgot') return json({ error: 'Not found' }, 404)

  const key = process.env.SUPABASE_SERVICE_ROLE_KEY
  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL || (key && urlFromKey(key))
  if (!key || !url) return json({ error: 'Password reset is not set up yet. Add SUPABASE_SERVICE_ROLE_KEY to the Netlify environment variables.' }, 500)
  const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } })

  try {
    const body = await req.json().catch(() => ({}))
    return json(await forgot(db, body))
  } catch (e) {
    if (!(e instanceof HttpError)) console.error(e)
    return json({ error: e.message || 'Server error' }, e.status || 500)
  }
}
