import { ref } from 'vue'
import { daysLeftAt, rentEnds } from '@/utils/exactTime'

// The time now, ticking: what is counted to the exact moment (rent, subscriptions) changes on the screen by itself.
export const now = ref(Date.now())
// For working something out: the time right now (the ref above only says when to work it out again, and can be seconds old)
export const timeNow = () => (now.value, Date.now())
if (typeof window !== 'undefined') {
  const tick = () => (now.value = Date.now())
  setInterval(tick, 15_000)
  document.addEventListener('visibilitychange', () => document.visibilityState === 'visible' && tick())
}

// A tenant's paid time right now: days left (0 or less = ended, see utils/exactTime.js; null = not started)
export const rentDaysLeft = (t) => daysLeftAt(rentEnds(t), timeNow())
export const rentEnded = (t) => {
  const ends = rentEnds(t)
  return ends !== null && ends <= timeNow()
}
