// Netlify Function: sign in with a PHONE NUMBER instead of an email.
// Same as POST /api/auth/phone-sign-in in server/index.js; logic in server/signIn.js.
// The account's email is looked up here, so it is never revealed to the browser.
// Needs SUPABASE_SERVICE_ROLE_KEY in Netlify → Site configuration → Environment variables (scope: Functions).
//   POST { phone, password }   → { accessToken, refreshToken }   normal sign-in (5 wrong → 15 min lock)
//   POST { phone, setupCode }  → { tokenHash }                    first sign-in with the one-time setup code
//   POST { phone, check: true } → { status }                      live check while typing
import { createClient } from '@supabase/supabase-js'
import { HttpError } from '../../server/admin.js'
import { phoneSignIn } from '../../server/signIn.js'

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

  const key = process.env.SUPABASE_SERVICE_ROLE_KEY
  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL || (key && urlFromKey(key))
  if (!key || !url) {
    return json({ error: 'Phone sign-in is not set up yet. Add SUPABASE_SERVICE_ROLE_KEY to the Netlify environment variables.' }, 500)
  }

  const opts = { auth: { persistSession: false, autoRefreshToken: false } }
  try {
    const body = await req.json().catch(() => ({}))
    // Second, throwaway client only for the password check, so the admin client never holds a user session
    return json(await phoneSignIn(createClient(url, key, opts), createClient(url, key, opts), body))
  } catch (e) {
    if (!(e instanceof HttpError)) console.error(e)
    return json({ error: e instanceof HttpError ? e.message : 'Something went wrong. Please try again.' }, e.status || 500)
  }
}
