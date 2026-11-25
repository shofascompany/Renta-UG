import test from 'node:test'
import assert from 'node:assert/strict'
import { toE164, isValidPhone, phoneKey, samePhone, splitPhone, composePhone, prettyPhone, whatsappDigits, COUNTRIES } from '../src/lib/phone.js'

test('numbers from any country are saved with their country code', () => {
  assert.equal(toE164('0772 123 456'), '+256772123456') // an older Ugandan number
  assert.equal(toE164('+254 712-345-678'), '+254712345678') // Kenya
  assert.equal(toE164('00447911123456'), '+447911123456') // United Kingdom, written with 00
  assert.equal(toE164('+1 (415) 555-2671'), '+14155552671') // United States
  assert.equal(toE164('12345'), '')
  assert.equal(isValidPhone('+12'), false)
  assert.equal(isValidPhone('+81 90 1234 5678'), true) // Japan
})

test('the same person is matched on the full number, not the last 9 digits', () => {
  assert.equal(phoneKey('0772123456'), '256772123456')
  assert.ok(samePhone('+256 772 123 456', '0772123456'))
  assert.ok(!samePhone('+256712345678', '+254712345678')) // Uganda vs Kenya: same last 9 digits, different people
  assert.equal(whatsappDigits('+254712345678'), '254712345678')
})

test('a number splits back into country and local part', () => {
  assert.deepEqual(splitPhone('+254712345678'), { iso: 'KE', dial: '254', local: '712345678' })
  assert.equal(splitPhone('+14155552671').iso, 'US')
  assert.equal(splitPhone('+18765551234').iso, 'JM')
  assert.equal(splitPhone('+447911123456').iso, 'GB')
  assert.equal(composePhone('254', '0712 345 678'), '+254712345678')
  assert.equal(prettyPhone('+256772123456'), '+256 772 123 456')
})

test('the country list is complete and has no repeated codes', () => {
  assert.ok(COUNTRIES.length >= 230)
  assert.equal(new Set(COUNTRIES.map((c) => c.iso)).size, COUNTRIES.length)
  assert.ok(COUNTRIES.every((c) => /^\d{1,4}$/.test(c.dial) && c.name))
})
