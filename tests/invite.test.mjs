import test from 'node:test'
import assert from 'node:assert/strict'
import { createInvite, openInvite, LINK_HOURS } from '../server/invite.js'
import { completeTenantAccount } from '../server/admin.js'
import { deleteInboxItem } from '../server/inbox.js'

const T = '11111111-2222-4333-8444-555555555555'
const L = 'landlord-1'
const PHONE_A = 'device-aaaaaaaaaaaaaaaa'
const PHONE_B = 'device-bbbbbbbbbbbbbbbb'

// A small stand-in for the database
function fakeDb(over = {}) {
  const tables = {
    tenants: [{ id: T, landlord_id: L, user_id: 'u1', property_id: 'p1', managed_by_landlord: true, ...over.tenant }],
    profiles: [{ id: 'u1', role: 'tenant', must_change_password: true, email: `tenant-${T}@phone-signin.example.com`, ...over.login }],
  }
  const meta = over.meta ?? {}
  return {
    tables, meta,
    from: (t) => ({
      select: () => ({
        eq: (c, v) => ({ maybeSingle: async () => ({ data: tables[t].find((r) => r[c] === v) ?? null, error: null }) }),
        ilike: () => ({ neq: () => ({ limit: async () => ({ data: [], error: null }) }) }),
      }),
      update: (change) => ({ eq: async (c, v) => {
        tables[t].filter((r) => r[c] === v).forEach((r) => Object.assign(r, change))
        return { error: null }
      } }),
    }),
    auth: { admin: {
      getUserById: async () => ({ data: { user: { app_metadata: structuredClone(meta) } }, error: null }),
      updateUserById: async (_id, v) => { Object.assign(meta, structuredClone(v.app_metadata)); return { error: null } },
    } },
  }
}
const open = (db, token, device = PHONE_A) => openInvite(db, { token, device }).then((r) => r.status)

test('one time: the first phone that opens it, and only that phone', async () => {
  const db = fakeDb()
  const { token } = await createInvite(db, L, T)
  assert.equal(await open(db, token, PHONE_A), 'ok')
  assert.equal(await open(db, token, PHONE_A), 'ok') // e.g. reloading the page
  assert.equal(await open(db, token, PHONE_B), 'used')
})

test('it carries nothing about the tenant, and opening it reveals nothing', async () => {
  const db = fakeDb()
  const { token } = await createInvite(db, L, T)
  assert.match(token, /^[\w-]{40}$/)
  assert.deepEqual(Object.keys(await openInvite(db, { token, device: PHONE_A })), ['status'])
  assert.ok(!JSON.stringify(db.meta).includes(token)) // only a hash is stored
})

test('every send gets its own link', async () => {
  const db = fakeDb()
  const a = await createInvite(db, L, T)
  const b = await createInvite(db, L, T)
  assert.notEqual(a.token, b.token)
  assert.equal(await open(db, a.token, PHONE_A), 'ok')
  assert.equal(await open(db, b.token, PHONE_B), 'ok')
  for (let i = 0; i < 30; i++) await createInvite(db, L, T)
  assert.ok(db.meta.links.length <= 10)
})

test('it stops after 48 hours', async () => {
  const db = fakeDb()
  const { token, expiresAt } = await createInvite(db, L, T)
  assert.ok(Math.abs(expiresAt - Date.now() - LINK_HOURS * 3_600_000) < 5000)
  db.meta.links[0].e = Date.now() - 1
  assert.equal(await open(db, token), 'expired')
})

test('it stops once the account is set up, and no new one can be made', async () => {
  const db = fakeDb()
  const { token } = await createInvite(db, L, T)
  db.tables.profiles[0].must_change_password = false
  assert.equal(await open(db, token), 'used')
  await assert.rejects(createInvite(db, L, T), /already set up/)
})

test('it stops when the tenancy ends', async () => {
  const db = fakeDb()
  const { token } = await createInvite(db, L, T)
  db.tables.tenants[0].property_id = null
  assert.equal(await open(db, token), 'invalid')
})

