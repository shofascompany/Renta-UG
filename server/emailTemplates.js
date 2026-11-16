// Email designs. Built for email apps (Gmail, Outlook, Apple Mail, Yahoo): tables + inline styles,
// a fluid 100% width that stops at 480px, and a few media queries that tighten spacing on small phones.
// Gradients have a solid colour behind them for the email apps that can't show gradients (Outlook).

const SITE = 'https://rentaug.netlify.app'
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c])

// The 6-character sign-up code
export function verificationEmail({ name, code, minutes }) {
  const first = esc(String(name ?? '').trim().split(/\s+/)[0] || 'there')
  const chars = String(code).toUpperCase().split('')
  const boxes = chars
    .map(
      (c) => `<td class="cbox" align="center" valign="middle" width="44" height="54" bgcolor="#ffffff" style="width:44px;height:54px;border:1px solid #c7ece6;border-radius:12px;background:#ffffff;font-family:Consolas,'SF Mono',Menlo,monospace;font-size:26px;font-weight:700;color:#0f766e;box-shadow:0 4px 10px -6px rgba(15,118,110,.45)">${esc(c)}</td>`,
    )
    .join('<td class="cgap" width="6" style="width:6px;font-size:0;line-height:0">&nbsp;</td>')

  const html = `<!doctype html>
<html lang="en" xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="x-apple-disable-message-reformatting">
<meta name="color-scheme" content="light only">
<meta name="supported-color-schemes" content="light only">
<title>Your Renta UG code</title>
<style>
  body{margin:0!important;padding:0!important;width:100%!important;-webkit-text-size-adjust:100%;-ms-text-size-adjust:100%}
  table{border-collapse:separate}
  a{color:#0f766e}
  @media only screen and (max-width:420px){
    .outer{padding:14px 8px!important}
    .pad{padding-left:20px!important;padding-right:20px!important}
    .hero-title{font-size:23px!important}
    .cbox{width:38px!important;height:48px!important;font-size:22px!important;border-radius:10px!important}
    .cgap{width:4px!important}
  }
  @media only screen and (max-width:340px){
    .cbox{width:33px!important;height:44px!important;font-size:19px!important}
    .cgap{width:3px!important}
  }
</style>
</head>
<body style="margin:0;padding:0;background:#eef4f3">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;mso-hide:all">Your code is ${esc(code)}. It works for ${minutes} minutes.&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;&#8199;&#847;</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="#eef4f3" style="background:#eef4f3;background-image:linear-gradient(180deg,#e3f3ef 0%,#eef4f3 45%,#f4f1fb 100%)">
<tr><td class="outer" align="center" style="padding:28px 12px">

  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:480px;width:100%">

    <!-- Card -->
    <tr><td style="border-radius:24px;overflow:hidden;background:#ffffff;box-shadow:0 18px 40px -22px rgba(10,59,56,.45)">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">

        <!-- Gradient header -->
        <tr><td class="pad" bgcolor="#0f766e" style="padding:30px 32px 34px;background:#0f766e;background-image:linear-gradient(135deg,#19b3a3 0%,#0f766e 48%,#0b3f4d 100%);border-radius:24px 24px 0 0">
          <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>
            <td width="38" height="38" align="center" valign="middle" style="width:38px;height:38px;border-radius:11px;background:#ffffff;background:rgba(255,255,255,.18);border:1px solid rgba(255,255,255,.35);font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:19px;font-weight:800;color:#ffffff">R</td>
            <td style="padding-left:10px;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:16px;font-weight:700;color:#ffffff;letter-spacing:.01em">Renta UG</td>
          </tr></table>
          <div class="hero-title" style="margin-top:22px;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:26px;line-height:1.25;font-weight:800;color:#ffffff">Verify your email</div>
          <div style="margin-top:6px;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:14px;line-height:1.5;color:#d5f5ef">One quick step and your account is ready.</div>
        </td></tr>

        <!-- Body -->
        <tr><td class="pad" style="padding:28px 32px 8px;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#0f172a">
          <p style="margin:0;font-size:16px;line-height:1.55">Hi ${first},</p>
          <p style="margin:8px 0 0;font-size:15px;line-height:1.6;color:#334155">Enter this code in the Renta UG app to finish creating your account:</p>
        </td></tr>

        <!-- Code -->
        <tr><td align="center" style="padding:22px 12px 6px">
          <table role="presentation" cellpadding="0" cellspacing="0" border="0" bgcolor="#effaf7" style="background:#effaf7;background-image:linear-gradient(135deg,#ecfdf9 0%,#f1f7ff 100%);border-radius:18px;border:1px solid #d3f0ea">
            <tr><td style="padding:14px 14px">
              <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>${boxes}</tr></table>
            </td></tr>
          </table>
        </td></tr>

        <!-- Expiry pill -->
        <tr><td align="center" style="padding:14px 24px 0">
          <span style="display:inline-block;padding:7px 14px;border-radius:999px;background:#fff7ed;border:1px solid #fed7aa;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:13px;font-weight:600;color:#9a3412">&#9201;&nbsp; Expires in ${minutes} minutes</span>
        </td></tr>

        <!-- Steps -->
        <tr><td class="pad" style="padding:26px 32px 4px;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-top:1px solid #eef2f7">
            <tr><td style="padding-top:18px;font-size:13px;line-height:1.6;color:#475569">
              <strong style="color:#0f172a">What happens next</strong><br>
              Once the code is accepted, you go straight to your dashboard. Then connect to your home with the code from your landlord.
            </td></tr>
          </table>
        </td></tr>

        <!-- Safety note -->
        <tr><td class="pad" style="padding:16px 32px 30px;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="#f8fafc" style="background:#f8fafc;border-radius:14px">
            <tr><td style="padding:14px 16px;font-size:12.5px;line-height:1.55;color:#64748b">
              &#128274;&nbsp; Renta UG will never ask you for this code by phone or SMS. If you didn't try to sign up, ignore this email and no account will be created.
            </td></tr>
          </table>
        </td></tr>

      </table>
    </td></tr>

    <!-- Footer -->
    <tr><td align="center" style="padding:22px 16px 6px;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:12px;line-height:1.6;color:#94a3b8">
      Renta UG &middot; Rent made simple in Uganda<br>
      <a href="${SITE}" style="color:#0f766e;text-decoration:none;font-weight:600">rentaug.netlify.app</a>
      &nbsp;&middot;&nbsp; <a href="${SITE}/privacy" style="color:#94a3b8;text-decoration:underline">Privacy</a>
    </td></tr>

  </table>
</td></tr>
</table>
</body>
</html>`

  const text =
    `Hi ${String(name ?? '').trim().split(/\s+/)[0] || 'there'},\n\n` +
    `Your Renta UG verification code is: ${code}\n\n` +
    `It expires in ${minutes} minutes. Enter it in the app to finish creating your account.\n\n` +
    `Renta UG will never ask you for this code by phone or SMS. If you didn't try to sign up, ignore this email.\n\n` +
    `Renta UG · ${SITE}`

  return { subject: `${code} is your Renta UG code`, html, text }
}
