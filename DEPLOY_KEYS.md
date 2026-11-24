# Renta UG: deploy checklist + keys

The code lives on GitHub (`shofascompany/Renta-UG`, branch `main`). Netlify builds the live site
(`https://rentaug.netlify.app`) from it. **Keys never go to GitHub**: they live in Netlify's environment variables.

| File (on your computer) | Goes to GitHub? | What it holds |
|---|---|---|
| `.env` | No (`.gitignore`) | Secret keys for `npm run server` on your computer |
| `.env.netlify` | No (`.gitignore`) | Every key Netlify needs, ready to import |
| `.env.production` | Yes, on purpose | Only PUBLIC values (Supabase address, anon key, public notification key), already built into the website |
| `.env.example` | Yes | Empty template |

`PERMANENT_ACCOUNT_PASSWORD` stays in `.env` only (used by `npm run permanent-account` on your computer). Don't put it in `.env.netlify`.

---

## Launch checklist (in this order)

### 1. Update the database first
Supabase → **SQL Editor** → open `database/update_existing.sql` → paste all → **Run**.
Safe to run again; keeps all data. The new app needs it (payments, mobile money numbers, rent months,
error reports, health checks, adding tenants by email or phone, subscriptions, the permanent account).

Then, on your computer, in this project folder: **`npm run permanent-account`**. It sets the fixed password of the
permanent landlord account (ngumisiriza@gmail.com) from `PERMANENT_ACCOUNT_PASSWORD` in your private `.env`, then
test-signs in and prints `sign-in test: OK`. Run it again whenever you want to repair that account. The password is
never in the code or on Netlify.

### 2. Upload the code to GitHub
GitHub Desktop → this repository → write a summary (e.g. "Mobile money, health checks, legal pages") →
**Commit to main** → **Push origin**. Netlify starts building by itself.

### 3. Keys in Netlify (once, and whenever a key changes)
Netlify → your site → **Site configuration → Environment variables → Add a variable → Import from a .env file**.
Open `.env.netlify`, copy everything, paste, keep **All scopes**, import.
Delete any old variables that are no longer used: `RELWORX_API_KEY`, `RELWORX_ACCOUNT_NO`, `PAYMENTS_TEST_MODE`,
`PAYMENT_EMAIL_FALLBACK`, `FLW_SECRET_KEY`, `FLW_WEBHOOK_HASH`, `SSENTEZO_*`, `PAYMENT_PROVIDER`.

### 4. Deploy
Netlify → **Deploys → Trigger deploy → Deploy site** (needed after changing keys: `VITE_…` keys are built into the app).

### 5. Check it is working
1. Supabase → **Authentication → URL Configuration** → Site URL `https://rentaug.netlify.app`.
2. Open `https://rentaug.netlify.app/admin2026` → **Health & settings** → **Run checks now** → all green
   (SMS shows a warning until the Africa's Talking keys are added).
3. Sign up a test tenant, add them as a landlord with their email, connect with the code, send a test payment and confirm it.

---

## The keys

| Variable | What it is | Where to get it | Secret? |
|---|---|---|---|
| `VITE_SUPABASE_URL` | Supabase project address | Supabase → Project Settings → API | No |
| `VITE_SUPABASE_ANON_KEY` | Public key used in the browser | Supabase → API keys → `anon` | No (protected by database rules) |
| `SUPABASE_SERVICE_ROLE_KEY` | Full-power key for server functions | Supabase → API keys → `service_role` | **YES** |
| `VITE_VAPID_PUBLIC_KEY` | Phone notifications (public half) | `npx web-push generate-vapid-keys` | No |
| `VAPID_PRIVATE_KEY` | Phone notifications (private half) | Same command | **YES** |
| `VAPID_SUBJECT` | Contact for phone notifications | `mailto:` + your support email | No |
| `CLIENT_URL` | Live address | `https://rentaug.netlify.app` | No |
| `SMTP_USER` | Gmail that sends sign-up codes | Your Renta UG Gmail | No |
| `SMTP_PASS` | That Gmail's **App password** | Google Account → Security → 2-Step Verification → App passwords | **YES** |
| `MAIL_FROM` | Sender name on emails | `Renta UG <the same Gmail>`, or with Resend `Renta UG <no-reply@your-domain>` | No |
| `RESEND_API_KEY` | Sends emails through Resend instead of Gmail (better inbox delivery). When set with `MAIL_FROM`, Resend is used | Resend → **API Keys** → Create API key (Sending access) | **YES** |
| `MAIL_REPLY_TO` | Optional, Resend only: where replies go | Your support email | No |
| `VITE_SUPPORT_EMAIL` | Contact on Privacy / Terms / Delete-account pages | An email you read | No |
| `AT_USERNAME` | Africa's Talking app username (`sandbox` = test, no real texts) | africastalking.com | No |
| `AT_API_KEY` | Africa's Talking API key | Africa's Talking → Settings → API Key | **YES** |
| `AT_SENDER_ID` | (optional) Sender name, e.g. `RentaUG` | Needs approval from Africa's Talking | No |

`AT_…` are not set yet: SMS stays off until you add them (remove the `#` in `.env.netlify`, fill them in,
import them in Netlify, redeploy).

**Mobile money** needs no keys: each landlord adds their MTN / Airtel number in the app
(**Payments → Mobile money numbers**). Tenants send money from their own phone; the landlord confirms it.

---

## What runs on Netlify

| Netlify function | Job |
|---|---|
| `push-sweep` | Every minute: phone notifications, and SMS when a landlord confirms a payment |
| `health-check` | Every 20 minutes: database, sign-in, email, SMS, notifications, waiting payments, app errors |
| `signup` | Emails the 6-character sign-up code and creates the account |
| `admin` | Main admin: landlords, delete an account, delete all users (with archive), run checks now |
| `first-login`, `phone-sign-in`, `tenant-account` | First sign-in, sign-in by phone, app access for tenants |
| `password` | "Forgot password": emails the reset link (never for the permanent account, whose password is fixed) |

## If a key leaks
Make a new one straight away (Supabase, Gmail app password, Africa's Talking, or `npx web-push generate-vapid-keys`),
update it in Netlify and in `.env` / `.env.netlify`, then redeploy. The old key stops working once replaced.
