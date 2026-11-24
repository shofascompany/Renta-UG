// Netlify Function: a landlord's FIRST sign-in: email + the one-time setup code from Renta UG
// (shown to the main admin when the landlord was registered, and emailed to the landlord).
// Same as POST /api/auth/first-login in server/index.js. Logic in server/signIn.js.
// Needs SUPABASE_SERVICE_ROLE_KEY in Netlify → Site configuration → Environment variables (scope: Functions).
import { createClient } from '@supabase/supabase-js'
import { HttpError } from '../../server/admin.js'
import { firstLoginByEmail } from '../../server/signIn.js'

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

  const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } })
  try {
    const body = await req.json().catch(() => ({}))
    return json(await firstLoginByEmail(db, body))
  } catch (e) {
    if (!(e instanceof HttpError)) console.error(e)
    return json({ error: e instanceof HttpError ? e.message : 'Something went wrong. Please try again.' }, e.status || 500)
  }
}
