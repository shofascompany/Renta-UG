import test from 'node:test'
import assert from 'node:assert/strict'
import { existsSync, readFileSync } from 'node:fs'
import { PAGES, withPreview } from '../scripts/linkPreviews.js'
import { millionsUGX } from '../src/utils/format.js'
import { COUNTRIES } from '../src/lib/phone.js'

const at = (p) => new URL(`../${p}`, import.meta.url)

test('total revenue: exact to the thousand, never rounded', () => {
  assert.equal(millionsUGX(1_200_000), '1.2M')
  assert.equal(millionsUGX(12_340_000), '12.34M')
  assert.equal(millionsUGX(21_897_000), '21.897M')
  assert.equal(millionsUGX(21_897_999), '21.897M') // the hundreds are left out, not rounded up
  assert.equal(millionsUGX(1_999_999), '1.999M')
  assert.equal(millionsUGX(3_000_000), '3M')
  assert.equal(millionsUGX(3_005_000), '3.005M')
  assert.equal(millionsUGX(1_234_567_890), '1,234.567M')
  assert.equal(millionsUGX(850_000), '850,000')
  assert.equal(millionsUGX(0), '0')
})

test('country names keep their accents', () => {
  const names = COUNTRIES.map((c) => c.name)
  for (const n of ['Åland Islands', "Côte d'Ivoire", 'Curaçao', 'Réunion', 'Saint Barthélemy', 'São Tomé and Príncipe']) assert.ok(names.includes(n), n)
  assert.ok(!names.some((n) => /[ÂÃâ][\u0080-¿€‚ƒ„…†‡]/.test(n)))
})

test('no source file starts with an invisible byte-order mark', () => {
  for (const f of ['src/lib/phone.js', 'src/layouts/AppShell.vue', 'src/lib/installApp.js', 'scripts/bundle-sql.js']) {
    assert.notEqual(readFileSync(at(f))[0], 0xef, f)
  }
})

test('every shared link has its own title and picture, exactly once', () => {
  const html = readFileSync(at('index.html'), 'utf8')
  for (const [path, page] of Object.entries(PAGES)) {
    const out = withPreview(html, path, page)
    for (const re of [/<title>/g, /og:title"/g, /og:image"/g, /name="description"/g, /twitter:card/g]) assert.equal(out.match(re).length, 1, `${path} ${re}`)
    // The title is the app's name and nothing else
    assert.ok(out.includes('<title>Renta UG</title>') && out.includes('og:title" content="Renta UG"') && out.includes('twitter:title" content="Renta UG"'), path)
    assert.ok(out.includes(page.image))
    assert.ok(existsSync(at(`public/${page.image}`)), page.image)
    assert.ok(out.includes('<div id="app">'))
  }
  const toml = readFileSync(at('netlify.toml'), 'utf8')
  for (const path of Object.keys(PAGES).filter(Boolean)) assert.ok(toml.includes(`to = "/${path}.html"`), path)
})
