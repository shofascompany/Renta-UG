// Netlify Function: mobile money rent payments on the live site. Same as server/index.js:
//   POST /api/payments/info            → are online payments on?
//   POST /api/momo/pay                 → pay one rent charge
//   POST /api/momo/status              → poll a payment while the tenant approves it
//   POST /api/momo/recharge-quote      → price of N months
//   POST /api/momo/recharge            → pay unpaid rent + N months ahead
//   POST /api/momo/relworx-webhook     → Relworx says a payment finished (re-checked with Relworx)
//   POST /api/momo/webhook             → Flutterwave webhook (if Flutterwave is used instead)
// Needs in Netlify → Site configuration → Environment variables (scope: Functions):
//   SUPABASE_SERVICE_ROLE_KEY, RELWORX_API_KEY, RELWORX_ACCOUNT_NO
import { createClient } from '@supabase/supabase-js'
import { HttpError } from '../../server/admin.js'
import * as payments from '../../server/payments.js'

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

const TENANT_ROUTES = {
  pay: payments.pay,
  status: payments.status,
  'recharge-quote': payments.rechargeQuote,
  recharge: payments.recharge,
}

export default async (req) => {
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)
  const path = new URL(req.url).pathname
  if (/\/info\/?$/.test(path)) return json(payments.info())

  const key = process.env.SUPABASE_SERVICE_ROLE_KEY
  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL || (key && urlFromKey(key))
  if (!key || !url) return json({ error: 'Not set up yet. Add SUPABASE_SERVICE_ROLE_KEY to the Netlify environment variables.' }, 500)
  const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } })

  try {
    const body = await req.json().catch(() => ({}))
    const name = path.split('/').filter(Boolean).at(-1)

    if (name === 'relworx-webhook') return json(await payments.relworxWebhook(db, body))
    if (name === 'webhook') return json(await payments.flutterwaveWebhook(db, body, req.headers.get('verif-hash')))

    const handler = TENANT_ROUTES[name]
    if (!handler) return json({ error: 'Not found' }, 404)
    const user = await payments.requireUser(db, req.headers.get('authorization'))
    return json(await handler(db, user, body))
  } catch (e) {
    if (!(e instanceof HttpError)) console.error(e)
    return json({ error: e.message || 'Server error' }, e.status || 500)
  }
}