test("another landlord can't make a link; no access → no link", async () => {
  await assert.rejects(createInvite(fakeDb(), 'landlord-2', T), /not found/i)
  await assert.rejects(createInvite(fakeDb(), L, 'x'), /not found/i)
  await assert.rejects(createInvite(fakeDb({ tenant: { user_id: null } }), L, T), /app access/)
})

test('a changed, guessed or damaged link is refused', async () => {
  const db = fakeDb()
  const { token } = await createInvite(db, L, T)
  const bytes = Buffer.from(token, 'base64url')
  for (let i = 16; i < bytes.length; i += 3) {
    const bad = Buffer.from(bytes)
    bad[i] ^= 1
    assert.equal(await open(db, bad.toString('base64url')), 'invalid')
  }
  for (const bad of ['', undefined, 'hello', token.slice(0, -2), `${token}=`, 'A'.repeat(500)]) assert.equal(await open(db, bad), 'invalid')
  assert.equal(await open(db, token, 'x'), 'invalid') // no device
  assert.equal(await open(db, token), 'ok') // and none of that used it up
})

const register = (db) => completeTenantAccount(db, { id: 'u1' }, db.tables.profiles[0], { email: 'Sarah@Gmail.com', password: 'secret123' })

test('registering records the tenant as using the app', async () => {
  const db = fakeDb()
  const { token } = await createInvite(db, L, T)
  assert.equal(db.tables.tenants[0].managed_by_landlord, true) // a link alone changes nothing
  await register(db)
  assert.equal(db.tables.tenants[0].managed_by_landlord, false)
  assert.equal(db.tables.tenants[0].email, 'sarah@gmail.com')
  assert.equal(db.tables.profiles[0].must_change_password, false)
  assert.equal(await open(db, token), 'used')
})

test('a refused email does not stop the tenant being recorded', async () => {
  const db = fakeDb()
  const log = console.error
  console.error = () => {}
  const from = db.from
  db.from = (t) => (t === 'tenants' ? { ...from(t), update: (c) => ('email' in c ? { eq: async () => ({ error: { message: 'refused' } }) } : from(t).update(c)) } : from(t))
  await register(db)
  console.error = log
  assert.equal(db.tables.tenants[0].managed_by_landlord, false)
})

test('bad details record nothing', async () => {
  const db = fakeDb()
  await assert.rejects(completeTenantAccount(db, { id: 'u1' }, db.tables.profiles[0], { email: 'x', password: 'secret123' }))
  await assert.rejects(completeTenantAccount(db, { id: 'u1' }, db.tables.profiles[0], { email: 'a@b.co', password: 'short' }))
  assert.equal(db.tables.tenants[0].managed_by_landlord, true)
})

test('asking for a link puts an out-of-step record right', async () => {
  const set = fakeDb({ login: { must_change_password: false, email: 'sarah@gmail.com' } })
  await assert.rejects(createInvite(set, L, T), /already set up/)
  assert.equal(set.tables.tenants[0].managed_by_landlord, false)

  const old = fakeDb({ tenant: { managed_by_landlord: false } })
  await createInvite(old, L, T)
  assert.equal(old.tables.tenants[0].managed_by_landlord, true)

  // another landlord's request changes nothing
  const other = fakeDb({ login: { must_change_password: false } })
  await assert.rejects(createInvite(other, 'landlord-2', T), /not found/i)
  assert.equal(other.tables.tenants[0].managed_by_landlord, true)
})

test('inbox: only your own message can be deleted', async () => {
  const id = '99999999-2222-4333-8444-555555555555'
  let rows = [{ id, user_id: 'me' }]
  const db = { from: () => ({ delete: () => { const f = {}; const q = { eq: (c, v) => ((f[c] = v), q), select: async () => { const hit = rows.filter((r) => r.id === f.id && r.user_id === f.user_id); rows = rows.filter((r) => !hit.includes(r)); return { data: hit, error: null } } }; return q } }) }
  await assert.rejects(deleteInboxItem(db, { id: 'someone-else' }, { id }), /not found/i)
  assert.equal(rows.length, 1)
  await assert.rejects(deleteInboxItem(db, { id: 'me' }, { id: 'x' }), /not found/i)
  assert.deepEqual(await deleteInboxItem(db, { id: 'me' }, { id }), { ok: true })
  assert.equal(rows.length, 0)
})
