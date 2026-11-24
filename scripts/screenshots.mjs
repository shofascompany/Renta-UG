// Screenshots of the pages INSIDE the app, for the PDR (docs/Renta-UG-PDR.pdf).
// Signs in with DEMO accounts kept in the private .env file (never in the code or the PDF):
//   SHOT_LANDLORD_EMAIL, SHOT_LANDLORD_PASSWORD
//   SHOT_TENANT_EMAIL,   SHOT_TENANT_PASSWORD
//   SHOT_ADMIN_EMAIL,    SHOT_ADMIN_PASSWORD      (any of the three can be left out)
// Run: npm run build && npm run screenshots      → saves JPEGs in docs/screens/app-*.jpg
// Needs Microsoft Edge (Windows). Uses the built app served locally on port 4173.
import { spawn } from 'node:child_process'
import { writeFileSync, mkdirSync } from 'node:fs'
import { join } from 'node:path'
import { createClient } from '@supabase/supabase-js'

const OUT = join(process.cwd(), 'docs', 'screens')
const BASE = 'http://localhost:4173'
mkdirSync(OUT, { recursive: true })
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

const url = process.env.VITE_SUPABASE_URL
const anon = process.env.VITE_SUPABASE_ANON_KEY
if (!url || !anon) throw new Error('VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY missing in .env')
const storageKey = `sb-${new URL(url).hostname.split('.')[0]}-auth-token`

const accounts = [
  ['landlord', process.env.SHOT_LANDLORD_EMAIL, process.env.SHOT_LANDLORD_PASSWORD],
  ['tenant', process.env.SHOT_TENANT_EMAIL, process.env.SHOT_TENANT_PASSWORD],
  ['admin', process.env.SHOT_ADMIN_EMAIL, process.env.SHOT_ADMIN_PASSWORD],
].filter(([, e, p]) => e && p)
if (!accounts.length) {
  console.log('No demo accounts: add SHOT_LANDLORD_EMAIL / SHOT_LANDLORD_PASSWORD (and/or TENANT, ADMIN) to .env')
  process.exit(1)
}

// ── Serve the build ──
const preview = spawn(process.platform === 'win32' ? 'npx.cmd' : 'npx', ['vite', 'preview', '--port', '4173', '--strictPort'], { stdio: 'ignore', shell: true })
for (let i = 0; i < 40; i++) {
  try { if ((await fetch(BASE)).ok) break } catch {}
  await sleep(500)
}

// ── Headless Edge over the DevTools protocol ──
const edge = `${process.env['ProgramFiles(x86)']}\\Microsoft\\Edge\\Application\\msedge.exe`
const port = 9400 + Math.floor(Math.random() * 500)
const profile = join(process.env.TEMP || OUT, `renta-shots-${Date.now()}`)
const browser = spawn(edge, ['--headless=new', '--disable-gpu', '--hide-scrollbars', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`, 'about:blank'], { stdio: 'ignore' })
let target
for (let i = 0; i < 40 && !target; i++) {
  try { target = (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find((t) => t.type === 'page') } catch {}
  if (!target) await sleep(500)
}
const ws = new WebSocket(target.webSocketDebuggerUrl)
await new Promise((r) => ws.addEventListener('open', r))
let seq = 0
const pending = new Map()
ws.addEventListener('message', (e) => {
  const m = JSON.parse(e.data)
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id) }
})
const send = (method, params = {}) => new Promise((r) => { const i = ++seq; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })) })
const evalJs = async (expression) => (await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })).result?.result?.value
await send('Page.enable')
await send('Runtime.enable')
await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: 'light' }, { name: 'prefers-reduced-motion', value: 'reduce' }] })

const PHONE = { width: 390, height: 844, deviceScaleFactor: 3, mobile: true }
const DESK = { width: 1440, height: 900, deviceScaleFactor: 1.5, mobile: false }

async function shot(path, name, device, { tall = false } = {}) {
  await send('Emulation.setDeviceMetricsOverride', device)
  await send('Page.navigate', { url: BASE + path })
  await sleep(6500)
  await evalJs('document.fonts.ready.then(() => { window.scrollTo(0, 0); return true })')
  await sleep(700)
  const height = tall ? Math.min(await evalJs('document.documentElement.scrollHeight'), device.height * 2.2) : device.height
  const r = await send('Page.captureScreenshot', { format: 'jpeg', quality: 88, captureBeyondViewport: tall, clip: { x: 0, y: 0, width: device.width, height, scale: 1 } })
  writeFileSync(join(OUT, `app-${name}.jpg`), Buffer.from(r.result.data, 'base64'))
  console.log('saved', `app-${name}.jpg`, path)
}

for (const [role, email, password] of accounts) {
  const sb = createClient(url, anon, { auth: { persistSession: false } })
  const { data, error } = await sb.auth.signInWithPassword({ email, password })
  if (error) { console.log(`${role}: sign-in failed (${error.message})`); continue }
  // Put the session in the app's storage, the way a normal sign-in would
  await send('Page.navigate', { url: `${BASE}/login` })
  await sleep(2500)
  await evalJs(`localStorage.clear(); localStorage.setItem(${JSON.stringify(storageKey)}, ${JSON.stringify(JSON.stringify(data.session))}); true`)

  if (role === 'landlord') {
    const { data: t } = await sb.from('tenants').select('id, managed_by_landlord, user_id').not('property_id', 'is', null).limit(20)
    const tenant = t?.find((x) => !x.managed_by_landlord) ?? t?.[0]
    for (const [path, name, dev, opt] of [
      ['/landlord', 'landlord-overview', DESK], ['/landlord/tenants', 'landlord-tenants', DESK],
      tenant && [`/landlord/tenants/${tenant.id}`, 'landlord-tenant', PHONE],
      ['/landlord/payments', 'landlord-payments', DESK], ['/landlord/subscription', 'landlord-subscription', DESK],
    ].filter(Boolean)) await shot(path, name, dev, opt)
  }
  if (role === 'tenant') {
    for (const [path, name, dev, opt] of [
      ['/tenant', 'tenant-dashboard', PHONE], ['/tenant/payments', 'tenant-payments', PHONE], ['/tenant/pay', 'tenant-pay', PHONE],
    ]) await shot(path, name, dev, opt)
  }
  if (role === 'admin') {
    for (const [path, name, dev] of [
      ['/admin2026/overview', 'admin-overview', DESK], ['/admin2026/landlords', 'admin-landlords', DESK],
      ['/admin2026/subscriptions', 'admin-subscriptions', DESK],
    ]) await shot(path, name, dev)
  }
  await sb.auth.signOut({ scope: 'local' }).catch(() => {}) // only this session, not the account's other devices
}

ws.close()
browser.kill()
preview.kill()
process.exit(0)
