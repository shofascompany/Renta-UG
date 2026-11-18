// Catches email addresses that can never receive the code, BEFORE we send it:
//   • common typos of big providers (gmial.com, gmail.con, yaho.com, hotmial.com …) → "Did you mean …?"
//   • domains that don't exist or can't receive mail (no MX / A record)
import { promises as dns } from 'node:dns'
import { HttpError } from './admin.js'

const PROVIDERS = ['gmail.com', 'yahoo.com', 'outlook.com', 'hotmail.com', 'icloud.com', 'live.com', 'ymail.com', 'protonmail.com', 'aol.com', 'mail.com']
const KNOWN_TYPOS = {
  'gmail.co': 'gmail.com', 'gmail.con': 'gmail.com', 'gmail.cm': 'gmail.com', 'gmail.om': 'gmail.com', 'gmail.comm': 'gmail.com',
  'gmai.com': 'gmail.com', 'gmial.com': 'gmail.com', 'gamil.com': 'gmail.com', 'gmaill.com': 'gmail.com', 'gnail.com': 'gmail.com',
  'gmal.com': 'gmail.com', 'gmali.com': 'gmail.com', 'gmail.cpm': 'gmail.com', 'gmail.ug': 'gmail.com', 'googlemail.co': 'googlemail.com',
  'yahoo.co': 'yahoo.com', 'yahoo.con': 'yahoo.com', 'yaho.com': 'yahoo.com', 'yahooo.com': 'yahoo.com', 'yhoo.com': 'yahoo.com',
  'hotmail.co': 'hotmail.com', 'hotmail.con': 'hotmail.com', 'hotmial.com': 'hotmail.com', 'hotmal.com': 'hotmail.com',
  'outlook.co': 'outlook.com', 'outlook.con': 'outlook.com', 'outlok.com': 'outlook.com', 'outllok.com': 'outlook.com',
  'icloud.co': 'icloud.com', 'icloud.con': 'icloud.com', 'iclod.com': 'icloud.com',
}

// Edit distance, for typos not in the list above (e.g. "gmaik.com")
function distance(a, b) {
  const d = Array.from({ length: a.length + 1 }, (_, i) => [i, ...Array(b.length).fill(0)])
  for (let j = 1; j <= b.length; j++) d[0][j] = j
  for (let i = 1; i <= a.length; i++)
    for (let j = 1; j <= b.length; j++)
      d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1))
  return d[a.length][b.length]
}

function suggestion(domain) {
  if (PROVIDERS.includes(domain)) return null
  if (KNOWN_TYPOS[domain]) return KNOWN_TYPOS[domain]
  const close = PROVIDERS.find((p) => distance(domain, p) === 1)
  return close ?? null
}

async function canReceiveMail(domain) {
  try {
    const mx = await dns.resolveMx(domain)
    if (mx?.some((r) => r.exchange && r.exchange !== '.')) return true
  } catch (e) {
    if (!['ENOTFOUND', 'ENODATA', 'ENOTIMP'].includes(e.code)) return true // DNS hiccup: don't block the person
  }
  try {
    await dns.resolve4(domain) // no MX but an address: mail can still be delivered there
    return true
  } catch (e) {
    return !['ENOTFOUND', 'ENODATA'].includes(e.code)
  }
}

export async function checkDeliverable(email) {
  const domain = email.split('@')[1] ?? ''
  const fix = suggestion(domain)
  if (fix) throw new HttpError(400, `Check your email address: did you mean ${email.split('@')[0]}@${fix}?`)
  if (!(await canReceiveMail(domain))) {
    throw new HttpError(400, `"${domain}" can't receive email. Check the address for typos.`)
  }
}
