// Netlify Function: the main admin's landlord / account management on the live site.
//   POST   /api/admin/landlords       → register a landlord (first sign-in without a password)
//   PATCH  /api/admin/landlords/:id   → edit, reset password, suspend / reactivate
//   DELETE /api/admin/users/:id       → delete an inactive account
//   POST   /api/admin/clear           → archive everything, then delete every landlord + tenant
// Same rules as the Express server (both use server/admin.js).
// Needs SUPABASE_SERVICE_ROLE_KEY in Netlify → Site configuration → Environment variables (scope: Functions).
import { createClient } from '@supabase/supabase-js'
import { HttpError, requireSuperadmin, createLandlord, updateLandlord, deleteUser, archiveAndClear } from '../../server/admin.js'

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
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY
  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL || (key && urlFromKey(key))
  if (!key || !url) {
    return json({ error: 'Admin actions are not set up yet. Add SUPABASE_SERVICE_ROLE_KEY to the Netlify environment variables.' }, 500)
  }
  const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } })

  // Works with both the original path (/api/admin/...) and the rewritten one (/.netlify/functions/admin/...)
  const route = new URL(req.url).pathname.match(/\/(landlords|users|clear)(?:\/([^/]+))?\/?$/)
  const [, resource, id] = route ?? []

  try {
    const me = await requireSuperadmin(db, req.headers.get('authorization'))
    const body = req.method === 'DELETE' ? {} : await req.json().catch(() => ({}))

    if (req.method === 'POST' && resource === 'landlords' && !id) return json(await createLandlord(db, body))
    if (req.method === 'PATCH' && resource === 'landlords' && id) return json(await updateLandlord(db, id, body))
    if (req.method === 'DELETE' && resource === 'users' && id) return json(await deleteUser(db, me.id, id))
    if (req.method === 'POST' && resource === 'clear') return json(await archiveAndClear(db, me.id, body))
    return json({ error: 'Not found' }, 404)
  } catch (e) {
    if (!(e instanceof HttpError)) console.error(e)
    return json({ error: e.message || 'Server error' }, e.status || 500)
  }
}
