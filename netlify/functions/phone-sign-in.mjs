// Netlify Function: sign in with a PHONE NUMBER instead of an email.
// Same as POST /api/auth/phone-sign-in and /api/auth/phone-status in server/index.js,
// so the live site works without the Express server.
// The account's email is looked up here, so it is never revealed to the browser.
// Needs SUPABASE_SERVICE_ROLE_KEY in Netlify → Site configuration → Environment variables (scope: Functions).
//   POST { phone, password } → { accessToken, refreshToken }   normal sign-in
//   POST { phone }           → { tokenHash }                    landlord's first sign-in (no password yet)
//   POST { phone, check: true } → { status }                    live check while typing
import { createClient } from '@supabase/supabase-js'

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

const digits = (v) => String(v ?? '').replace(/\D/g, '')

function statusOf(p) {
  if (!p) return 'not_found'
  if (p.role === 'landlord' && !p.active) return 'suspended'
  if (p.role === 'landlord' && p.must_change_password) return 'first_login'
  if (p.role === 'tenant' && p.must_change_password) return 'tenant_first_login'
  return p.role === 'landlord' || p.role === 'tenant' ? p.role : 'not_found'
}

export default async (req) => {
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  const key = process.env.SUPABASE_SERVICE_ROLE_KEY
  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL || (key && urlFromKey(key))
  if (!key || !url) {
    return json({ error: 'Phone sign-in is not set up yet. Add SUPABASE_SERVICE_ROLE_KEY to the Netlify environment variables.' }, 500)
  }

  const body = await req.json().catch(() => ({}))
  const want = digits(body?.phone).slice(-9)
  const opts = { auth: { persistSession: false, autoRefreshToken: false } }
  const db = createClient(url, key, opts)

  let profile = null
  if (want.length >= 9) {
    const { data, error } = await db
      .from('profiles')
      .select('id, email, phone, role, active, must_change_password, created_at')
      .not('phone', 'is', null)
    if (error) return json({ error: error.message }, 500)
    profile =
      (data ?? [])
        .filter((p) => digits(p.phone).slice(-9) === want)
        .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)))[0] ?? null
  }
  const status = statusOf(profile)
  if (body?.check) return json({ status })

  if (status === 'not_found' || !profile?.email) return json({ error: 'No account uses this phone number.' }, 400)
  if (status === 'suspended') return json({ error: 'This account has been suspended. Please contact Renta UG.' }, 403)

  const password = String(body?.password ?? '')
  if ((status === 'first_login' || status === 'tenant_first_login') && !password) {
    const { data, error } = await db.auth.admin.generateLink({ type: 'magiclink', email: profile.email })
    if (error) return json({ error: error.message }, 400)
    return json({ tokenHash: data.properties.hashed_token })
  }
  if (!password) return json({ error: 'Please enter your password.' }, 400)

  const client = createClient(url, key, opts)
  const { data, error } = await client.auth.signInWithPassword({ email: profile.email, password })
  if (error) return json({ error: error.message }, 400)
  return json({ accessToken: data.session.access_token, refreshToken: data.session.refresh_token })
}
