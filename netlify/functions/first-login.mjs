// Netlify Function: a landlord's FIRST sign-in (email only, no password yet).
// Same as POST /api/auth/first-login in server/index.js, so the live site works without the Express server.
// Needs SUPABASE_SERVICE_ROLE_KEY in Netlify → Site configuration → Environment variables (scope: Functions).
// NOTE: by design, a landlord who hasn't set a password yet can be signed in with just their email,
// until they choose a password on the next page.
import { createClient } from '@supabase/supabase-js'

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })

// The project URL is inside the service key ("ref"), so only one variable has to be set.
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

  const key = process.env.SUPABASE_SERVICE_ROLE_KEY
  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL || (key && urlFromKey(key))
  if (!key || !url) {
    return json({ error: 'First sign-in is not set up yet. Add SUPABASE_SERVICE_ROLE_KEY to the Netlify environment variables.' }, 500)
  }

  const body = await req.json().catch(() => ({}))
  const email = String(body?.email ?? '').trim().toLowerCase()
  if (!email) return json({ error: 'Enter your email.' }, 400)

  const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } })

  const { data: profile, error } = await db
    .from('profiles')
    .select('id, role, active, must_change_password')
    .eq('email', email)
    .maybeSingle()
  if (error) return json({ error: error.message }, 500)
  if (!(profile?.role === 'landlord' && profile.active && profile.must_change_password)) {
    return json({ error: 'Please enter your password.' }, 400)
  }

  const { data, error: linkError } = await db.auth.admin.generateLink({ type: 'magiclink', email })
  if (linkError) return json({ error: linkError.message }, 400)
  return json({ tokenHash: data.properties.hashed_token })
}
