// Sign-in security tests (setup codes + wrong-password lockout) against an in-memory fake of Supabase.
// Run: npm test
import { test } from 'node:test'
import assert from 'node:assert/strict'
import * as mod from '../server/signIn.js'

test('first sign-in needs no code (landlords and tenants); wrong passwords are rate-limited', async () => {
const tables = { profiles: [], setup_codes: [], login_failures: [] }
const keyOf = { setup_codes: 'user_id', login_failures: 'key', profiles: 'id' }

function query(table) {
  const filters = []
  let op = 'select'
  let payload = null
  const rows = () => tables[table].filter((r) => filters.every((f) => f(r)))
  const q = {
    select() { return q },
    eq(c, v) { filters.push((r) => r[c] === v); return q },
    not(c, _is, v) { filters.push((r) => r[c] !== v && r[c] != null); return q },
    update(p) { op = 'update'; payload = p; return q },
    delete() { op = 'delete'; return q },
    upsert(p) {
      const k = keyOf[table]
      const i = tables[table].findIndex((r) => r[k] === p[k])
      if (i >= 0) tables[table][i] = { ...tables[table][i], ...p }
      else tables[table].push({ ...p })
      return Promise.resolve({ error: null })
    },
    maybeSingle() { const r = rows()[0]; return Promise.resolve({ data: r ? { ...r } : null, error: null }) }, // copies, like the real API
    then(res, rej) {
      if (op === 'update') rows().forEach((r) => Object.assign(r, payload))
      if (op === 'delete') tables[table] = tables[table].filter((r) => !filters.every((f) => f(r)))
      return Promise.resolve({ data: op === 'select' ? rows() : null, error: null }).then(res, rej)
    },
  }
  return q
}
const db = {
  from: query,
  auth: { admin: { generateLink: async () => ({ data: { properties: { hashed_token: 'TOKEN' } }, error: null }) } },
}
let goodPassword = 'right-pass1'
const signInClient = {
  auth: {
    signInWithPassword: async ({ password }) =>
      password === goodPassword
        ? { data: { session: { access_token: 'A', refresh_token: 'R' } }, error: null }
        : { data: null, error: { message: 'Invalid login credentials' } },
  },
}
const err = async (p) => { try { await p; return null } catch (e) { return e } }

// A landlord registered by the admin (no password yet), a tenant with a password,
// and a tenant just given app access by their landlord (no password yet)
tables.profiles.push(
  { id: 'L1', email: 'land@x.com', phone: '0772 123 456', role: 'landlord', active: true, must_change_password: true, created_at: '1' },
  { id: 'T1', email: 'ten@x.com', phone: '+256 701 000 111', role: 'tenant', active: true, must_change_password: false, created_at: '1' },
  { id: 'T2', email: 't2@phone-signin.example.com', phone: '0782 555 444', role: 'tenant', active: true, must_change_password: true, created_at: '1' },
)

// 1. Landlord's first sign-in: email or phone only, no code
assert.deepEqual(await mod.firstLoginByEmail(db, { email: 'land@x.com' }), { tokenHash: 'TOKEN' })
assert.deepEqual(await mod.phoneSignIn(db, signInClient, { phone: '0772123456' }), { tokenHash: 'TOKEN' })
// …but the email route is only for landlords who haven't set a password
assert.match((await err(mod.firstLoginByEmail(db, { email: 'ten@x.com' }))).message, /password/)

// 2. Tenant given app access: phone only too, no code
assert.deepEqual(await mod.phoneSignIn(db, signInClient, { phone: '0782555444' }), { tokenHash: 'TOKEN' })

// 3. An account that already has a password always needs it
assert.match((await err(mod.phoneSignIn(db, signInClient, { phone: '0701000111' }))).message, /password/)

// 5. Password lockout: 5 wrong passwords â†’ locked, even the right password is refused
for (let i = 0; i < 5; i++) await err(mod.phoneSignIn(db, signInClient, { phone: '0701000111', password: 'nope' }))
assert.match((await err(mod.phoneSignIn(db, signInClient, { phone: '0701000111', password: goodPassword }))).message, /Too many wrong passwords/)
// lock over â†’ right password works and clears the counter
tables.login_failures[0].locked_until = new Date(Date.now() - 1000).toISOString()
assert.deepEqual(await mod.phoneSignIn(db, signInClient, { phone: '0701000111', password: goodPassword }), { accessToken: 'A', refreshToken: 'R' })
assert.equal(tables.login_failures.length, 0)
})
