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
// tel: link that opens the phone's dialer with the code ready (# must be encoded)
export const dialHref = (code) => `tel:${encodeURIComponent(code)}`

// The steps the tenant follows on their phone
export function sendSteps(account, { amount, code }) {
  const n = NETWORKS[account.network]
  const dial = dialCodeOf(account)
  return [
    dial ? `Dial ${dial} on your ${n.short} line.` : `Open the ${n.label} menu on your ${n.short} line.`,
    `Choose "${n.menu[0]}", then "${n.menu[1]}".`,
    `Enter the landlord's number: ${prettyPhone(account.phone)}.`,
    `Check that the name shown is ${account.accountName.toUpperCase()}.`,
    `Enter the amount: ${formatUGX(amount)}.`,
    `For the reason, type ${code}.`,
    'Enter your mobile money PIN to send.',
    'Come back here and tap "I have sent the money".',
  ]
}
