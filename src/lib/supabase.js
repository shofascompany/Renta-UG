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
export const PERMISSION_MESSAGE =
  "Your account isn't allowed to make this change right now. Sign out and sign in again, then try once more. If it keeps happening, contact Renta UG."
