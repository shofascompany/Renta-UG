// The link a landlord sends on WhatsApp to a tenant they gave app access. Shared by Express and Netlify Functions.
//
//   https://rentaug.netlify.app/i/<random>
//
// A normal link that carries NOTHING about the tenant: no number, no name, no code, and it signs nobody in. It only
// opens the website and (on Android) makes the app required. The number is written in the message.
//   • One time: it belongs to the first device that opens it; any other device is refused.
//   • It stops after 48 hours, once the account is set up, or when the tenancy ends.
// Only a hash of each link is kept, on the tenant's own login (app_metadata, which only the server can write).
import { createHash, randomBytes } from 'node:crypto'
import { HttpError, isPlaceholderEmail } from './admin.js'

export const LINK_HOURS = 48
const KEEP = 10 // unexpired links remembered per tenant
const UUID = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i
const short = (v) => createHash('sha256').update(v).digest('base64url').slice(0, 24)

async function row(query) {
  const { data, error } = await query.maybeSingle()
  if (error) throw new HttpError(500, error.message)
  return data
}
const tenantRow = (db, id) => row(db.from('tenants').select('id, landlord_id, user_id, property_id, managed_by_landlord').eq('id', id))
const loginRow = (db, id) => row(db.from('profiles').select('role, must_change_password, email').eq('id', id))

async function links(db, userId) {
  const { data, error } = await db.auth.admin.getUserById(userId)
  if (error) throw new HttpError(500, error.message)
  const list = data?.user?.app_metadata?.links
  return Array.isArray(list) ? list : []
}
async function saveLinks(db, userId, list) {
  const { error } = await db.auth.admin.updateUserById(userId, { app_metadata: { links: list } })
  if (error) throw new HttpError(500, error.message)
}

// Keeps the tenant's record in step with their login (registered or not)
async function setManaged(db, t, managed) {
  if (t.managed_by_landlord === managed) return
  const { error } = await db.from('tenants').update({ managed_by_landlord: managed }).eq('id', t.id)
  if (error) console.error('[invite]', error.message)
}

// Landlord: a fresh link for one of their tenants
export async function createInvite(db, landlordId, tenantId) {
  if (!UUID.test(String(tenantId))) throw new HttpError(404, 'Tenant not found.')
  const t = await tenantRow(db, tenantId)
  if (!t || t.landlord_id !== landlordId) throw new HttpError(404, 'Tenant not found.')
  if (!t.property_id) throw new HttpError(400, 'This tenant is not renting a house right now.')
  if (!t.user_id) throw new HttpError(409, 'Give this tenant app access first.')
  const login = await loginRow(db, t.user_id)
  if (!login || login.role !== 'tenant') throw new HttpError(404, 'Tenant not found.')
  if (!login.must_change_password) {
    await setManaged(db, t, false)
    throw new HttpError(409, 'This tenant has already set up their account, so they no longer need a link.')
  }
  if (isPlaceholderEmail(login.email)) await setManaged(db, t, true) // access given by an older version: not registered yet

  const token = Buffer.concat([Buffer.from(t.id.replace(/-/g, ''), 'hex'), randomBytes(14)]).toString('base64url')
  const expiresAt = Date.now() + LINK_HOURS * 3_600_000
  const current = (await links(db, t.user_id)).filter((l) => l.e > Date.now()).slice(-(KEEP - 1))
  await saveLinks(db, t.user_id, [...current, { h: short(token), e: expiresAt }])
  return { token, expiresAt }
}

// Someone opens a link: { token, device } → { status: ok | expired | used | invalid }. Nothing else is revealed.
export async function openInvite(db, body) {
  const token = String(body?.token ?? '')
  const device = String(body?.device ?? '')
  const raw = Buffer.from(token, 'base64url')
  if (raw.length !== 30 || raw.toString('base64url') !== token || !/^[\w-]{16,64}$/.test(device)) return { status: 'invalid' }
  const hex = raw.subarray(0, 16).toString('hex')
  const t = await tenantRow(db, `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`)
  if (!t?.property_id || !t.user_id) return { status: 'invalid' }

  const list = await links(db, t.user_id)
  const link = list.find((l) => l.h === short(token))
  const login = await loginRow(db, t.user_id)
  if (!login || login.role !== 'tenant') return { status: 'invalid' }
  if (!login.must_change_password) return { status: 'used' }
  if (!link) return { status: 'invalid' }
  if (link.e <= Date.now()) return { status: 'expired' }
  const mine = short(`device:${device}`)
  if (link.d) return { status: link.d === mine ? 'ok' : 'used' }
  await saveLinks(db, t.user_id, list.map((l) => (l === link ? { ...l, d: mine } : l)))
  return { status: 'ok' }
}
