// Time is counted to the exact moment, the same as the database (database/61): a day is 24 complete hours from when
// it started, not a calendar day. The database keeps the day a thing ends and, beside it, the time of day. That time is
// never shown to anyone. Uganda is always UTC+3, whatever the phone is set to.
export const DAY_MS = 86_400_000
const day = (d) => String(d).slice(0, 10)
const at = (d, clock) => new Date(`${day(d)}T${String(clock).slice(0, 8)}+03:00`).getTime()

// A day like 2026-11-25, or a moment → milliseconds
export const momentOf = (x) => (typeof x === 'string' && x.length === 10 ? at(x, '12:00:00') : new Date(x).getTime())

// The day (in Uganda) of a moment, and a day moved by n days
export const ugandaDay = (ms) => new Date(ms + 3 * 3_600_000).toISOString().slice(0, 10)
export const moveDay = (iso, n) => new Date(Date.parse(`${day(iso)}T00:00:00Z`) + n * DAY_MS).toISOString().slice(0, 10)

// The moment a tenant's paid time ends (null = not started). No time of day known: the end of that day.
export const rentEnds = (t) => (!t?.leaseEnd ? null : t.leaseClock ? at(t.leaseEnd, t.leaseClock) : at(t.leaseEnd, '00:00:00') + DAY_MS)
// The moment a subscription ends: the day after its last whole day, at its time of day
export const subscriptionEnds = (until, clock) => (until ? at(until, clock || '00:00:00') + DAY_MS : null)

// Days left: one is taken off each time 24 hours are complete (30 right after paying, 1 during the last 24 hours).
// 0 or less = it has ended: 0 in the first 24 hours after the end, then -1, -2… complete days since.
export const daysLeftAt = (ends, now) => (ends === null ? null : ends > now ? Math.ceil((ends - now) / DAY_MS) : 0 - Math.floor((now - ends) / DAY_MS))
