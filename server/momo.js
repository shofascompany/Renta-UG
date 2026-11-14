// MTN MoMo / Airtel Money collections for Uganda. The provider is picked from the keys in .env:
//   • RELWORX_API_KEY + RELWORX_ACCOUNT_NO → Relworx (Kampala). One API for MTN and Airtel,
//     payment prompt straight to the tenant's phone, status checked automatically. (preferred)
//   • FLW_SECRET_KEY                        → Flutterwave (mobile_money_uganda).
//   • PAYMENTS_TEST_MODE=true               → TEST MODE: no money moves, payments approve
//     themselves after a few seconds. Only when you switch it on yourself.
//   • none of the above                     → online payments are OFF and the app says so.
// Whatever the provider, a payment only counts after we ask the provider ourselves and the
// amount + currency match. Webhook bodies are never trusted on their own.
import { randomUUID } from 'node:crypto'
import { retryFetch } from '../src/lib/retryFetch.js'

const FLW = 'https://api.flutterwave.com/v3'
const RELWORX = 'https://payments.relworx.com/api'
const http = retryFetch({ retries: 2, timeoutMs: 30000 })

const TEST_APPROVE_AFTER_MS = 8_000
export const ATTEMPT_TIMEOUT_MS = 15 * 60 * 1000 // give up waiting for approval after 15 min

export const NETWORK_LABEL = { MTN: 'MTN Mobile Money', AIRTEL: 'Airtel Money' }

export function providerName(env = process.env) {
  if (env.RELWORX_API_KEY && env.RELWORX_ACCOUNT_NO) return 'relworx'
  if (env.FLW_SECRET_KEY) return 'flutterwave'
  if (String(env.PAYMENTS_TEST_MODE).toLowerCase() === 'true') return 'test'
  return null // not set up
}

// Accepts 0772123456, 772123456, +256 772 123 456, 256772123456 → "256772123456" (or null)
export function normalizeUgPhone(input) {
  const d = String(input ?? '').replace(/\D/g, '')
  let local = null
  if (d.length === 12 && d.startsWith('256')) local = d.slice(3)
  else if (d.length === 10 && d.startsWith('0')) local = d.slice(1)
  else if (d.length === 9) local = d
  return local && local.startsWith('7') ? `256${local}` : null
}

// Known prefixes: the network is worked out from the number itself
const MTN = ['76', '77', '78', '79']
const AIRTEL = ['70', '74', '75']
export function networkOf(msisdn) {
  const p = msisdn.slice(3, 5)
  if (MTN.includes(p)) return 'MTN'
  if (AIRTEL.includes(p)) return 'AIRTEL'
  return null
}

// 34 characters: fits every provider's reference limit (Relworx: 8–36)
export const newTxRef = () => `rt${randomUUID().replace(/-/g, '')}`

const relworxHeaders = (env) => ({
  Authorization: `Bearer ${env.RELWORX_API_KEY}`,
  Accept: 'application/vnd.relworx.v2',
  'Content-Type': 'application/json',
})

// Start a collection. Returns { providerRef, redirectUrl }.
export async function initiate({ txRef, amount, msisdn, network, email, fullname, description }, env = process.env) {
  const provider = providerName(env)
  if (!provider) throw new Error('Online payments are not set up yet. Please pay your landlord in cash for now.')
  if (provider === 'test') return { providerRef: `test-${txRef}`, redirectUrl: null }

  if (provider === 'relworx') {
    const res = await http(`${RELWORX}/mobile-money/request-payment`, {
      method: 'POST',
      headers: relworxHeaders(env),
      body: JSON.stringify({
        account_no: env.RELWORX_ACCOUNT_NO,
        reference: txRef,
        msisdn: `+${msisdn}`,
        currency: 'UGX',
        amount: Number(amount),
        description: description || 'Rent payment',
      }),
    })
    const body = await res.json().catch(() => ({}))
    if (!res.ok || body.success === false) throw new Error(body.message || `Mobile money provider error (${res.status})`)
    return { providerRef: body.internal_reference ?? null, redirectUrl: null }
  }

  const res = await http(`${FLW}/charges?type=mobile_money_uganda`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${env.FLW_SECRET_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ tx_ref: txRef, amount, currency: 'UGX', network, phone_number: msisdn, email, fullname }),
  })
  const body = await res.json().catch(() => ({}))
  if (!res.ok || body.status !== 'success') throw new Error(body.message || `Mobile money provider error (${res.status})`)
  return {
    providerRef: body.data?.id ? String(body.data.id) : null,
    redirectUrl: body.meta?.authorization?.redirect ?? null,
  }
}

// Ask the provider what happened. Returns { status: 'pending'|'successful'|'failed', amount, currency, providerRef, reason }.
export async function verify(attempt, env = process.env) {
  if (attempt.provider === 'test') {
    const age = Date.now() - new Date(attempt.created_at).getTime()
    return age >= TEST_APPROVE_AFTER_MS
      ? { status: 'successful', amount: Number(attempt.amount), currency: 'UGX', providerRef: attempt.provider_ref }
      : { status: 'pending' }
  }

  if (attempt.provider === 'relworx') {
    if (!env.RELWORX_API_KEY) return { status: 'pending' }
    const ref = attempt.provider_ref || attempt.tx_ref
    const url = `${RELWORX}/mobile-money/check-request-status?internal_reference=${encodeURIComponent(ref)}&account_no=${encodeURIComponent(env.RELWORX_ACCOUNT_NO)}`
    const res = await http(url, { headers: relworxHeaders(env) })
    const body = await res.json().catch(() => ({}))
    if (!res.ok || !body) return { status: 'pending' }
    const s = String(body.request_status ?? body.status ?? '').toLowerCase()
    return {
      status: s === 'success' || s === 'successful' ? 'successful' : s === 'failed' || s === 'cancelled' ? 'failed' : 'pending',
      amount: Number(body.amount),
      currency: body.currency,
      providerRef: body.provider_transaction_id || body.internal_reference || attempt.provider_ref,
      reason: s === 'failed' ? body.message : undefined,
    }
  }

  if (!env.FLW_SECRET_KEY) return { status: 'pending' }
  const res = await http(`${FLW}/transactions/verify_by_reference?tx_ref=${encodeURIComponent(attempt.tx_ref)}`, {
    headers: { Authorization: `Bearer ${env.FLW_SECRET_KEY}` },
  })
  const body = await res.json().catch(() => ({}))
  if (!res.ok || body.status !== 'success' || !body.data) return { status: 'pending' }
  const s = String(body.data.status ?? '').toLowerCase()
  return {
    status: s === 'successful' ? 'successful' : s === 'failed' || s === 'cancelled' ? 'failed' : 'pending',
    amount: Number(body.data.amount),
    currency: body.data.currency,
    providerRef: body.data.id ? String(body.data.id) : attempt.provider_ref,
    reason: body.data.processor_response,
  }
}
