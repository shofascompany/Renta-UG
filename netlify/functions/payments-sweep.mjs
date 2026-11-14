// Netlify Scheduled Function: every minute, confirm mobile money payments that are still waiting,
// so rent is updated even if the tenant closed the app and no webhook arrived.
// (On your own computer, `npm run server` does the same every 15 seconds.)
import { createClient } from '@supabase/supabase-js'
import * as payments from '../../server/payments.js'

export default async () => {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY
  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL
  if (!key || !url) return
  const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } })
  try {
    const n = await payments.checkPending(db)
    if (n) console.log(`[payments-sweep] checked ${n} waiting payment(s)`)
  } catch (e) {
    console.warn(`[payments-sweep] ${e.message}`)
  }
}

export const config = { schedule: '* * * * *' }
