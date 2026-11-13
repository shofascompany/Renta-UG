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
    throw error
  }
  return data
}
