import { formatUGX } from '../utils/format.js' // relative, so the tests can load this file too

// A plain landscape receipt, drawn on a canvas and saved as a PNG.
// No decoration: just the facts someone may need to prove a rent payment.
const W = 1600
const H = 900
const FONT = '"Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif'
const INK = '#0f172a'
const MUTED = '#64748b'
const LINE = '#cbd5e1'

const day = (d) =>
  d ? new Date(String(d).length === 10 ? `${d}T12:00:00` : d).toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' }) : '—'
const shortDay = (d) =>
  d ? new Date(String(d).length === 10 ? `${d}T12:00:00` : d).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) : '—'

// An 8-digit receipt number, always the same for the same payment (from its id), e.g. 30591874
export const receiptNumber = (id) => {
  const hex = String(id).replace(/[^0-9a-f]/gi, '').slice(0, 12) || '0'
  return String(parseInt(hex, 16) % 100_000_000).padStart(8, '0')
}
// File name: the tenant's name and the receipt number, e.g. "John Kamera Receipt No. 30591874.png"
export const receiptFileName = (r) => {
  const name = String(r.tenantName ?? '')
    .replace(/[\\/:*?"<>|]+/g, ' ') // characters files can't have
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/\b\p{L}/gu, (c) => c.toUpperCase())
  return `${name || 'Renta'} Receipt No. ${receiptNumber(r.id)}.png`
}

// Whole months are shown as months only ("1 month", "2 months"); less than a month is shown in days ("12 days").
// A rent month is 30 days, so 30 days = 1 month. Days are added only when they are left over ("1 month 15 days").
export function rentalTime(days) {
  const n = Math.max(0, Math.round(Number(days) || 0))
  if (!n) return '—'
  const months = Math.floor(n / 30)
  const rest = n % 30
  return [months && `${months} month${months === 1 ? '' : 's'}`, rest && `${rest} day${rest === 1 ? '' : 's'}`].filter(Boolean).join(' ')
}

// The "Rent for" line: when the payment was made, how long it lasts, when it ends.
// Without that information (older payments) it stays the rent month, as before.
function rentFor(r) {
  const w = r.window
  if (w?.days && w.to) return `Paid ${shortDay(r.paidOn)} · ${rentalTime(w.days)} · ends ${shortDay(w.to)}`
  return r.months?.length ? r.months.join(', ') : '—'
}

// Shorten text with "…" so it never runs past `max` pixels
function fit(ctx, text, max) {
  let t = String(text ?? '—')
  if (ctx.measureText(t).width <= max) return t
  while (t.length > 1 && ctx.measureText(`${t}…`).width > max) t = t.slice(0, -1)
  return `${t}…`
}

/**
 * r = { id, amount, method, paidOn, confirmedOn, confirmedBy, months[], details,
 *       tenantName, tenantPhone, property, landlordName,
 *       window?: { from, to, days },
 *       instalments?: { period, rent, paid, balance, days, current, rows: [{ id, n, at, method, amount, days, totalAfter }] } }
 * With instalments (a month paid in turns) the receipt grows a table listing every payment.
 */
export function drawReceipt(r) {
  const inst = r.instalments?.rows?.length ? r.instalments : null
  const ROW = 50
  const extra = inst ? 150 + inst.rows.length * ROW + 70 : 0
  const c = document.createElement('canvas')
  c.width = W
  c.height = H + extra
  const ctx = c.getContext('2d')
  ctx.fillStyle = '#fff'
  ctx.fillRect(0, 0, W, H + extra)
  ctx.textBaseline = 'alphabetic'
  const L = 90
  const R = W - 90

  // Header
  ctx.fillStyle = INK
  ctx.font = `700 40px ${FONT}`
  ctx.fillText('Renta UG', L, 120)
  ctx.fillStyle = MUTED
  ctx.font = `600 24px ${FONT}`
  ctx.fillText('RENT PAYMENT RECEIPT', L, 160)

  ctx.textAlign = 'right'
  ctx.fillStyle = INK
  ctx.font = `700 28px ${FONT}`
  ctx.fillText(`Receipt No. ${receiptNumber(r.id)}`, R, 120)
  ctx.fillStyle = MUTED
  ctx.font = `400 22px ${FONT}`
  ctx.fillText(`Issued ${day(new Date().toISOString())}`, R, 160)
  ctx.textAlign = 'left'

  ctx.strokeStyle = INK
  ctx.lineWidth = 2
  ctx.beginPath()
  ctx.moveTo(L, 195)
  ctx.lineTo(R, 195)
  ctx.stroke()

  // Amount
  ctx.fillStyle = MUTED
  ctx.font = `600 22px ${FONT}`
  ctx.fillText('AMOUNT PAID', L, 255)
  ctx.fillStyle = INK
  ctx.font = `700 64px ${FONT}`
  ctx.fillText(formatUGX(r.amount), L, 330)
  ctx.textAlign = 'right'
  ctx.font = `700 26px ${FONT}`
  ctx.fillText(inst && inst.balance > 0 ? 'PART PAYMENT · CONFIRMED' : 'PAID · CONFIRMED', R, 300)
  ctx.textAlign = 'left'

  // Details: two columns of label / value
  const rows = [
    [
      ['Received from', r.tenantName],
      ['Tenant phone', r.tenantPhone],
      ['Property', r.property],
      ['Paid to (landlord)', r.landlordName],
      ['Rent for', rentFor(r)],
    ],
    [
      ['Payment method', r.method],
      ['Date paid', day(r.paidOn)],
      ['Confirmed on', day(r.confirmedOn)],
      ['Confirmed by', r.confirmedBy],
      ['Details', r.details],
    ],
  ]
  const colW = (R - L - 60) / 2
  rows.forEach((col, ci) => {
    const x = L + ci * (colW + 60)
    col.forEach(([label, value], ri) => {
      const y = 400 + ri * 78
      ctx.fillStyle = MUTED
      ctx.font = `400 20px ${FONT}`
      ctx.fillText(label, x, y)
      ctx.fillStyle = INK
      ctx.font = `600 26px ${FONT}`
      ctx.fillText(fit(ctx, value || '—', colW), x, y + 34)
    })
  })

  // Paid in turns: every instalment towards the month
  if (inst) {
    let y = 820
    ctx.strokeStyle = LINE
    ctx.lineWidth = 1.5
    ctx.beginPath()
    ctx.moveTo(L, y)
    ctx.lineTo(R, y)
    ctx.stroke()
    y += 50
    ctx.fillStyle = INK
    ctx.font = `700 26px ${FONT}`
    ctx.fillText(`Payments towards ${inst.period} rent (${inst.rows.length} payment${inst.rows.length === 1 ? '' : 's'})`, L, y)
    y += 46
    const cols = [L, L + 130, L + 470, L + 900, L + 1150] // No. · Date · Method · Amount · Days
    const heads = ['No.', 'Date', 'Method', 'Amount', 'Days covered']
    ctx.fillStyle = MUTED
    ctx.font = `600 19px ${FONT}`
    heads.forEach((h, i) => {
      ctx.textAlign = i >= 3 ? 'right' : 'left'
      ctx.fillText(h, i === 3 ? cols[4] - 60 : i === 4 ? R : cols[i], y)
    })
    ctx.textAlign = 'left'
    y += 14
    for (const row of inst.rows) {
      const mine = row.id === inst.current
      if (mine) {
        ctx.fillStyle = '#f1f5f9'
        ctx.fillRect(L - 14, y + 6, R - L + 28, ROW - 6)
      }
      y += ROW - 10
      ctx.fillStyle = INK
      ctx.font = `${mine ? 700 : 500} 22px ${FONT}`
      ctx.fillText(`${row.n}${mine ? ' (this receipt)' : ''}`, cols[0], y)
      ctx.fillText(day(row.at), cols[1], y)
      ctx.fillText(fit(ctx, row.method || '—', cols[3] - cols[2] - 40), cols[2], y)
      ctx.textAlign = 'right'
      ctx.fillText(formatUGX(row.amount), cols[4] - 60, y)
      ctx.fillText(`${row.days} day${row.days === 1 ? '' : 's'}`, R, y)
      ctx.textAlign = 'left'
      y += 10
    }
    y += 50
    ctx.fillStyle = INK
    ctx.font = `700 23px ${FONT}`
    ctx.fillText(
      fit(ctx, `Paid ${formatUGX(inst.paid)} of ${formatUGX(inst.rent)} · ${inst.balance > 0 ? `Balance ${formatUGX(inst.balance)}` : 'Paid in full'} · ${inst.days} of 30 days covered`, R - L),
      L,
      y,
    )
  }

  // Footer
  const fy = 800 + extra
  ctx.strokeStyle = LINE
  ctx.lineWidth = 1.5
  ctx.beginPath()
  ctx.moveTo(L, fy)
  ctx.lineTo(R, fy)
  ctx.stroke()
  ctx.fillStyle = MUTED
  ctx.font = `400 19px ${FONT}`
  ctx.fillText(
    fit(ctx, `This receipt records a payment confirmed by the landlord and saved in Renta UG. Quote ${receiptNumber(r.id)} for any question about it.`, R - L),
    L,
    fy + 40,
  )
  return c
}

const standaloneIOS = () => /iP(hone|ad|od)/.test(navigator.userAgent) && window.matchMedia?.('(display-mode: standalone)').matches

function saveBlob(blob, name) {
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = name
  document.body.appendChild(a)
  a.click()
  a.remove()
  setTimeout(() => URL.revokeObjectURL(url), 4000)
}

// Made in one go, with no waiting: phones only open the share list straight from the tap itself
function makeFile(r) {
  const bytes = Uint8Array.from(atob(drawReceipt(r).toDataURL('image/png').split(',')[1]), (c) => c.charCodeAt(0))
  const blob = new Blob([bytes], { type: 'image/png' })
  const name = receiptFileName(r)
  return { blob, name, file: new File([blob], name, { type: 'image/png' }) }
}

// Draw it and save it as a PNG (phones without download support get the share sheet)
export async function downloadReceipt(r) {
  const { blob, name, file } = makeFile(r)
  if (standaloneIOS() && navigator.canShare?.({ files: [file] })) {
    try {
      await navigator.share({ files: [file], title: name })
      return
    } catch {
      /* cancelled: fall back to a normal download */
    }
  }
  saveBlob(blob, name)
}

// Can this device send the receipt picture to another app (WhatsApp…)? Phones can; most computers cannot.
// Where it can't, the WhatsApp button is not shown at all.
export function canShareReceiptImage() {
  try {
    if (typeof navigator === 'undefined' || !navigator.canShare || !navigator.share) return false
    return navigator.canShare({ files: [new File(['x'], 'receipt.png', { type: 'image/png' })] })
  } catch {
    return false
  }
}

// The same PNG as the download, handed straight to the phone's share sheet: pick WhatsApp, then the person.
// Nothing is downloaded first. (A web page cannot open one chosen WhatsApp chat with a picture attached, so
// WhatsApp is chosen in the sheet the phone shows.)
export async function shareReceiptImage(r) {
  try {
    await navigator.share({ files: [makeFile(r).file] }) // the picture only: no text, no link
    return 'shared'
  } catch (e) {
    // Closed without sending, or the list is already open: nothing to do
    if (e?.name === 'AbortError' || e?.name === 'InvalidStateError') return 'cancelled'
    throw e
  }
}
