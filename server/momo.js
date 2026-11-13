// MTN / Airtel Mobile Money for Uganda.
//   • With FLW_SECRET_KEY set: real collections through Flutterwave (charge type mobile_money_uganda).
//     Money lands in the Flutterwave merchant account and is settled to the company's account.
//   • Without it: TEST MODE. No money moves, and payments are auto-approved after a few seconds
//     so the whole flow (verification, receipt notification, phone push) can be tried end to end.
import { randomUUID } from 'node:crypto'
import { retryFetch } from '../src/lib/retryFetch.js'

const FLW = 'https://api.flutterwave.com/v3'
const http = retryFetch({ retries: 2, timeoutMs: 30000 })

const TEST_APPROVE_AFTER_MS = 8_000
export const ATTEMPT_TIMEOUT_MS = 15 * 60 * 1000 // give up waiting for approval after 15 min

export const NETWORK_LABEL = { MTN: 'MTN Mobile Money', AIRTEL: 'Airtel Money' }

export function providerName(env = process.env) {
  return env.FLW_SECRET_KEY ? 'flutterwave' : 'test'
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

// Known prefixes, used to catch "picked MTN but typed an Airtel number"
const MTN = ['76', '77', '78']
const AIRTEL = ['70', '74', '75']
export function networkOf(msisdn) {
  const p = msisdn.slice(3, 5)
  if (MTN.includes(p)) return 'MTN'
  if (AIRTEL.includes(p)) return 'AIRTEL'
  return null
}

export const newTxRef = () => `renta-${randomUUID()}`

// Start a collection. Returns { providerRef, redirectUrl }.
export async function initiate({ txRef, amount, msisdn, network, email, fullname }, env = process.env) {
  if (providerName(env) === 'test') return { providerRef: `test-${txRef}`, redirectUrl: null }

  const res = await http(`${FLW}/charges?type=mobile_money_uganda`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${env.FLW_SECRET_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      tx_ref: txRef,
      amount,
      currency: 'UGX',
      network,
      phone_number: msisdn,
      email,
      fullname,
    }),
  })
  const body = await res.json().catch(() => ({}))
  if (!res.ok || body.status !== 'success') {
    throw new Error(body.message || `Mobile money provider error (${res.status})`)
  }
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

  const res = await http(`${FLW}/transactions/verify_by_reference?tx_ref=${encodeURIComponent(attempt.tx_ref)}`, {
    headers: { Authorization: `Bearer ${env.FLW_SECRET_KEY}` },
  })
  const body = await res.json().catch(() => ({}))
  if (!res.ok || body.status !== 'success' || !body.data) return { status: 'pending' } // not visible yet
  const s = String(body.data.status ?? '').toLowerCase()
  return {
    status: s === 'successful' ? 'successful' : s === 'failed' || s === 'cancelled' ? 'failed' : 'pending',
    amount: Number(body.data.amount),
    currency: body.data.currency,
    providerRef: body.data.id ? String(body.data.id) : attempt.provider_ref,
    reason: body.data.processor_response,
  }
}
