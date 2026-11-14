// Mobile money rent payments (MTN / Airtel), shared by the Express server (server/index.js) and the
// Netlify Function (netlify/functions/payments.mjs), so payments work locally AND on the live site.
// `db` is a Supabase client created with the SERVICE ROLE key: never use this in the browser.
// Every handler takes (db, user?, body) and returns plain JSON, or throws HttpError.
import { HttpError, requireUserProfile } from './admin.js'
import { isNetworkError, NETWORK_MESSAGE } from '../src/lib/retryFetch.js'
import * as momo from './momo.js'

const { providerName } = momo

function check(error) {
  if (!error) return
  if (isNetworkError(error)) throw new HttpError(503, NETWORK_MESSAGE)
  throw error
}

export async function requireUser(db, authorization) {
  return (await requireUserProfile(db, authorization)).user
}

const ugx = (n) => `UGX ${Number(n).toLocaleString('en-UG')}`
const monthOf = (period) => {
  const [y, m] = period.split('-').map(Number)
  return new Date(y, m - 1, 1).toLocaleDateString('en-GB', { month: 'long', year: 'numeric' })
}

// Loads a payment and checks it belongs to the signed-in tenant.
async function ownedPayment(db, paymentId, userId) {
  if (!paymentId) throw new HttpError(400, 'Missing payment.')
  const { data, error } = await db
    .from('payments')
    .select('id, amount, amount_paid, period, status, tenant_id, landlord_id, tenants!inner(user_id)')
    .eq('id', paymentId)
    .maybeSingle()
  check(error)
  if (!data || data.tenants.user_id !== userId) throw new HttpError(404, 'Payment not found.')
  return data
}

// ONE confirmation per payment (never one per month): to the tenant and their landlord. The main admin
// isn't messaged about landlords' payments; they see every payment under Transactions.
// Written after the rent is updated, so "paid up to" is the real new end of their rental time.
async function notifyPayment(db, { tenantId, landlordId, propertyId, received, method, phone, reference, months }) {
  if (!received) return
  const [{ data: tenant }, { data: house }, { data: rest }] = await Promise.all([
    db.from('tenants').select('full_name, lease_end').eq('id', tenantId).maybeSingle(),
    db.from('properties').select('name').eq('id', propertyId).maybeSingle(),
    db.from('payments').select('amount, amount_paid').eq('tenant_id', tenantId).eq('status', 'pending'),
  ])
  const balance = (rest ?? []).reduce((s, p) => s + Number(p.amount) - Number(p.amount_paid ?? 0), 0)
  const until = tenant?.lease_end
    ? new Date(`${tenant.lease_end}T00:00:00`).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })
    : null
  const covers = months?.length ? ` It covers ${months.map(monthOf).join(', ')}.` : ''

  await db.from('notifications').insert({
    landlord_id: landlordId,
    tenant_id: tenantId,
    type: 'payment',
    title: 'Payment confirmation',
    body:
      `Your ${method} payment of ${ugx(received)} was received and verified.${covers}` +
      (until ? ` You are paid up to ${until}.` : '') +
      (balance > 0 ? ` Still unpaid: ${ugx(balance)}.` : ''),
  })

  const body =
    `${tenant?.full_name ?? 'A tenant'} paid ${ugx(received)}${house?.name ? ` for ${house.name}` : ''} via ${method}` +
    `${phone ? ` (${String(phone).replace(/^256/, '0')})` : ''}.${covers} Verified automatically. Ref: ${reference}.`
  await db.from('staff_notifications').insert({ user_id: landlordId, type: 'payment', title: 'Payment received', body, url: '/landlord/inbox' })
}

