// Netlify Function: opens a link a landlord sent on WhatsApp. Same as POST /api/invite/open in server/index.js.
//   POST /api/invite/open { token, device } → { status }   (the link itself is made in tenant-account.mjs)
// Needs SUPABASE_SERVICE_ROLE_KEY in Netlify → Site configuration → Environment variables (scope: Functions).
import { createClient } from '@supabase/supabase-js'
import { HttpError } from '../../server/admin.js'
import { openInvite } from '../../server/invite.js'

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } })

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
  if (!key || !url) return json({ error: 'Not set up yet. Add SUPABASE_SERVICE_ROLE_KEY to the Netlify environment variables.' }, 500)
  const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } })
  try {
    return json(await openInvite(db, await req.json().catch(() => ({}))))
  } catch (e) {
    if (!(e instanceof HttpError)) console.error(e)
    return json({ error: e.message || 'Server error' }, e.status || 500)
  }
}
