import { supabase } from './supabase'
import { NETWORK_MESSAGE } from './retryFetch'

// Calls to our Express server, authenticated with the user's Supabase session.
export async function api(path, body, method = 'POST') {
  const {
    data: { session },
  } = await supabase.auth.getSession()

  let res
  try {
    res = await fetch(path, {
      method,
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${session?.access_token ?? ''}` },
      body: JSON.stringify(body ?? {}),
    })
  } catch {
    throw new Error('Cannot reach the Renta server. Make sure `npm run server` is running.')
  }
  const data = await res.json().catch(() => ({}))
  if (res.status === 503) throw new Error(data.error || NETWORK_MESSAGE)
  if (!res.ok) throw new Error(data.error || 'Cannot reach the Renta server. Make sure `npm run server` is running.')
  return data
}