// Online payment verified → pay off the rent charge (idempotent) and keep a receipt.
// notify = false when it's part of a bigger payment that sends one summary at the end.
async function markPaid(db, paymentId, reference, method, phone, notify = true) {
  const { data: before, error: bErr } = await db
    .from('payments')
    .select('id, amount, amount_paid, status, landlord_id, tenant_id, property_id, period')
    .eq('id', paymentId)
    .maybeSingle()
  check(bErr)
  if (!before || before.status === 'paid') return 0
  const received = Number(before.amount) - Number(before.amount_paid ?? 0)
  const paidAt = new Date().toISOString()

  const { data: rows, error } = await db
    .from('payments')
    .update({ status: 'paid', amount_paid: before.amount, paid_at: paidAt, method, reference })
    .eq('id', paymentId)
    .eq('status', 'pending') // only the first caller gets past here
    .select('id')
  check(error)
  if (!rows?.length) return 0

  await db.from('payment_receipts').insert({
    payment_id: before.id,
    tenant_id: before.tenant_id,
    landlord_id: before.landlord_id,
    amount: received,
    method,
    reference,
    received_at: paidAt,
  })

  if (notify) {
    await notifyPayment(db, {
      tenantId: before.tenant_id,
      landlordId: before.landlord_id,
      propertyId: before.property_id,
      received,
      method,
      phone,
      reference,
      months: [before.period],
    })
  }
  return received
}

