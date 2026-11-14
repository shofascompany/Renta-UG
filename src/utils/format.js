const ugx = new Intl.NumberFormat('en-UG', { style: 'currency', currency: 'UGX', maximumFractionDigits: 0 })

export const formatUGX = (n) => ugx.format(n ?? 0)

export const formatDate = (d) =>
  d ? new Date(d).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) : '—'

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

export const daysUntil = (d) => Math.ceil((new Date(d).setHours(0, 0, 0, 0) - new Date().setHours(0, 0, 0, 0)) / 86400000)

export const uid = (prefix = '') => prefix + Math.random().toString(36).slice(2, 10)

// "2 months, 5 days left" style wording for a number of days
export function timeLeft(days) {
  if (days === null || days === undefined) return 'Starts when they pay'
  if (days < 0) return `Ended ${Math.abs(days)} day${days === -1 ? '' : 's'} ago`
  if (days === 0) return 'Ends today'
  if (days < 31) return `${days} day${days === 1 ? '' : 's'} left`
  const months = Math.floor(days / 30.44)
  if (months < 12) {
    const rest = Math.round(days - months * 30.44)
    return `${months} month${months === 1 ? '' : 's'}${rest ? `, ${rest} day${rest === 1 ? '' : 's'}` : ''} left`
  }
  const years = Math.floor(months / 12)
  const m = months % 12
  return `${years} year${years === 1 ? '' : 's'}${m ? `, ${m} month${m === 1 ? '' : 's'}` : ''} left`
}
