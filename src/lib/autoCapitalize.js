// Automatic capital letters, everywhere in the app.
//   • every text box / message: the first letter is a capital ("Water will be off…")
//   • names (people, landlords, rentals, rooms, places): every word starts with a capital
//     ("john mukasa" → "John Mukasa"). Marked with data-cap="words", or detected from the field.
//   • never touched: email, password, phone, numbers, dates, search boxes, codes, data-cap="off"
// Runs before Vue's v-model handler (capture phase), so the model gets the capitalised text.

const SKIP_TYPES = new Set(['email', 'password', 'tel', 'number', 'url', 'date', 'month', 'time', 'datetime-local', 'search', 'checkbox', 'radio', 'file', 'hidden', 'color', 'range'])
const NAME_HINT = /name|loc|prefix|room|rental|business|biz|house|area|place/i
const NEVER_HINT = /mail|pass|pw|code|phone|user|login|otp|ref/i

function mode(el) {
  if (el.dataset.cap === 'off') return null
  if (el.dataset.cap === 'words' || el.dataset.cap === 'sentence') return el.dataset.cap
  if (el.tagName === 'TEXTAREA') return 'sentence'
  if (el.tagName !== 'INPUT') return null
  if (el.readOnly || el.disabled) return null
  if (SKIP_TYPES.has((el.type || 'text').toLowerCase())) return null
  const ac = (el.autocomplete || '').toLowerCase()
  if (/email|username|tel|one-time-code|password/.test(ac)) return null
  if (/^search/i.test(el.placeholder || '')) return null
  if (/numeric|decimal|tel|email/.test(el.inputMode || '')) return null
  if (NEVER_HINT.test(el.id || '') || NEVER_HINT.test(el.name || '')) return null
  if (ac === 'name' || NAME_HINT.test(el.id || '') || NAME_HINT.test(el.name || '')) return 'words'
  return 'sentence'
}

const capWords = (s) => s.replace(/(^|[\s\-'(])([a-zà-ÿ])/g, (_, a, b) => a + b.toUpperCase())
const capFirst = (s) => s.replace(/^(\s*)([a-zà-ÿ])/, (_, a, b) => a + b.toUpperCase())

function onInput(e) {
  const el = e.target
  if (!el || (el.tagName !== 'INPUT' && el.tagName !== 'TEXTAREA') || e.isComposing) return
  const m = mode(el)
  if (!m) return
  const before = el.value
  const after = m === 'words' ? capWords(before) : capFirst(before)
  if (after === before) return
  const { selectionStart, selectionEnd } = el
  el.value = after // same length, so the cursor stays put
  try { el.setSelectionRange(selectionStart, selectionEnd) } catch { /* some inputs don't support it */ }
}

// Phone keyboards: open with the Shift key already on
function onFocus(e) {
  const el = e.target
  if (!el || (el.tagName !== 'INPUT' && el.tagName !== 'TEXTAREA') || el.hasAttribute('autocapitalize')) return
  const m = mode(el)
  if (m) el.setAttribute('autocapitalize', m === 'words' ? 'words' : 'sentences')
}

export function installAutoCapitalize() {
  document.addEventListener('input', onInput, true)
  document.addEventListener('focusin', onFocus, true)
}
