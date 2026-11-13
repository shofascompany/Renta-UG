# Database

SQL for the Renta UG Supabase database.

## Quick setup: one file

Paste **`setup_all.sql`** into Supabase **SQL Editor** and click **Run**. It deletes any existing Renta tables and data, creates everything, and creates the main admin login. Then sign in at `/admin2026`.

`setup_all.sql` is generated: after editing any numbered file, run `npm run db:bundle` to rebuild it.

## The individual files

| File | What it does |
| --- | --- |
| `00_reset.sql` | ⚠ Deletes all Renta tables, data and functions (login accounts are kept) |
| `01_profiles.sql` | User profiles (role: superadmin / landlord / tenant) |
| `02_properties.sql` | Properties, each owned by a landlord |
| `03_tenants.sql` | Tenants and their lease, linked to a landlord and a property |
| `04_payments.sql` | Monthly rent charges and their payment status |
| `05_notifications.sql` | Messages to tenants |
| `07_functions.sql` | Role checks, sign-up trigger, and the 20-minute connection codes (create / redeem) |
| `08_policies.sql` | Row level security (who can read/change what) |
| `09_realtime.sql` | Live updates for notifications, payments, tenants |
| `11_backfill_profiles.sql` | Creates profiles for accounts that signed up before the tables existed |
| `13_first_login_password.sql` | Landlords' first sign-in (set own password) |
| `14_tenant_records.sql` | Records: last house and end date of a tenancy |
| `15_tenant_stays.sql` | Separate stays per person; add former tenants back with a fresh history |
| `16_reminders_push_momo.sql` | Removes alerts; daily end-of-stay reminders; phone notifications; MTN/Airtel payments |
| `17_cash_receipts_inbox.sql` | Cash and part payments, receipts, and the landlord/admin inbox |
| `18_smart_notifications.sql` | Sign-in alerts, welcome on connecting, rent status on opening the app, overdue reminders every 5 hours |
| `19_login_email_check.sql` | Sign-in page: checks the email as it's typed (✓/✗, tenant or landlord, first-time landlord) |
| `12_main_admin.sql` | Creates or resets the main admin login. **Edit the email, password, name and phone at the top** and run it again to change them |

## Other files

| File | What it does |
| --- | --- |
| `update_existing.sql` | Applies the latest security rules and additions to an existing database. Keeps all data |
| `delete_all_landlords_and_tenants.sql` | ⚠ Deletes every landlord and tenant account and all their data. Keeps the main admin and the tables. Run by hand only |

The order matters: payments, notifications and alerts reference tenants, the policies use the functions, and the main admin needs the profiles table.
