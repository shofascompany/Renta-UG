# Renta UG: keys for GitHub + Netlify

**Never put real keys on GitHub.** GitHub only gets the code. The keys go into **Netlify → Site configuration → Environment variables**, where only Netlify can read them.

- `.env`, `.env.production` and `.env.netlify` are already in `.gitignore`, so they are never uploaded.
- `.env.netlify` (on your computer only) has every key below filled in, ready to paste into Netlify.

---

## 1. Put the code on GitHub

1. Create a **private** repository on github.com (for example `renta-ug`).
2. Upload the project folder. Before uploading, check that these files are **not** in the list: `.env`, `.env.production`, `.env.netlify`. They contain your keys.

## 2. Connect GitHub to Netlify

1. Netlify → **Add new site → Import an existing project → GitHub** → pick the repository.
2. Build settings are read from `netlify.toml` (build command `npm run build`, publish folder `dist`). Leave them as they are.

## 3. Add the keys in Netlify

Netlify → your site → **Site configuration → Environment variables → Add a variable → Import from a .env file**.
Open `.env.netlify` on your computer, copy everything, paste it in, keep **All scopes**, and save.

| Variable | What it is | Where to get it | Secret? |
|---|---|---|---|
| `VITE_SUPABASE_URL` | Your Supabase project address | Supabase → Project Settings → API | No |
| `VITE_SUPABASE_ANON_KEY` | Public key the app uses in the browser | Supabase → Project Settings → API keys → `anon` / publishable | No (protected by the database rules) |
| `SUPABASE_SERVICE_ROLE_KEY` | Full-power key for the server functions | Supabase → Project Settings → API keys → `service_role` / secret | **YES: never share** |
| `RELWORX_API_KEY` | Takes real MTN / Airtel payments | Relworx → Organizations → your organization → API keys | **YES** |
| `RELWORX_ACCOUNT_NO` | Your Relworx business account number | Relworx dashboard (starts with `REL…`) | No |
| `PAYMENTS_TEST_MODE` | Must be `false` on the live site | — | No |
| `VITE_VAPID_PUBLIC_KEY` | Phone notifications (public half) | Made once with `npx web-push generate-vapid-keys` | No |
| `VAPID_PRIVATE_KEY` | Phone notifications (private half) | Same command as above | **YES** |
| `VAPID_SUBJECT` | Contact for phone notifications | `mailto:` + an email address you control | No |
| `PAYMENT_EMAIL_FALLBACK` | Email sent to the payment provider when a tenant has none | Any company email | No |
| `CLIENT_URL` | Your live address | `https://rentaug.netlify.app` | No |

Optional, only if you ever switch from Relworx to Flutterwave: `FLW_SECRET_KEY`, `FLW_WEBHOOK_HASH`.

## 4. Deploy

Netlify → **Deploys → Trigger deploy → Deploy site**. The `VITE_…` keys are built into the app, so **redeploy every time you change one of them**.

## 5. After the first deploy

1. Supabase → **SQL Editor** → run `database/update_existing.sql` (once, and again after every app update that adds a database file).
2. Supabase → **Authentication → URL Configuration** → set Site URL to `https://rentaug.netlify.app`.
3. Relworx → webhook for **Request payment** → `https://rentaug.netlify.app/api/momo/relworx-webhook`.
4. Relworx → **API Authorized IPs**: Netlify has no fixed address. If Relworx requires one, ask them to allow your account without an IP restriction.
5. Open `https://rentaug.netlify.app/admin2026` → **Health & settings** and check that everything shows green.

## What runs on Netlify

| Netlify function | Job |
|---|---|
| `payments` | Pay rent / recharge with MTN or Airtel, check payments, Relworx webhook |
| `payments-sweep` | Every minute: confirms payments still waiting |
| `push-sweep` | Every minute: sends notifications to phones |
| `admin` | Main admin: landlords, delete accounts, delete all users (with archive) |
| `first-login`, `phone-sign-in`, `tenant-account` | Sign-in by email or phone, first sign-in, app access for tenants |

## If a key leaks

Make a new one straight away (Supabase, Relworx or `npx web-push generate-vapid-keys`), update it in Netlify and in your local `.env`, then redeploy. The old key stops working as soon as it's replaced.
