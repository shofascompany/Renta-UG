// Netlify Function: tenants without a smartphone → app access. Same as server/index.js:
//   POST /api/landlord/tenants/:id/app-access → landlord creates the tenant's login (phone sign-in)
//   POST /api/auth/complete-tenant            → tenant's first sign-in: add email + choose password
// Needs SUPABASE_SERVICE_ROLE_KEY in Netlify → Site configuration → Environment variables (scope: Functions).
import { createClient } from '@supabase/supabase-js'
import { HttpError, requireUserProfile, giveTenantAppAccess, completeTenantAccount } from '../../server/admin.js'

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
  if (!key || !url) return json({ error: 'Not set up yet. Add SUPABASE_SERVICE_ROLE_KEY to the Netlify environment variables.' }, 500)
  const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } })

  const path = new URL(req.url).pathname
  try {
    const { user, profile } = await requireUserProfile(db, req.headers.get('authorization'))
    const body = await req.json().catch(() => ({}))

    const access = path.match(/\/tenants\/([^/]+)\/app-access\/?$/)
    if (access) {
      if (profile?.role !== 'landlord' || !profile.active) throw new HttpError(403, 'Only landlords can do this.')
      return json(await giveTenantAppAccess(db, user.id, access[1]))
    }
    if (/complete-tenant\/?$/.test(path)) return json(await completeTenantAccount(db, user, profile, body))
    return json({ error: 'Not found' }, 404)
  } catch (e) {
    if (!(e instanceof HttpError)) console.error(e)
    return json({ error: e.message || 'Server error' }, e.status || 500)
  }
}
