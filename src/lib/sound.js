// A short two-note chime for new notifications, made in the browser (no sound file to download).
// Browsers only allow sound after the person has touched the page once, so the first tap unlocks it.
let ctx = null

function context() {
  if (ctx) return ctx
  const AC = window.AudioContext || window.webkitAudioContext
  if (!AC) return null
  ctx = new AC()
  return ctx
}

export function unlockSound() {
  const c = context()
  if (c && c.state === 'suspended') c.resume().catch(() => {})
}

function note(c, freq, start, length, volume) {
  const osc = c.createOscillator()
  const gain = c.createGain()
  osc.type = 'sine'
  osc.frequency.setValueAtTime(freq, start)
  gain.gain.setValueAtTime(0.0001, start)
  gain.gain.exponentialRampToValueAtTime(volume, start + 0.015)
  gain.gain.exponentialRampToValueAtTime(0.0001, start + length)
  osc.connect(gain).connect(c.destination)
  osc.start(start)
  osc.stop(start + length + 0.05)
}

export function playChime() {
  try {
    if (localStorage.getItem('renta.sound') === 'off') return
  } catch {
    /* private mode: play anyway */
  }
  const c = context()
  if (!c || c.state !== 'running') return
  const t = c.currentTime + 0.02
  note(c, 880, t, 0.22, 0.18) // A5
  note(c, 1318.5, t + 0.12, 0.35, 0.14) // E6
}
