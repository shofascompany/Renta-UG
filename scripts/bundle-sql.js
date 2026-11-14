// Builds database/setup_all.sql from the numbered files so it can be run in one go.
// Usage: npm run db:bundle
import { readdirSync, readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

const dir = fileURLToPath(new URL('../database/', import.meta.url))
const SKIP = new Set()

const files = readdirSync(dir)
  .filter((f) => /^\d{2}_.+\.sql$/.test(f) && !SKIP.has(f))
  .sort()

const header = `-- ============================================================================
-- Renta UG · full database setup (GENERATED, do not edit, run \`npm run db:bundle\`)
--
-- ⚠ Starts by DELETING all existing Renta tables and data, then recreates everything.
-- Paste the whole file into Supabase → SQL Editor → Run.
-- It also creates the main admin login (12_main_admin.sql); sign in at /admin2026.
--
-- Includes: ${files.join(', ')}
-- ============================================================================
`

const body = files
  .map((f) => `\n-- ────────────── ${f} ──────────────\n\n${readFileSync(join(dir, f), 'utf8').trim()}\n`)
  .join('')

writeFileSync(join(dir, 'setup_all.sql'), header + body)
console.log(`Wrote database/setup_all.sql from ${files.length} files`)

// Non-destructive update for a database that already has the tables: re-runnable files only.
// Column additions first, then the policies (which may reference the new columns).
// Every file here must be safe to run again on a database that already has it.
const UPDATE = [
  '07_functions.sql', // helper functions + sign-up trigger (replaced in place)
  '11_backfill_profiles.sql', // profiles for any account that lacks one
  '13_first_login_password.sql',
  '14_tenant_records.sql',
  '15_tenant_stays.sql',
  '08_policies.sql', // after 14 (uses last_property_id); before 16/17, which set their own tighter access
  '09_realtime.sql',
  '16_reminders_push_momo.sql',
  '17_cash_receipts_inbox.sql',
  '18_smart_notifications.sql',
  '19_login_email_check.sql',
  '20_login_phone_check.sql',
  '21_recharge.sql',
  '22_month_start_notices.sql',
  '23_notification_delete.sql',
  '24_cash_confirmation.sql',
  '25_tenant_phone_first_login.sql',
  '26_rentals.sql',
  '27_one_house_per_tenant.sql',
  '28_cash_any_time.sql',
  '29_paid_rental_time.sql',
  '30_move_out_requests.sql',
  '31_calm_notifications.sql',
  '32_admin_console.sql',
  '33_landlord_owns_issues.sql',
  '34_archive_and_clear.sql',
]
const updateHeader = `-- ============================================================================
-- Renta UG · update an EXISTING database (GENERATED, do not edit, run \`npm run db:bundle\`)
--
-- Keeps all data. Re-applies the security policies and newer additions.
-- Paste the whole file into Supabase → SQL Editor → Run. Safe to run more than once.
--
-- Includes: ${UPDATE.join(', ')}
-- ============================================================================

-- Safety check: stop right away if this isn't the Renta database
do $$
begin
  if to_regclass('public.tenants') is null or to_regclass('public.profiles') is null then
    raise exception 'This is not the Renta UG database (no tenants table here). Open the SQL Editor of the project whose URL is in your .env file (VITE_SUPABASE_URL) and run this file there.';
  end if;
end $$;
`
const updateBody = UPDATE.map(
  (f) => `\n-- ────────────── ${f} ──────────────\n\n${readFileSync(join(dir, f), 'utf8').trim()}\n`,
).join('')
writeFileSync(join(dir, 'update_existing.sql'), updateHeader + updateBody)
console.log(`Wrote database/update_existing.sql from ${UPDATE.length} files`)
