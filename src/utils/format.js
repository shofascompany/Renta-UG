const ugx = new Intl.NumberFormat('en-UG', { style: 'currency', currency: 'UGX', maximumFractionDigits: 0 })

export const formatUGX = (n) => ugx.format(n ?? 0)

// Big amounts in millions, exact to the thousand and never rounded up: 1.2M, 12.34M, 21.897M.
// The hundreds are left out (21,897,650 → 21.897M). Below a million the full number is shown: 850,000.
export function millionsUGX(n) {
  const v = Math.floor(Number(n) || 0)
  if (v < 1_000_000) return v.toLocaleString('en-UG')
  const thousands = Math.floor(v / 1000)
  const decimals = String(thousands % 1000).padStart(3, '0').replace(/0+$/, '')
  return `${Math.floor(thousands / 1000).toLocaleString('en-UG')}${decimals ? `.${decimals}` : ''}M`
}

export const formatDate = (d) =>
  d ? new Date(d).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) : '—'

// The local day (2026-11-25) and month (2026-11) of a moment. Never cut the saved text: it is in UTC, so a payment
// made just after midnight would land on the day (or month) before.
export const dayOf = (d) => (d ? new Date(d).toLocaleDateString('en-CA') : '')
export const monthOf = (d) => dayOf(d).slice(0, 7)

export const formatPeriod = (p) => {
  if (!p) return '—'
  const [y, m] = p.split('-').map(Number)
  return new Date(y, m - 1, 1).toLocaleDateString('en-GB', { month: 'long', year: 'numeric' })
}

export const timeAgo = (d) => {
  const diff = (Date.now() - new Date(d).getTime()) / 1000
  if (diff < 60) return 'just now'
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`
  if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`
  if (diff < 86400 * 7) return `${Math.floor(diff / 86400)}d ago`
  return formatDate(d)
}

// "2 months, 5 days left" style wording for a number of days
export function timeLeft(days) {
  if (days === null || days === undefined) return 'Starts when they pay'
  if (days < 0) return `${Math.abs(days)} debt day${days === -1 ? '' : 's'}` // month ended, not paid yet
  if (days === 0) return 'Just ended' // not one complete day since the end
  // A rent month is 30 days
  if (days < 30) return `${days} day${days === 1 ? '' : 's'} left`
  const months = Math.floor(days / 30)
  if (months < 12) {
    const rest = days - months * 30
    return `${months} month${months === 1 ? '' : 's'}${rest ? `, ${rest} day${rest === 1 ? '' : 's'}` : ''} left`
  }
  const years = Math.floor(months / 12)
  const m = months % 12
  return `${years} year${years === 1 ? '' : 's'}${m ? `, ${m} month${m === 1 ? '' : 's'}` : ''} left`
}
