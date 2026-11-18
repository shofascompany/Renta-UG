// Netlify Scheduled Function: every 20 minutes, check every part of Renta UG (database, sign-in,
// email, SMS, phone notifications, payments waiting, app errors) and keep the result for the main
// admin (Health & settings). Problems are reported so the main admin gets a notification.
// On your own computer, `npm run server` does the same.
import { createClient } from '@supabase/supabase-js'
import { runHealthCheck } from '../../server/health.js'

export default async () => {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY
  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL
  if (!key || !url) return
  const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } })
  try {
    const { ok, results } = await runHealthCheck(db)
    if (!ok) console.warn(`[health] ${results.filter((r) => r.status !== 'ok').map((r) => `${r.label}: ${r.detail}`).join(' | ')}`)
  } catch (e) {
    console.warn(`[health] ${e.message}`)
  }
}

export const config = { schedule: '*/20 * * * *' }
