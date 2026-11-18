// "Forgot password": the app (not Supabase) emails the reset link. Shared by the Express server and the Netlify Function.
//   POST /api/password/forgot { email } → emails a link to /reset-password?token=…  (valid 1 hour, works once)
// The answer is always the same ("if an account uses this email…"), so nobody can use this to find out who has an account.
import { HttpError, isPlaceholderEmail } from './admin.js'
import { sendMail } from './mailer.js'
import { resetEmail } from './resetEmailTemplate.js'

export const LINK_MINUTES = 60
const COOLDOWN_S = 60 // one link per minute per account: stops anyone flooding an inbox
const normalEmail = (v) => String(v ?? '').trim().toLowerCase()

// Where the link points. Never taken from the request, so a stranger can't make a link to another site.
const siteUrl = () =>
  String(process.env.SITE_URL || process.env.URL || process.env.CLIENT_URL || 'https://rentaug.netlify.app').replace(/\/+$/, '')

export async function forgot(db, body) {
  const email = normalEmail(body?.email)
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) throw new HttpError(400, 'Enter a valid email address.')
  const done = { ok: true }
  if (isPlaceholderEmail(email)) return done

  const { data: profile, error } = await db
    .from('profiles')
    .select('id, email, full_name, active')
    .ilike('email', email.replace(/[\\%_]/g, '\\$&'))
    .limit(1)
    .maybeSingle()
  if (error) throw new HttpError(500, error.message)
  if (!profile || profile.active === false) return done // no such account, or suspended: say nothing

  // Cooldown, remembered on the account itself
  const { data: found } = await db.auth.admin.getUserById(profile.id)
  const last = Number(found?.user?.app_metadata?.reset_sent_at ?? 0)
  const wait = COOLDOWN_S - Math.floor((Date.now() - last) / 1000)
  if (wait > 0) throw new HttpError(429, `A link was just sent. You can ask for another in ${wait} seconds.`)

  const { data, error: linkError } = await db.auth.admin.generateLink({ type: 'recovery', email: profile.email })
  if (linkError) throw new HttpError(400, linkError.message)
  const link = `${siteUrl()}/reset-password?token=${encodeURIComponent(data.properties.hashed_token)}`

  const { subject, html, text } = resetEmail({ name: profile.full_name, link, minutes: LINK_MINUTES, site: siteUrl() })
  await sendMail({ to: profile.email, subject, text, html })
  await db.auth.admin.updateUserById(profile.id, { app_metadata: { reset_sent_at: Date.now() } })
  return done
}
