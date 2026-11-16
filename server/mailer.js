// Sends email (the sign-up verification code). Two ways, whichever is set up:
//   1. Gmail / any SMTP:  SMTP_USER + SMTP_PASS   (for Gmail, SMTP_PASS is an "App password")
//                          optional: SMTP_HOST (default smtp.gmail.com), SMTP_PORT (default 465), MAIL_FROM
//   2. Resend (resend.com): RESEND_API_KEY + MAIL_FROM  (MAIL_FROM must be on a domain you verified there)
// Shared by the Express server and the Netlify Function.
import nodemailer from 'nodemailer'
import { HttpError } from './admin.js'

export function mailEnabled(env = process.env) {
  return Boolean((env.SMTP_USER && env.SMTP_PASS) || (env.RESEND_API_KEY && env.MAIL_FROM))
}

export async function sendMail({ to, subject, text, html }, env = process.env) {
  if (env.RESEND_API_KEY && env.MAIL_FROM) {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${env.RESEND_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: env.MAIL_FROM, to: [to], subject, text, html }),
    })
    if (!res.ok) {
      const detail = await res.text().catch(() => '')
      console.error(`[mail] Resend ${res.status}: ${detail.slice(0, 200)}`)
      throw new HttpError(502, 'We could not send the email right now. Please try again in a moment.')
    }
    return
  }

  if (env.SMTP_USER && env.SMTP_PASS) {
    const port = Number(env.SMTP_PORT || 465)
    const transport = nodemailer.createTransport({
      host: env.SMTP_HOST || 'smtp.gmail.com',
      port,
      secure: port === 465,
      auth: { user: env.SMTP_USER, pass: String(env.SMTP_PASS).replace(/\s+/g, '') }, // Gmail shows app passwords with spaces
    })
    try {
      await transport.sendMail({ from: env.MAIL_FROM || `Renta UG <${env.SMTP_USER}>`, to, subject, text, html })
    } catch (e) {
      console.error(`[mail] SMTP: ${e.message}`)
      throw new HttpError(502, 'We could not send the email right now. Please try again in a moment.')
    }
    return
  }

  throw new HttpError(503, 'Email sending is not set up yet. The owner must add SMTP_USER and SMTP_PASS (see DEPLOY_KEYS.md).')
}
