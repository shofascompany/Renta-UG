// Mobile money networks in Uganda: how a tenant sends money from their own phone to the landlord.
// The landlord only types the number, the name the network shows, and (optionally) the dial code.
// Everything else (the steps) is written here, per network.
import { formatUGX } from '@/utils/format'

export const NETWORKS = {
  mtn: {
    id: 'mtn',
    label: 'MTN Mobile Money',
    short: 'MTN',
    dial: '*165#',
    sendDial: '*165*1#', // straight to "Send Money" (published by MTN Uganda)
    // The whole send, up to the PIN: Send Money → MoMo user → number → amount. Follows MTN Uganda's menu; check it on
    // a real phone with a small amount after any menu change by MTN.
    payCode: (number, amount) => `*165*1*1*${number}*${amount}#`,
    bg: '#ffcc00',
    ink: '#1f1a00',
    soft: '#fff7cc',
    gradient: 'linear-gradient(135deg,#ffd84d 0%,#ffcc00 45%,#e0a800 100%)',
    menu: ['Send Money', 'Mobile User'],
  },
  airtel: {
    id: 'airtel',
    label: 'Airtel Money',
    short: 'Airtel',
    dial: '*185#',
    sendDial: '*185*1#', // straight to "Send Money" (published by Airtel Uganda)
    // The whole send, up to the PIN: Send Money → Airtel Money user → number → amount (Airtel Uganda's menu)
    payCode: (number, amount) => `*185*1*1*${number}*${amount}#`,
    bg: '#e40000',
    ink: '#ffffff',
    soft: '#fde8e8',
    gradient: 'linear-gradient(135deg,#ff4d4d 0%,#e40000 50%,#9e0000 100%)',
    menu: ['Send Money', 'Airtel Money User'],
  },
}
export const NETWORK_IDS = ['mtn', 'airtel']

// 0772123456 → "0772 123 456"
export function prettyPhone(v) {
  const d = String(v ?? '').replace(/\D/g, '')
  const local = d.length >= 9 ? `0${d.slice(-9)}` : d
  return local.length === 10 ? `${local.slice(0, 4)} ${local.slice(4, 7)} ${local.slice(7)}` : String(v ?? '')
}
export const validUgPhone = (v) => /^(?:\+?256|0)?7\d{8}$/.test(String(v ?? '').replace(/[\s\-().]/g, ''))

export const dialCodeOf = (account) => account?.dialCode || NETWORKS[account?.network]?.dial || ''
// The code that opens the network's Send Money menu. A landlord's own special code (not the plain menu) is kept.
// The receiving number and the amount are NOT put into the code: the networks publish no code that takes them, so the
// tenant types them in the menu (they are shown on screen, with Copy buttons). The PIN is only ever typed in the menu.
export const sendCodeOf = (account) => {
  const n = NETWORKS[account?.network]
  const own = account?.dialCode?.trim()
  return own && own !== n?.dial ? own : n?.sendDial || n?.dial || ''
}
// The code that dials the whole payment, up to the PIN: the landlord's number (0772123456) and the amount are filled
// in. A landlord's own special code (e.g. a merchant code) is used as it is.
export function payCodeOf(account, amount) {
  const n = NETWORKS[account?.network]
  if (!n) return ''
  const own = account?.dialCode?.trim()
  if (own && own !== n.dial && own !== n.sendDial) return own
  const d = String(account.phone ?? '').replace(/\D/g, '')
  const amt = Math.round(Number(amount) || 0)
  return d.length >= 9 && amt > 0 ? n.payCode(`0${d.slice(-9)}`, amt) : n.sendDial
}

// Phones that let a web page open a USSD code (iPhones don't: the code is dialled by hand there)
export const canOpenUssd = () => typeof navigator !== 'undefined' && /Android/i.test(navigator.userAgent)

// tel: link that opens the phone's dialer with the code ready (# must be encoded)
export const dialHref = (code) => `tel:${encodeURIComponent(code)}`

// The steps followed on the phone. `payee`: whose number it is ("the landlord's", "Renta UG's").
// No reason / reference code: payments are matched by the names registered on the line used.
export function sendSteps(account, { amount, payee = "the landlord's" }) {
  const n = NETWORKS[account.network]
  const dial = sendCodeOf(account)
  const inSend = dial === n.sendDial
  return [
    dial ? `Dial ${dial} on your ${n.short} line.` : `Open the ${n.label} menu on your ${n.short} line.`,
    inSend ? `Choose "${n.menu[1]}".` : `Choose "${n.menu[0]}", then "${n.menu[1]}".`,
    `Enter ${payee} number: ${prettyPhone(account.phone)}.`,
    `Check that the name shown is ${account.accountName.toUpperCase()}.`,
    `Enter the amount: ${formatUGX(amount)}.`,
    'Enter your mobile money PIN to send.',
    'Come back here and continue.',
  ]
}
