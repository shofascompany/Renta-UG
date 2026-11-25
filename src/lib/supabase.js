import { createClient } from '@supabase/supabase-js'
import { retryFetch, isNetworkError, NETWORK_MESSAGE } from './retryFetch'

const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_ANON_KEY

export const isConfigured = Boolean(url && key)

if (!isConfigured) {
  console.error('Supabase is not configured. Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY in .env and restart the dev server.')
}

export const supabase = createClient(url || 'http://localhost', key || 'missing-key', {
  global: { fetch: retryFetch() }, // retries + timeouts for unstable connections
})

// Unwrap a Supabase response, throwing on error (with a friendly message for network failures).
export function must({ data, error }) {
  if (error) {
    if (isNetworkError(error)) throw new Error(NETWORK_MESSAGE)
    // The database refused the change for this account (signed out on another tab, account changed, etc.)
    if (/row-level security|permission denied/i.test(error.message)) throw new Error(PERMISSION_MESSAGE)
    throw error
  }
  return data
}
// Every row of a list, not only the first 1,000 (the most the database sends at a time), so totals are always whole.
//   await fetchAll(() => supabase.from('payments').select('*').order('created_at').order('id'))
const PAGE = 1000
export async function fetchAll(query, most = Infinity) {
  const rows = new Map() // a row added while reading can't be counted twice
  for (let from = 0; from < most; from += PAGE) {
    const page = must(await query().range(from, from + PAGE - 1))
    for (const r of page) rows.set(r.id ?? rows.size, r)
    if (page.length < PAGE) break
  }
  return [...rows.values()]
}
export const PERMISSION_MESSAGE =
  "Your account isn't allowed to make this change right now. Sign out and sign in again, then try once more. If it keeps happening, contact Renta UG."
