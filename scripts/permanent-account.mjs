// Creates or repairs the permanent landlord account (ngumisiriza@gmail.com) with its fixed password.
// The password lives only in your private .env (PERMANENT_ACCOUNT_PASSWORD), never in the code.
// Needs database/50_permanent_account.sql to have been run in Supabase first.
// Usage: npm run permanent-account
import { createClient } from '@supabase/supabase-js'

const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY
const anonKey = process.env.VITE_SUPABASE_ANON_KEY
const password = process.env.PERMANENT_ACCOUNT_PASSWORD
const email = 'ngumisiriza@gmail.com'

if (!url || !serviceKey) throw new Error('Supabase URL and SUPABASE_SERVICE_ROLE_KEY must be in .env')
if (!password) throw new Error('Add PERMANENT_ACCOUNT_PASSWORD to .env first')

const db = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
const { data: id, error } = await db.rpc('set_permanent_account', { p_password: password })
if (error) {
  throw new Error(/set_permanent_account/.test(error.message) ? 'Run database/update_existing.sql in Supabase first (it has 50_permanent_account.sql).' : error.message)
}
console.log('permanent account ready:', email)

const { data: p } = await db.from('profiles').select('role, active, must_change_password, subscription_exempt').eq('id', id).maybeSingle()
console.log(`  landlord: ${p?.role === 'landlord'} | active: ${p?.active} | free for life: ${p?.subscription_exempt} | first sign-in pages: ${p?.must_change_password ? 'YES (wrong)' : 'never'}`)

if (anonKey) {
  const client = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } })
  const { error: sErr } = await client.auth.signInWithPassword({ email, password })
  console.log(`  sign-in test: ${sErr ? `FAILED (${sErr.message})` : 'OK'}`)
  if (!sErr) await client.auth.signOut()
}
