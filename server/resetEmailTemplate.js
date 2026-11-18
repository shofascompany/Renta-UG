// The password-reset email: a button with the reset link. Same look as the sign-up code email
// (tables + inline styles for Gmail, Outlook and Apple Mail).
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c])
const FONT = "'Segoe UI',Roboto,Helvetica,Arial,sans-serif"

export function resetEmail({ name, link, minutes, site }) {
  const first = String(name ?? '').trim().split(/\s+/)[0] || 'there'
  const href = esc(link)

  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light only">
<title>Reset your Renta UG password</title>
<style>
  body{margin:0!important;padding:0!important;width:100%!important;-webkit-text-size-adjust:100%}
  @media only screen and (max-width:420px){ .outer{padding:14px 8px!important} .pad{padding-left:20px!important;padding-right:20px!important} .hero-title{font-size:23px!important} }
</style>
</head>
<body style="margin:0;padding:0;background:#eef4f3">
<div style="display:none;max-height:0;overflow:hidden;opacity:0">Reset your Renta UG password. The link works for ${minutes} minutes.</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="#eef4f3" style="background:#eef4f3;background-image:linear-gradient(180deg,#e3f3ef 0%,#eef4f3 45%,#f4f1fb 100%)">
<tr><td class="outer" align="center" style="padding:28px 12px">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:480px;width:100%">
    <tr><td style="border-radius:24px;overflow:hidden;background:#ffffff;box-shadow:0 18px 40px -22px rgba(10,59,56,.45)">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
        <tr><td class="pad" bgcolor="#0f766e" style="padding:30px 32px 34px;background:#0f766e;background-image:linear-gradient(135deg,#19b3a3 0%,#0f766e 48%,#0b3f4d 100%);border-radius:24px 24px 0 0">
          <div style="font-family:${FONT};font-size:16px;font-weight:700;color:#ffffff">Renta UG</div>
          <div class="hero-title" style="margin-top:20px;font-family:${FONT};font-size:26px;line-height:1.25;font-weight:800;color:#ffffff">Reset your password</div>
          <div style="margin-top:6px;font-family:${FONT};font-size:14px;line-height:1.5;color:#d5f5ef">Choose a new one in a few seconds.</div>
        </td></tr>
        <tr><td class="pad" style="padding:28px 32px 8px;font-family:${FONT};color:#0f172a">
          <p style="margin:0;font-size:16px;line-height:1.55">Hi ${esc(first)},</p>
          <p style="margin:8px 0 0;font-size:15px;line-height:1.6;color:#334155">We got a request to reset the password for your Renta UG account. Tap the button to choose a new password.</p>
        </td></tr>
        <tr><td align="center" style="padding:22px 24px 6px">
          <a href="${href}" style="display:inline-block;padding:14px 30px;border-radius:14px;background:#0f766e;background-image:linear-gradient(135deg,#19b3a3,#0f766e);font-family:${FONT};font-size:16px;font-weight:700;color:#ffffff;text-decoration:none">Reset my password</a>
        </td></tr>
        <tr><td align="center" style="padding:14px 24px 0">
          <span style="display:inline-block;padding:7px 14px;border-radius:999px;background:#fff7ed;border:1px solid #fed7aa;font-family:${FONT};font-size:13px;font-weight:600;color:#9a3412">&#9201;&nbsp; The link works for ${minutes} minutes, once</span>
        </td></tr>
        <tr><td class="pad" style="padding:22px 32px 4px;font-family:${FONT};font-size:12.5px;line-height:1.6;color:#64748b">
          Button not working? Copy this link into your browser:<br>
          <a href="${href}" style="color:#0f766e;word-break:break-all">${href}</a>
        </td></tr>
        <tr><td class="pad" style="padding:16px 32px 30px;font-family:${FONT}">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="#f8fafc" style="background:#f8fafc;border-radius:14px">
            <tr><td style="padding:14px 16px;font-size:12.5px;line-height:1.55;color:#64748b">&#128274;&nbsp; Didn't ask for this? Ignore this email: your password stays the same. Renta UG will never ask for your password.</td></tr>
          </table>
        </td></tr>
      </table>
    </td></tr>
    <tr><td align="center" style="padding:22px 16px 6px;font-family:${FONT};font-size:12px;line-height:1.6;color:#94a3b8">
      Renta UG &middot; Rent made simple in Uganda<br><a href="${esc(site)}" style="color:#0f766e;text-decoration:none;font-weight:600">${esc(String(site).replace(/^https?:\/\//, ''))}</a>
    </td></tr>
  </table>
</td></tr>
</table>
</body>
</html>`

  const text =
    `Hi ${first},\n\n` +
    `We got a request to reset your Renta UG password. Open this link to choose a new one:\n\n${link}\n\n` +
    `The link works for ${minutes} minutes and only once. If you didn't ask for this, ignore this email: your password stays the same.\n\n` +
    `Renta UG · ${site}`

  return { subject: 'Reset your Renta UG password', html, text }
}