// ── Recharge: unpaid rent + months ahead, in one payment ──
const kampalaMonth = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Africa/Kampala' }).slice(0, 7)
const addMonths = (period, n) => {
  const [y, m] = period.split('-').map(Number)
  const d = new Date(Date.UTC(y, m - 1 + n, 1))
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`
}

// The tenant's current stay, its monthly rent, their unpaid rent and the months a recharge would add.
async function rechargePlan(db, tenantFilter, months) {
  const { data: tenant, error } = await db
    .from('tenants')
    .select('id, user_id, landlord_id, property_id, properties!tenants_property_id_fkey(rent)')
    .match(tenantFilter)
    .maybeSingle()
  check(error)
  if (!tenant?.property_id) throw new HttpError(400, 'You are not connected to a house yet.')
  const rent = Number(tenant.properties?.rent ?? 0)
  if (!rent) throw new HttpError(400, 'Your house has no monthly rent set. Contact your landlord.')

  const { data: charges, error: cErr } = await db.from('payments').select('period, amount, amount_paid, status').eq('tenant_id', tenant.id)
  if (cErr && /amount_paid/.test(cErr.message)) {
    throw new HttpError(500, 'The database needs updating: run database/update_existing.sql in Supabase → SQL Editor.')
  }
  check(cErr)
  const outstanding = (charges ?? [])
    .filter((c) => c.status === 'pending')
    .reduce((s, c) => s + Number(c.amount) - Number(c.amount_paid ?? 0), 0)
  const latest = (charges ?? []).map((c) => c.period).sort().at(-1)
  const now = kampalaMonth()
  const start = latest && latest >= now ? addMonths(latest, 1) : now
  const periods = Array.from({ length: months }, (_, i) => addMonths(start, i))
  return { tenant, rent, outstanding, periods, total: outstanding + rent * months }
}

// Verified recharge → create the months ahead, then pay off every unpaid charge, oldest first.
async function applyRecharge(db, attempt) {
  const { tenant, rent, periods } = await rechargePlan(db, { id: attempt.tenant_id }, attempt.advance_months)
  const { error } = await db.from('payments').upsert(
    periods.map((period) => ({
      landlord_id: tenant.landlord_id,
      tenant_id: tenant.id,
      property_id: tenant.property_id,
      period,
      amount: rent,
      due_date: `${period}-05`,
    })),
    { onConflict: 'tenant_id,period', ignoreDuplicates: true },
  )
  check(error)

  const { data: open, error: oErr } = await db
    .from('payments')
    .select('id, amount, amount_paid, period')
    .eq('tenant_id', tenant.id)
    .eq('status', 'pending')
    .order('due_date')
    .order('period')
  check(oErr)

  const reference = attempt.provider_ref ?? attempt.tx_ref
  const method = momo.NETWORK_LABEL[attempt.network]
  const total = Number(attempt.amount)
  const covered = []
  let left = total
  for (const c of open ?? []) {
    if (left <= 0) break
    const remaining = Number(c.amount) - Number(c.amount_paid ?? 0)
    if (left >= remaining) {
      const got = await markPaid(db, c.id, reference, method, attempt.phone, false)
      left -= got
      if (got) covered.push(c.period)
      continue
    }
    // Not enough for this whole month (e.g. the rent went up): record what there is
    const { error: pErr } = await db.from('payments').update({ amount_paid: Number(c.amount_paid ?? 0) + left, method, reference }).eq('id', c.id)
    check(pErr)
    await db.from('payment_receipts').insert({
      payment_id: c.id,
      tenant_id: tenant.id,
      landlord_id: tenant.landlord_id,
      amount: left,
      method,
      reference,
      received_at: new Date().toISOString(),
    })
    left = 0
  }

  await notifyPayment(db, {
    tenantId: tenant.id,
    landlordId: tenant.landlord_id,
    propertyId: tenant.property_id,
    received: total - left,
    method,
    phone: attempt.phone,
    reference,
    months: covered,
  })
}

const attemptView = (a) => ({
  attemptId: a.id,
  status: a.status,
  network: a.network,
  phone: a.phone,
  redirectUrl: a.redirect_url,
  reason: a.failure_reason,
  testMode: a.provider === 'test',
})

// Checks one attempt with the provider and records the outcome. Safe to call repeatedly.
export async function checkAttempt(db, attempt) {
  if (attempt.status !== 'pending') return attempt

  let result
  try {
    result = await momo.verify(attempt)
  } catch (e) {
    console.warn(`[momo] verify ${attempt.tx_ref}: ${e.message}`)
    return attempt // try again on the next check
  }

  let update = null
  if (result.status === 'successful') {
    // Never trust a success that doesn't match what we asked for
    if (result.currency === 'UGX' && Number(result.amount) >= Number(attempt.amount)) {
      update = { status: 'successful', provider_ref: result.providerRef ?? attempt.provider_ref }
    } else {
      update = { status: 'failed', failure_reason: 'Amount or currency did not match. Contact support.' }
    }
  } else if (result.status === 'failed') {
    update = { status: 'failed', failure_reason: result.reason || 'The payment was declined or cancelled.' }
  } else if (Date.now() - new Date(attempt.created_at).getTime() > momo.ATTEMPT_TIMEOUT_MS) {
    update = { status: 'failed', failure_reason: 'The payment was not approved in time.' }
  }
  if (!update) return attempt

  // Only the first checker to flip it from pending gets to act on it
  const { data: rows, error } = await db
    .from('momo_attempts')
    .update({ ...update, updated_at: new Date().toISOString() })
    .eq('id', attempt.id)
    .eq('status', 'pending')
    .select()
  check(error)
  const updated = rows?.[0]
  if (!updated) {
    const { data: fresh } = await db.from('momo_attempts').select('*').eq('id', attempt.id).single()
    return fresh ?? attempt
  }
  if (updated.status === 'successful') {
    if (updated.advance_months) await applyRecharge(db, updated)
    else await markPaid(db, updated.payment_id, updated.provider_ref ?? updated.tx_ref, momo.NETWORK_LABEL[updated.network], updated.phone)
  }
  return updated
}

// Checks the number and works out MTN / Airtel from it (a picked network must match the number).
function payerFrom(body) {
  if (!providerName()) throw new HttpError(503, 'Online payments are not set up yet. Please pay your landlord in cash for now.')
  const msisdn = momo.normalizeUgPhone(body?.phone)
  if (!msisdn) throw new HttpError(400, 'Enter a valid Ugandan mobile number, e.g. 0772 123456.')
  const detected = momo.networkOf(msisdn)
  const picked = String(body?.network ?? '').toUpperCase()
  if (!detected && !['MTN', 'AIRTEL'].includes(picked)) throw new HttpError(400, 'Use an MTN or Airtel number.')
  if (detected && picked && picked !== detected) {
    throw new HttpError(400, `That is an ${detected === 'MTN' ? 'MTN' : 'Airtel'} number. Choose ${detected === 'MTN' ? 'MTN' : 'Airtel'} or use a different number.`)
  }
  return { msisdn, network: detected ?? picked }
}

// Account / key problems at the provider are for the owner to fix: log the real reason, show the
// tenant a plain message. Problems with their own payment (e.g. a wrong number) are shown as they are.
function providerError(e) {
  if (isNetworkError(e)) return new HttpError(503, NETWORK_MESSAGE)
  if (/disabled|not authenticated|authori[sz]ed ip|invalid access|not authorized|api key/i.test(e.message)) {
    console.error(`[momo] provider account problem: ${e.message}`)
    return new HttpError(503, 'Mobile money payments are not available right now. Please try again later, or pay your landlord in cash.')
  }
  return new HttpError(502, `Could not start the payment: ${e.message}`)
}

export const MIN_AMOUNT = 2_000 // Relworx's smallest mobile money payment in Uganda
export const MAX_AMOUNT = 5_000_000 // per mobile money transaction
function checkAmount(amount) {
  if (amount < MIN_AMOUNT) throw new HttpError(400, `The smallest payment is ${ugx(MIN_AMOUNT)}.`)
  if (amount > MAX_AMOUNT) throw new HttpError(400, `Mobile money allows up to ${ugx(MAX_AMOUNT)} in one payment. Choose fewer months.`)
}

// Sends the prompt for an attempt row that was just saved, and records the provider's reference.
async function startPrompt(db, attempt, user, description) {
  try {
    const { providerRef, redirectUrl } = await momo.initiate({
      txRef: attempt.tx_ref,
      amount: attempt.amount,
      msisdn: attempt.phone,
      network: attempt.network,
      email: user.email || process.env.PAYMENT_EMAIL_FALLBACK || 'payments@example.com',
      fullname: user.user_metadata?.full_name,
      description,
    })
    const { data: saved } = await db
      .from('momo_attempts')
      .update({ provider_ref: providerRef, redirect_url: redirectUrl, updated_at: new Date().toISOString() })
      .eq('id', attempt.id)
      .select()
      .single()
    return attemptView(saved ?? attempt)
  } catch (e) {
    await db.from('momo_attempts').update({ status: 'failed', failure_reason: e.message }).eq('id', attempt.id)
    throw providerError(e)
  }
}

// ── Handlers ──────────────────────────────────────────────────

// Is paying online switched on (and is it test mode)?
export function info() {
  const provider = providerName()
  return { enabled: Boolean(provider), testMode: provider === 'test', provider: provider ?? 'off', minAmount: MIN_AMOUNT, maxAmount: MAX_AMOUNT }
}

// Tenant pays one rent charge.
export async function pay(db, user, body) {
  const payment = await ownedPayment(db, body?.paymentId, user.id)
  if (payment.status === 'paid') throw new HttpError(400, 'This rent has already been paid.')
  const { msisdn, network } = payerFrom(body)

  // Don't send a second prompt while one is still waiting for approval
  const { data: open, error: oErr } = await db
    .from('momo_attempts')
    .select('*')
    .eq('payment_id', payment.id)
    .eq('status', 'pending')
    .order('created_at', { ascending: false })
    .limit(1)
  check(oErr)
  if (open?.[0]) {
    const current = await checkAttempt(db, open[0])
    if (current.status === 'pending') return { ...attemptView(current), resumed: true }
    if (current.status === 'successful') return attemptView(current)
  }

  // Only what's still owed (part of it may already have been paid in cash)
  const due = Number(payment.amount) - Number(payment.amount_paid ?? 0)
  checkAmount(due)
  const { data: attempt, error } = await db
    .from('momo_attempts')
    .insert({
      payment_id: payment.id,
      tenant_id: payment.tenant_id,
      landlord_id: payment.landlord_id,
      network,
      phone: msisdn,
      amount: due,
      tx_ref: momo.newTxRef(),
      provider: providerName(),
    })
    .select()
    .single()
  check(error)
  return startPrompt(db, attempt, user, `Rent ${monthOf(payment.period)}`)
}

// The app polls this while the tenant approves the prompt on their phone.
export async function status(db, user, body) {
  const { data: attempt, error } = await db.from('momo_attempts').select('*').eq('id', body?.attemptId).maybeSingle()
  check(error)
  if (!attempt) throw new HttpError(404, 'Payment not found.')
  const { data: owner, error: tErr } = await db.from('tenants').select('user_id').eq('id', attempt.tenant_id).maybeSingle()
  check(tErr)
  if (owner?.user_id !== user.id) throw new HttpError(404, 'Payment not found.')
  return attemptView(await checkAttempt(db, attempt))
}

const monthsFrom = (body) => {
  const months = Math.floor(Number(body?.months))
  if (!(months >= 1 && months <= 12)) throw new HttpError(400, 'Choose between 1 and 12 months.')
  return months
}

// Recharge page: what paying N months ahead would cost (unpaid rent is always included).
export async function rechargeQuote(db, user, body) {
  const { rent, outstanding, periods, total } = await rechargePlan(db, { user_id: user.id }, monthsFrom(body))
  return { rent, outstanding, periods, total }
}

// Recharge: one mobile money prompt for unpaid rent + 1–12 months ahead.
export async function recharge(db, user, body) {
  const months = monthsFrom(body)
  const { msisdn, network } = payerFrom(body)
  const { tenant, total } = await rechargePlan(db, { user_id: user.id }, months)
  checkAmount(total)

  const { data: open, error: oErr } = await db
    .from('momo_attempts')
    .select('*')
    .eq('tenant_id', tenant.id)
    .not('advance_months', 'is', null)
    .eq('status', 'pending')
    .order('created_at', { ascending: false })
    .limit(1)
  if (oErr && /advance_months/.test(oErr.message)) {
    throw new HttpError(500, 'Recharge needs a database update: run database/update_existing.sql in Supabase.')
  }
  check(oErr)
  if (open?.[0]) {
    const current = await checkAttempt(db, open[0])
    if (current.status === 'pending') return { ...attemptView(current), resumed: true }
  }

  const { data: attempt, error } = await db
    .from('momo_attempts')
    .insert({
      payment_id: null,
      tenant_id: tenant.id,
      landlord_id: tenant.landlord_id,
      network,
      phone: msisdn,
      amount: total,
      tx_ref: momo.newTxRef(),
      provider: providerName(),
      advance_months: months,
    })
    .select()
    .single()
  if (error && /payment_id|advance_months/.test(error.message)) {
    throw new HttpError(500, 'Recharge needs a database update: run database/update_existing.sql in Supabase.')
  }
  check(error)
  return startPrompt(db, attempt, user, `Rent recharge, ${months} month${months === 1 ? '' : 's'}`)
}

// Relworx calls this when a payment succeeds or fails. The body is only used to FIND the payment:
// the result is always re-checked with Relworx before any rent is marked paid.
export async function relworxWebhook(db, body) {
  const ref = body?.customer_reference ?? body?.reference
  const internal = body?.internal_reference
  let attempt = null
  if (ref) ({ data: attempt } = await db.from('momo_attempts').select('*').eq('tx_ref', ref).maybeSingle())
  if (!attempt && internal) ({ data: attempt } = await db.from('momo_attempts').select('*').eq('provider_ref', internal).maybeSingle())
  if (attempt) await checkAttempt(db, attempt)
  return { received: true }
}

// Flutterwave webhook: needs the secret hash header, and is re-verified with the API too.
export async function flutterwaveWebhook(db, body, verifHash) {
  const expected = process.env.FLW_WEBHOOK_HASH
  if (!expected || verifHash !== expected) throw new HttpError(401, 'Invalid webhook signature.')
  const txRef = body?.data?.tx_ref ?? body?.txRef
  if (txRef) {
    const { data: attempt } = await db.from('momo_attempts').select('*').eq('tx_ref', txRef).maybeSingle()
    if (attempt) await checkAttempt(db, attempt)
  }
  return { received: true }
}

// Background sweep: confirm waiting payments even if the tenant closed the app.
export async function checkPending(db, limit = 25) {
  const { data: pending } = await db.from('momo_attempts').select('*').eq('status', 'pending').order('created_at').limit(limit)
  for (const a of pending ?? []) await checkAttempt(db, a)
  return pending?.length ?? 0
}
