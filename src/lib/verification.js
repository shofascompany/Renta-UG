// The sign-up that is waiting for its email code. Kept in sessionStorage so a refresh of the
// verification page doesn't lose it. Holds only the email and two timestamps: never the password.
const KEY = 'renta.verify'

export function saveVerification(v) {
  try {
    sessionStorage.setItem(KEY, JSON.stringify(v))
  } catch {
    /* storage blocked: the page falls back to the sign-up form */
  }
}

export function loadVerification() {
  try {
    const v = JSON.parse(sessionStorage.getItem(KEY) || 'null')
    return v?.email ? v : null
  } catch {
    return null
  }
}

export function clearVerification() {
  try {
    sessionStorage.removeItem(KEY)
  } catch {
    /* ignore */
  }
}
