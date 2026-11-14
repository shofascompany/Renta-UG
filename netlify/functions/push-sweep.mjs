// Netlify Scheduled Function: every minute, send new notifications and inbox messages to people's
// phones (Web Push). On your own computer, `npm run server` does the same every 10 seconds.
// Needs VITE_VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT and SUPABASE_SERVICE_ROLE_KEY.
import { createClient } from '@supabase/supabase-js'
import { sendPendingPush } from '../../server/push.js'

export default async () => {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY
  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL
  if (!key || !url) return
  const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } })
  try {
    const n = await sendPendingPush(db)
    if (n) console.log(`[push-sweep] sent ${n} notification(s)`)
  } catch (e) {
    console.warn(`[push-sweep] ${e.message}`)
  }
}

export const config = { schedule: '* * * * *' }
