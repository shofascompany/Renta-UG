# Renta UG

Rental management platform with three kinds of account:

| Account | Signs in at | Can |
| --- | --- | --- |
| **Main admin** (one, set in `.env`) | `/admin2026` | Register, edit and suspend landlords; monitor every landlord's properties, tenants and payments (read-only) |
| **Landlord** (registered by the main admin) | `/login` | Manage their own properties and tenants, bill rent, record payments, send notifications |
| **Tenant** (signs up themselves) | `/login` | Connect to their landlord with a code, see their dashboard, get notifications on their phone, pay rent with MTN or Airtel |

Landlords and tenants use the same login page; the app sends each to their own area based on the account type.

Stack: Vue 3, Vite, Vue Router, Pinia, Tailwind CSS v4, Lucide icons, **Supabase** (auth + Postgres + realtime), and a small Express server for **mobile money** (Flutterwave) and **phone notifications** (Web Push).

## Setup

### 1. Supabase

1. Create a project at https://supabase.com.
2. In the **SQL Editor**, paste and run [`database/setup_all.sql`](database/setup_all.sql) (see [database/README.md](database/README.md)).
3. From **Project Settings → API**, copy the Project URL, the `anon` key, and the `service_role` key.
4. Optional for local testing: under **Authentication → Sign In / Providers → Email**, turn off "Confirm email" so sign-ups work without an email link.

### 2. Environment

Copy `.env.example` to `.env` and fill in the Supabase keys, the phone-notification (VAPID) keys and, for real payments, the Flutterwave keys.

### 3. Run

```bash
npm install
npm run dev      # app  → http://localhost:5173
npm run server   # API  → http://localhost:4242 (needed to register landlords, mobile money and phone notifications)
```

### 4. The main admin account

The main admin login is created by the database setup itself ([`database/12_main_admin.sql`](database/12_main_admin.sql), included in `setup_all.sql`). To change the main admin's email, password, name or phone, edit the values at the top of that file and run it again in the Supabase SQL Editor.

## How it works

1. The main admin signs in at **`/admin2026`** and registers each landlord (name, email, phone, password) under **Landlords**. The landlord can then sign in at `/login`.
2. A landlord adds **properties**, then **tenants** (name, property, lease dates; email optional).
3. Saving a tenant shows a **6-character connection code, valid for 20 minutes**. The landlord shares it; a new one can be made any time from **Tenants → Get code**.
4. The tenant **creates their own account** at `/signup`, is taken to **Connect to your landlord**, enters the code, and is connected to that landlord's rental automatically.
5. Each month the landlord clicks **Payments → Create rent charges**. Their current tenants are billed and notified.
6. Tenants pay with MTN or Airtel mobile money (verified automatically), or the landlord records cash or bank payments.
7. Notifications, payments and tenant connections update live via Supabase Realtime.

**Security (row level security):** landlords only ever see their own properties, tenants and payments. Tenants only see their own records, may only mark notifications read, and can never mark rent as paid. The main admin can read everything but can't change landlords' data. Suspended landlords can't sign in.

## Mobile money (MTN / Airtel)

Tenants pay rent with **MTN MoMo** or **Airtel Money** through **Flutterwave**. The server sends the payment prompt to the tenant's phone, then confirms it with Flutterwave (by polling every 15 s and via webhook). Only then does it mark the rent paid and send a "Payment received" notification.

- **Test mode** (no `FLW_SECRET_KEY`): no real money moves; payments approve themselves after ~8 seconds.
- **Real payments:** create a Flutterwave business account, then set `FLW_SECRET_KEY` and `FLW_WEBHOOK_HASH` in `.env`. Point the webhook at `https://<your-server>/api/momo/webhook`. Money is collected into the Flutterwave account and settled to the company's bank or mobile money account (set in Flutterwave → Settlements).

## Notifications

- **End-of-stay reminders:** a database job (`pg_cron`) runs every day at 09:00 Kampala time. During the last 7 days of a lease it sends the tenant one reminder per day ("3 days left in your stay…").
- **Phone notifications:** every notification (messages, reminders, payment receipts) is also sent to the phone's notification panel via Web Push. Tenants tap **Turn on** in the app. On iPhone they must first add the app to the Home Screen.
- Phone notifications need the API server running and the app served over **HTTPS** (localhost is fine on the same computer).

## Project structure

```
database/                  SQL: one file per table, then functions, RLS policies, realtime
server/index.js            Express API: mobile money, landlord accounts, first sign-in
server/momo.js             MTN / Airtel via Flutterwave (or test mode)
server/push.js             Sends notifications to phones (Web Push)
public/sw.js               Service worker: shows notifications on the phone
src/
  lib/supabase.js          Supabase client
  lib/api.js               Authenticated calls to the Express API
  stores/auth.js           Supabase auth + profile (role)
  stores/rental.js         Loads/mutates all data in Supabase
  router/index.js          Routes + role guards
  layouts/AppShell.vue     Sidebar layout shared by both roles
  components/              Shared UI
  views/tenant/            Dashboard, My home, Payments, Notifications
  views/landlord/          Overview, Properties (+ detail), Tenants, Records, Payments, Notifications
  views/super/             Main admin: Overview, Landlords, All tenants
```
