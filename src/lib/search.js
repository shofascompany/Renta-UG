// The one search used by every search box. Pure (no Vue, no browser).
//   const hit = searcher('sarah room 3')
//   hit(t.name, t.phone, house)  → true when every word is found, in any order
// Capital letters and accents don't matter. A phone number is found however it is typed:
// 0772 123, 772123, +256 772 123 and 256772123 all find +256772123456 (and a saved 0772 123 456).
const fold = (v) => String(v ?? '').toLowerCase().normalize('NFD').replace(/\p{M}/gu, '').replace(/\s+/g, ' ').trim()

const PHONE = /^\+?[\d\s().-]+$/
const digitsOf = (v) => String(v).replace(/\D/g, '')
const phoneDigits = (v) => {
  const d = digitsOf(v)
  return d.startsWith('00') ? d.slice(2) : d.startsWith('0') ? `256${d.slice(1)}` : d
}

export function searcher(query) {
  const q = fold(query)
  if (!q) return () => true
  const words = q.split(' ').map((w) => (/^\d{1,2}$/.test(w) ? new RegExp(`(?<!\\d)${w}`) : w)) // "1" finds Room 1 and 10, not every number with a 1 in it
  const typed = PHONE.test(q) && digitsOf(q).length >= 3 ? digitsOf(q) : ''
  // A leading 0 is the start of a local number: 0772… is the 772… inside +256772…
  const tries = typed ? [typed.replace(/^00/, ''), typed.replace(/^0+/, '')].filter((d) => d.length >= 3) : []

  return (...fields) => {
    const list = fields.flat(Infinity).filter((f) => f !== null && f !== undefined && f !== '')
    const text = fold(list.join(' '))
    const names = fold(list.filter((f) => !PHONE.test(String(f).trim())).join(' ')) // a "2" is never looked for inside a phone number
    if (words.every((w) => (typeof w === 'string' ? text.includes(w) : w.test(names)))) return true
    if (!tries.length) return false
    return list.some((f) => PHONE.test(String(f).trim()) && digitsOf(f).length >= 7 && tries.some((d) => phoneDigits(f).includes(d)))
  }
}

// Sorting that always makes sense: numbers as numbers, "Room 2" before "Room 10", and empty values last
// whichever way the list is sorted. dir: 1 = smallest first, -1 = biggest first
export function compare(a, b, dir = 1) {
  const none = (v) => v === null || v === undefined || v === ''
  if (none(a) || none(b)) return Number(none(a)) - Number(none(b))
  return (typeof a === 'number' && typeof b === 'number' ? a - b : String(a).localeCompare(String(b), undefined, { numeric: true, sensitivity: 'base' })) * dir
}
