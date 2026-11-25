// Tenants read the tenant policies, landlords the landlord policies: never mixed
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { LEGAL_PAGES, legalFor } from '../src/lib/legal.js'

const text = (page, who) => {
  const d = legalFor(page, who)
  return [d.title, d.intro, ...d.sections.flatMap((s) => [s.h, ...s.p])].join('\n')
}

test('every page has a text for both, with no empty parts', () => {
  for (const page of LEGAL_PAGES)
    for (const who of ['tenant', 'landlord']) {
      const d = legalFor(page, who)
      assert.ok(d.sections.length >= 3)
      for (const s of d.sections) assert.ok(s.h && s.p.length && s.p.every((p) => typeof p === 'string' && p.trim().length > 20), `${page} ${who} ${s.h}`)
      assert.doesNotMatch(text(page, who), /undefined|NaN|\bfalse\b(?!,)|\[object/)
    }
})

test('nothing that is only for landlords is in the tenant texts', () => {
  for (const page of LEGAL_PAGES) assert.doesNotMatch(text(page, 'tenant'), /subscription|NO REFUNDS|your tenants?\b|duties as a landlord|your properties|for landlords/i, page)
})

test('nothing that is only for tenants is in the landlord texts', () => {
  for (const page of LEGAL_PAGES) assert.doesNotMatch(text(page, 'landlord'), /your landlord|duties as a tenant|for tenants|your rent\b/i, page)
})

test('no refunds of landlord subscriptions; not responsible for mobile money, no digital cash', () => {
  assert.match(text('terms', 'landlord'), /NO REFUNDS: subscription payments are not refunded/)
  for (const who of ['tenant', 'landlord']) {
    assert.match(text('terms', who), /NOT responsible for any mobile money payment/)
    assert.match(text('terms', who), /No digital cash is involved/)
  }
})

test('section numbers and the sections they point to are right', () => {
  for (const who of ['tenant', 'landlord']) {
    const { sections } = legalFor('terms', who)
    sections.forEach((s, i) => assert.ok(s.h.startsWith(`${i + 1}. `)))
    const end = sections.find((s) => /Ending your use/.test(s.h)).p[0]
    assert.match(sections[Number(end.match(/in section (\d+)/)[1]) - 1].h, /Your account/)
    const names = end.match(/Sections ([\d, and]+) continue/)[1].match(/\d+/g).map((n) => sections[n - 1].h.replace(/^\d+\. /, ''))
    const want = ['Rent, payments and records', 'No warranties', 'Limit of our liability', 'Your promise to cover our losses (indemnity)', 'Events outside our control', 'Law and disputes']
    assert.deepEqual(names, who === 'landlord' ? ['Your subscription: no refunds', ...want] : want)
  }
})
