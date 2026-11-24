-- ============================================================================
-- Renta UG · update an EXISTING database (GENERATED, do not edit, run `npm run db:bundle`)
--
-- Keeps all data. Re-applies the security policies and newer additions.
-- Paste the whole file into Supabase → SQL Editor → Run. Safe to run more than once.
--
-- Includes: 07_functions.sql, 11_backfill_profiles.sql, 13_first_login_password.sql, 14_tenant_records.sql, 15_tenant_stays.sql, 08_policies.sql, 09_realtime.sql, 16_reminders_push_momo.sql, 17_cash_receipts_inbox.sql, 18_smart_notifications.sql, 19_login_email_check.sql, 20_login_phone_check.sql, 21_recharge.sql, 22_month_start_notices.sql, 23_notification_delete.sql, 24_cash_confirmation.sql, 25_tenant_phone_first_login.sql, 26_rentals.sql, 27_one_house_per_tenant.sql, 28_cash_any_time.sql, 29_paid_rental_time.sql, 30_move_out_requests.sql, 31_calm_notifications.sql, 32_admin_console.sql, 33_landlord_owns_issues.sql, 34_archive_and_clear.sql, 35_consistency.sql, 36_part_payments.sql, 37_email_verification.sql, 39_sms_confirmations.sql, 40_app_installs.sql, 41_manual_mobile_money.sql, 42_tenant_own_details.sql, 43_heard_from.sql, 44_security_hardening.sql, 45_landlord_subscriptions.sql, 46_subscription_tiers.sql, 47_no_free_trial.sql, 48_no_reason_codes.sql, 49_protected_account.sql, 50_permanent_account.sql, 51_capacity_and_cash_subscriptions.sql, 52_part_payment_days.sql, 53_subscription_30_day_months.sql, 54_browser_write_limits.sql
-- ============================================================================

-- Safety check: stop right away if this isn't the Renta database
do $$
begin
  if to_regclass('public.tenants') is null or to_regclass('public.profiles') is null then
    raise exception 'This is not the Renta UG database (no tenants table here). Open the SQL Editor of the project whose URL is in your .env file (VITE_SUPABASE_URL) and run this file there.';
  end if;
end $$;

-- ────────────── 07_functions.sql ──────────────

-- 07 · helper functions and triggers
-- Requires tables 01–05. Safe to run again (replaces the functions, recreates the trigger).

-- Current user's role checks (security definer so RLS policies don't recurse)
create or replace function public.is_superadmin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'superadmin');
$$;

create or replace function public.is_landlord() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'landlord' and active);
$$;

-- The tenant record belonging to the current user, if any.
create or replace function public.my_tenant_id() returns uuid
language sql stable security definer set search_path = '' as $$
  select id from public.tenants where user_id = auth.uid();
$$;

-- New sign-up → create a profile. Everyone starts as a tenant; landlords are promoted
-- by the server when the main admin registers them, the main admin by 12_main_admin.sql.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Landlord: create a fresh 6-character connection code for one of their tenants, valid 20 minutes.
-- Returns {"code": "...", "expires_at": "..."}.
create or replace function public.new_connect_code(p_tenant_id uuid) returns json
language plpgsql volatile security definer set search_path = '' as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- no 0/O/1/I
  c text;
  expires timestamptz := now() + interval '20 minutes';
begin
  if not public.is_landlord() then
    raise exception 'Only landlords can create connection codes.';
  end if;

  loop
    c := '';
    for i in 1..6 loop
      c := c || substr(alphabet, 1 + get_byte(extensions.gen_random_bytes(1), 0) % 32, 1);
    end loop;
    exit when not exists (select 1 from public.tenants where connect_code = c);
  end loop;

  update public.tenants
  set connect_code = c, connect_code_expires_at = expires
  where id = p_tenant_id and landlord_id = auth.uid() and user_id is null;

  if not found then
    raise exception 'Tenant not found, or already connected to an account.';
  end if;

  return json_build_object('code', c, 'expires_at', expires);
end $$;

-- Tenant: enter a code to connect your account to the landlord who issued it.
create or replace function public.redeem_connect_code(p_code text) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  t_id uuid;
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Please sign in first.';
  end if;
  if not exists (select 1 from public.profiles where id = me and role = 'tenant') then
    raise exception 'Only tenant accounts can use a connection code.';
  end if;
  if exists (select 1 from public.tenants where user_id = me and property_id is not null) then
    raise exception 'Your account is already connected to a rental.';
  end if;

  select id into t_id
  from public.tenants
  where connect_code = upper(trim(p_code))
    and connect_code_expires_at > now()
    and user_id is null
  for update;

  if t_id is null then
    raise exception 'This code is invalid or has expired. Ask your landlord for a new one.';
  end if;

  -- Detach any former-tenant record so user_id stays unique
  update public.tenants set user_id = null where user_id = me;

  update public.tenants
  set user_id = me,
      email = coalesce(email, (select email from auth.users where id = me)),
      connect_code = null,
      connect_code_expires_at = null
  where id = t_id;

  return t_id;
end $$;

revoke execute on function public.new_connect_code(uuid) from public, anon;
revoke execute on function public.redeem_connect_code(text) from public, anon;
grant execute on function public.new_connect_code(uuid) to authenticated;
grant execute on function public.redeem_connect_code(text) to authenticated;

-- ────────────── 11_backfill_profiles.sql ──────────────

-- 11 · backfill profiles
-- Gives a profile to any login account that existed before the tables were (re)created,
-- so people who already signed up can still sign in. Safe to run any time.

insert into public.profiles (id, email, full_name)
select u.id, u.email, coalesce(u.raw_user_meta_data ->> 'full_name', split_part(u.email, '@', 1))
from auth.users u
on conflict (id) do nothing;

-- ────────────── 13_first_login_password.sql ──────────────

-- 13 · first-login password
-- Landlords get a temporary password from the main admin. On their first sign-in they must
-- choose their own password; after that they go straight to their dashboard.
-- Safe to run on its own on an existing database (no data is deleted).

alter table public.profiles
  add column if not exists must_change_password boolean not null default false;

-- Called by the app right after the user has set their new password.
create or replace function public.complete_password_setup() returns void
language sql volatile security definer set search_path = '' as $$
  update public.profiles set must_change_password = false where id = auth.uid();
$$;

revoke execute on function public.complete_password_setup() from public, anon;
grant execute on function public.complete_password_setup() to authenticated;

-- ────────────── 14_tenant_records.sql ──────────────

-- 14 · tenant records
-- When a landlord ends a tenancy, the tenant moves to "Records": property_id becomes null,
-- and we remember which house they were in and when they left. All their payments,
-- notifications and alerts are kept. They can be added back later with history intact.
-- Safe to run on its own on an existing database (no data is deleted).

alter table public.tenants
  add column if not exists last_property_id uuid references public.properties (id) on delete set null,
  add column if not exists ended_at timestamptz;

-- Existing former tenants: work out their last house from their latest rent charge.
update public.tenants t
set last_property_id = (
  select p.property_id from public.payments p
  where p.tenant_id = t.id and p.property_id is not null
  order by p.period desc
  limit 1
)
where t.property_id is null and t.last_property_id is null;

-- ────────────── 15_tenant_stays.sql ──────────────

-- 15 · tenant stays
-- Each row in `tenants` is one STAY: one person in one house for one period, with its own
-- payments, notifications and alerts. When a landlord adds a former tenant back, a NEW stay
-- is created (fresh history) and linked to the same person via `person_id`. Old stays stay in
-- Records, separated per house and period.
-- Safe to run on its own on an existing database (no data is deleted).

alter table public.tenants add column if not exists person_id uuid;
update public.tenants set person_id = id where person_id is null;
alter table public.tenants alter column person_id set not null;
create index if not exists tenants_person_id_idx on public.tenants (person_id);

-- A new person's first stay: person_id = its own id
create or replace function public.set_tenant_person_id() returns trigger
language plpgsql as $$
begin
  new.person_id := coalesce(new.person_id, new.id);
  return new;
end $$;

drop trigger if exists tenants_person_id on public.tenants;
create trigger tenants_person_id
  before insert on public.tenants
  for each row execute function public.set_tenant_person_id();

-- The same email may now appear on several (past) stays; only CURRENT tenants must be unique.
drop index if exists public.tenants_landlord_email_key;
create unique index if not exists tenants_current_email_key
  on public.tenants (landlord_id, lower(email))
  where property_id is not null;

-- Landlord: add a former tenant back into a house as a NEW stay.
-- Their app account (if any) moves to the new stay, so their dashboard starts fresh.
create or replace function public.readd_tenant(
  p_former_id uuid,
  p_property_id uuid,
  p_full_name text,
  p_email text,
  p_phone text,
  p_lease_start date,
  p_lease_end date
) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_person uuid;
  v_email text;
  v_user uuid;
  v_new uuid;
begin
  if not public.is_landlord() then
    raise exception 'Only landlords can add tenants.';
  end if;

  select person_id, email into v_person, v_email
  from public.tenants
  where id = p_former_id and landlord_id = auth.uid();
  if v_person is null then
    raise exception 'Former tenant not found.';
  end if;

  if exists (select 1 from public.tenants where person_id = v_person and property_id is not null) then
    raise exception 'This tenant is already renting one of your houses.';
  end if;
  if not public.owns_property(p_property_id) then
    raise exception 'House not found.';
  end if;
  if exists (select 1 from public.tenants where property_id = p_property_id) then
    raise exception 'That house already has a tenant.';
  end if;

  -- Move the app account link from the old stay(s) to the new one
  select user_id into v_user from public.tenants where person_id = v_person and user_id is not null limit 1;
  update public.tenants set user_id = null where person_id = v_person and user_id is not null;

  insert into public.tenants (landlord_id, person_id, user_id, property_id, full_name, email, phone, lease_start, lease_end)
  values (
    auth.uid(), v_person, v_user, p_property_id,
    p_full_name, coalesce(nullif(lower(trim(p_email)), ''), v_email), nullif(trim(p_phone), ''),
    p_lease_start, p_lease_end
  )
  returning id into v_new;

  return v_new;
end $$;

revoke execute on function public.readd_tenant(uuid, uuid, text, text, text, date, date) from public, anon;
grant execute on function public.readd_tenant(uuid, uuid, text, text, text, date, date) to authenticated;

-- ────────────── 08_policies.sql ──────────────

-- 08 · row level security
--   superadmin → can READ everything (monitoring); landlords are created via the server
--   landlord   → full control of rows where landlord_id = their id
--   tenant     → reads their own records; may only mark notifications as read
-- Payments are marked paid by the server (service role), never by tenants.
--
-- Safe to run again on an existing database (drops and recreates the policies, keeps data).
-- Requires 07_functions.sql.

-- ── Helper lookups ──
-- Policies must not query another table whose own policies query back (tenants ↔ properties,
-- profiles → tenants), or Postgres reports "infinite recursion detected in policy".
-- These security definer functions read the tables directly, bypassing RLS, so there's no loop.

create or replace function public.my_property_id() returns uuid
language sql stable security definer set search_path = '' as $$
  select property_id from public.tenants where user_id = auth.uid();
$$;

create or replace function public.my_landlord_id() returns uuid
language sql stable security definer set search_path = '' as $$
  select landlord_id from public.tenants where user_id = auth.uid();
$$;

create or replace function public.owns_property(p_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.properties where id = p_id and landlord_id = auth.uid());
$$;

create or replace function public.owns_tenant(t_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.tenants where id = t_id and landlord_id = auth.uid());
$$;

-- ── Table access ──
-- Newer Supabase projects don't grant this automatically. The policies below still restrict
-- which rows each user can touch.
grant usage on schema public to anon, authenticated, service_role;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant all on all tables in schema public to service_role;
grant execute on function
  public.is_superadmin(), public.is_landlord(), public.my_tenant_id(),
  public.my_property_id(), public.my_landlord_id(), public.owns_property(uuid), public.owns_tenant(uuid)
to authenticated;

alter table public.profiles enable row level security;
alter table public.properties enable row level security;
alter table public.tenants enable row level security;
alter table public.payments enable row level security;
alter table public.notifications enable row level security;

-- ── profiles ──
drop policy if exists "profiles read" on public.profiles;
drop policy if exists "profiles update own" on public.profiles;

create policy "profiles read" on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_superadmin() or id = public.my_landlord_id()); -- tenant sees their landlord's contact
create policy "profiles update own" on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
revoke insert, update, delete on public.profiles from anon, authenticated;
grant update (full_name, phone) on public.profiles to authenticated; -- users can't change their own role

-- ── properties ──
drop policy if exists "properties landlord" on public.properties;
drop policy if exists "properties superadmin read" on public.properties;
drop policy if exists "properties tenant read" on public.properties;

create policy "properties landlord" on public.properties for all to authenticated
  using (public.is_landlord() and landlord_id = auth.uid())
  with check (public.is_landlord() and landlord_id = auth.uid());
create policy "properties superadmin read" on public.properties for select to authenticated
  using (public.is_superadmin());
create policy "properties tenant read" on public.properties for select to authenticated
  using (id = public.my_property_id());

-- ── tenants ──
drop policy if exists "tenants landlord" on public.tenants;
drop policy if exists "tenants superadmin read" on public.tenants;
drop policy if exists "tenants read own" on public.tenants;

create policy "tenants landlord" on public.tenants for all to authenticated
  using (public.is_landlord() and landlord_id = auth.uid())
  with check (
    public.is_landlord() and landlord_id = auth.uid()
    and (property_id is null or public.owns_property(property_id))
    and (last_property_id is null or public.owns_property(last_property_id))
  );
create policy "tenants superadmin read" on public.tenants for select to authenticated
  using (public.is_superadmin());
create policy "tenants read own" on public.tenants for select to authenticated
  using (user_id = auth.uid());

-- ── payments ──
drop policy if exists "payments landlord" on public.payments;
drop policy if exists "payments superadmin read" on public.payments;
drop policy if exists "payments read own" on public.payments;

create policy "payments landlord" on public.payments for all to authenticated
  using (public.is_landlord() and landlord_id = auth.uid())
  with check (public.is_landlord() and landlord_id = auth.uid() and public.owns_tenant(tenant_id));
create policy "payments superadmin read" on public.payments for select to authenticated
  using (public.is_superadmin());
create policy "payments read own" on public.payments for select to authenticated
  using (tenant_id = public.my_tenant_id());

-- ── notifications (tenants may only flip `read`) ──
drop policy if exists "notifications landlord" on public.notifications;
drop policy if exists "notifications superadmin read" on public.notifications;
drop policy if exists "notifications read own" on public.notifications;
drop policy if exists "notifications mark read" on public.notifications;

create policy "notifications landlord" on public.notifications for all to authenticated
  using (public.is_landlord() and landlord_id = auth.uid())
  with check (public.is_landlord() and landlord_id = auth.uid() and public.owns_tenant(tenant_id));
create policy "notifications superadmin read" on public.notifications for select to authenticated
  using (public.is_superadmin());
create policy "notifications read own" on public.notifications for select to authenticated
  using (tenant_id = public.my_tenant_id());
create policy "notifications mark read" on public.notifications for update to authenticated
  using (tenant_id = public.my_tenant_id() or (public.is_landlord() and landlord_id = auth.uid()))
  with check (tenant_id = public.my_tenant_id() or (public.is_landlord() and landlord_id = auth.uid()));
revoke update on public.notifications from anon, authenticated;
grant update (read) on public.notifications to authenticated;

-- ────────────── 09_realtime.sql ──────────────

-- 09 · realtime
-- Lets the app receive live updates: notifications, payments, and tenants
-- (so the landlord sees the moment a tenant connects with their code).
-- Safe to run again (skips tables that are already added).

do $$
declare
  t text;
begin
  foreach t in array array['notifications', 'payments', 'tenants'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then
      null; -- already added
    end;
  end loop;
end $$;

-- ────────────── 16_reminders_push_momo.sql ──────────────

-- 16 · reminders, phone notifications and mobile money
--   • removes the old "alerts" feature (the app now uses notifications only)
--   • automatic end-of-stay reminders: every day in the last 7 days of a lease (pg_cron)
--   • push subscriptions: which phones get notifications in their notification panel
--   • mobile money attempts: MTN / Airtel payments, verified automatically by the server
-- Safe to run more than once. ⚠ Deletes the alerts table and its data.

-- ── Remove alerts ──
drop table if exists public.alerts cascade;

-- ── Notifications: reminder type, de-duplication, push tracking ──
alter table public.notifications drop constraint if exists notifications_type_check;
-- Full list (incl. the types added in 18), so re-running this on a newer database doesn't fail
alter table public.notifications
  add constraint notifications_type_check
  check (type in ('general', 'maintenance', 'payment', 'reminder', 'security', 'welcome', 'status', 'rent_due'));
alter table public.notifications add column if not exists dedupe_key text;
alter table public.notifications add column if not exists pushed_at timestamptz;
create unique index if not exists notifications_dedupe_key on public.notifications (dedupe_key);
-- Don't push old notifications when phone notifications are first switched on
update public.notifications set pushed_at = coalesce(pushed_at, created_at) where pushed_at is null and created_at < now() - interval '10 minutes';

-- ── End-of-stay reminders ──
-- One notification per tenant per day while 0–7 days remain on the lease (Uganda time).
create or replace function public.send_lease_reminders() returns integer
language plpgsql volatile security definer set search_path = '' as $$
declare
  today date := (now() at time zone 'Africa/Kampala')::date;
  n integer;
begin
  insert into public.notifications (landlord_id, tenant_id, type, title, body, dedupe_key)
  select
    t.landlord_id,
    t.id,
    'reminder',
    'Tenancy reminder', -- sender line; the notification title is always "Renta UG"
    case
      when d.days_left = 0 then format(
        'Your current rental period for %s ends today. Please settle any outstanding rent and confirm your plans with your landlord.', p.name)
      when d.days_left = 1 then format(
        'Your current rental period for %s ends tomorrow, %s. Please arrange your next payment or inform your landlord of your plans.',
        p.name, to_char(t.lease_end, 'FMDD Mon YYYY'))
      else format(
        'Your current rental period for %s ends in %s days, on %s. Please arrange your next payment or inform your landlord of your plans.',
        p.name, d.days_left, to_char(t.lease_end, 'FMDD Mon YYYY'))
    end,
    format('lease_end:%s:%s', t.id, today)
  from public.tenants t
  join public.properties p on p.id = t.property_id
  cross join lateral (select (t.lease_end - today) as days_left) d
  where t.property_id is not null
    and t.lease_end is not null
    and d.days_left between 0 and 7
  on conflict (dedupe_key) do nothing;

  get diagnostics n = row_count;
  return n;
end $$;

revoke execute on function public.send_lease_reminders() from public, anon, authenticated;

-- Run every day at 06:00 UTC = 09:00 in Kampala
create extension if not exists pg_cron;
select cron.schedule('renta-lease-reminders', '0 6 * * *', 'select public.send_lease_reminders()');
-- …and once now, so anyone already in their last week is reminded today
select public.send_lease_reminders();

-- ── Phones registered for notifications ──
create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  created_at timestamptz not null default now()
);
create index if not exists push_subscriptions_user_id_idx on public.push_subscriptions (user_id);
alter table public.push_subscriptions enable row level security;

drop policy if exists "push read own" on public.push_subscriptions;
create policy "push read own" on public.push_subscriptions for select to authenticated using (user_id = auth.uid());

-- Save / remove this device for the signed-in user (a phone may change hands between accounts)
create or replace function public.save_push_subscription(p_endpoint text, p_p256dh text, p_auth text) returns void
language sql volatile security definer set search_path = '' as $$
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth)
  values (auth.uid(), p_endpoint, p_p256dh, p_auth)
  on conflict (endpoint) do update set user_id = auth.uid(), p256dh = excluded.p256dh, auth = excluded.auth;
$$;

create or replace function public.delete_push_subscription(p_endpoint text) returns void
language sql volatile security definer set search_path = '' as $$
  delete from public.push_subscriptions where endpoint = p_endpoint and user_id = auth.uid();
$$;

revoke execute on function public.save_push_subscription(text, text, text) from public, anon;
revoke execute on function public.delete_push_subscription(text) from public, anon;
grant execute on function public.save_push_subscription(text, text, text) to authenticated;
grant execute on function public.delete_push_subscription(text) to authenticated;

-- ── Mobile money payment attempts (written only by the server) ──
create table if not exists public.momo_attempts (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.payments (id) on delete cascade,
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  landlord_id uuid not null references auth.users (id) on delete cascade,
  network text not null check (network in ('MTN', 'AIRTEL')),
  phone text not null,
  amount bigint not null,
  tx_ref text not null unique,
  provider text not null,              -- 'flutterwave' or 'test'
  provider_ref text,
  status text not null default 'pending' check (status in ('pending', 'successful', 'failed')),
  failure_reason text,
  redirect_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists momo_attempts_payment_id_idx on public.momo_attempts (payment_id);
create index if not exists momo_attempts_pending_idx on public.momo_attempts (status) where status = 'pending';
alter table public.momo_attempts enable row level security;

-- Table access: read only for signed-in users (writes go through the functions / the server)
revoke all on public.push_subscriptions, public.momo_attempts from anon, authenticated;
grant select on public.push_subscriptions, public.momo_attempts to authenticated;
grant all on public.push_subscriptions, public.momo_attempts to service_role;

drop policy if exists "momo tenant read" on public.momo_attempts;
drop policy if exists "momo landlord read" on public.momo_attempts;
create policy "momo tenant read" on public.momo_attempts for select to authenticated using (tenant_id = public.my_tenant_id());
create policy "momo landlord read" on public.momo_attempts for select to authenticated
  using (public.is_landlord() and landlord_id = auth.uid());

-- ────────────── 17_cash_receipts_inbox.sql ──────────────

-- 17 · cash payments, receipts and staff inbox
--   • payments can be paid in parts: amount_paid tracks how much of each rent charge is paid
--   • payment_receipts: every amount received (cash or mobile money), kept for the records
--   • record_cash_payment(): landlord records cash; it's applied to the oldest unpaid rent first.
--     The tenant gets a confirmation only when a month's rent is fully paid
--   • staff_notifications: inbox for landlords and the main admin (e.g. "payment received")
-- Safe to run more than once. No data is deleted.

-- ── Part payments ──
alter table public.payments add column if not exists amount_paid bigint not null default 0;
update public.payments set amount_paid = amount where status = 'paid' and amount_paid = 0;

-- ── Receipts ──
create table if not exists public.payment_receipts (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.payments (id) on delete cascade,
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  landlord_id uuid not null references auth.users (id) on delete cascade,
  amount bigint not null check (amount > 0),
  method text not null,             -- Cash, MTN Mobile Money, Airtel Money, Bank transfer
  reference text,
  note text,
  received_at timestamptz not null default now(),
  recorded_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists payment_receipts_payment_id_idx on public.payment_receipts (payment_id);
create index if not exists payment_receipts_landlord_id_idx on public.payment_receipts (landlord_id);
alter table public.payment_receipts enable row level security;

drop policy if exists "receipts landlord read" on public.payment_receipts;
drop policy if exists "receipts tenant read" on public.payment_receipts;
drop policy if exists "receipts superadmin read" on public.payment_receipts;
create policy "receipts landlord read" on public.payment_receipts for select to authenticated
  using (public.is_landlord() and landlord_id = auth.uid());
create policy "receipts tenant read" on public.payment_receipts for select to authenticated
  using (tenant_id = public.my_tenant_id());
create policy "receipts superadmin read" on public.payment_receipts for select to authenticated
  using (public.is_superadmin());

-- ── Staff inbox (landlords + main admin) ──
create table if not exists public.staff_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  type text not null default 'payment',
  title text not null,
  body text not null,
  url text,
  read boolean not null default false,
  pushed_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists staff_notifications_user_id_idx on public.staff_notifications (user_id);
alter table public.staff_notifications enable row level security;

drop policy if exists "staff inbox read own" on public.staff_notifications;
drop policy if exists "staff inbox mark read" on public.staff_notifications;
create policy "staff inbox read own" on public.staff_notifications for select to authenticated using (user_id = auth.uid());
create policy "staff inbox mark read" on public.staff_notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Table access: read only for signed-in users (writes go through the functions / the server)
revoke all on public.payment_receipts, public.staff_notifications from anon, authenticated;
grant select on public.payment_receipts, public.staff_notifications to authenticated;
grant update (read) on public.staff_notifications to authenticated;
grant all on public.payment_receipts, public.staff_notifications to service_role;

do $$ begin
  alter publication supabase_realtime add table public.staff_notifications;
exception when duplicate_object then null; end $$;

-- ── Record a cash payment ──
-- Applies the amount to the tenant's unpaid rent, oldest first. Returns what happened.
create or replace function public.record_cash_payment(
  p_tenant_id uuid,
  p_amount bigint,
  p_received_at timestamptz default now(),
  p_note text default null
) returns json
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_landlord uuid := auth.uid();
  v_outstanding bigint;
  v_left bigint := p_amount;
  v_take bigint;
  v_completed text[] := '{}';
  v_parts json[] := '{}';
  v_balance_after bigint;
  v_house text;
  c record;
begin
  if not public.is_landlord() then
    raise exception 'Only landlords can record payments.';
  end if;
  if not exists (select 1 from public.tenants where id = p_tenant_id and landlord_id = v_landlord) then
    raise exception 'Tenant not found.';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Enter an amount greater than zero.';
  end if;

  select coalesce(sum(amount - amount_paid), 0) into v_outstanding
  from public.payments where tenant_id = p_tenant_id and status = 'pending';

  if v_outstanding = 0 then
    raise exception 'This tenant has no unpaid rent. Create a rent charge first.';
  end if;
  if p_amount > v_outstanding then
    raise exception 'That is more than the balance of UGX %.', to_char(v_outstanding, 'FM999,999,999,999');
  end if;

  for c in
    select * from public.payments
    where tenant_id = p_tenant_id and status = 'pending'
    order by due_date, period
    for update
  loop
    exit when v_left <= 0;
    v_take := least(v_left, c.amount - c.amount_paid);
    v_left := v_left - v_take;

    insert into public.payment_receipts (payment_id, tenant_id, landlord_id, amount, method, note, received_at, recorded_by)
    values (c.id, p_tenant_id, v_landlord, v_take, 'Cash', nullif(trim(p_note), ''), coalesce(p_received_at, now()), v_landlord);

    update public.payments
    set amount_paid = amount_paid + v_take,
        status = case when amount_paid + v_take >= amount then 'paid' else 'pending' end,
        paid_at = case when amount_paid + v_take >= amount then coalesce(p_received_at, now()) else paid_at end,
        method = 'Cash'
    where id = c.id;

    if c.amount_paid + v_take >= c.amount then
      v_completed := v_completed || to_char(to_date(c.period || '-01', 'YYYY-MM-DD'), 'FMMonth YYYY');
    end if;
    v_parts := v_parts || json_build_object('period', c.period, 'applied', v_take, 'paid_in_full', c.amount_paid + v_take >= c.amount);
  end loop;

  select coalesce(sum(amount - amount_paid), 0) into v_balance_after
  from public.payments where tenant_id = p_tenant_id and status = 'pending';

  -- Confirmation only for rent that is now fully paid
  if array_length(v_completed, 1) > 0 then
    select p.name into v_house from public.tenants t left join public.properties p on p.id = t.property_id where t.id = p_tenant_id;
    insert into public.notifications (landlord_id, tenant_id, type, title, body)
    values (
      v_landlord, p_tenant_id, 'payment',
      'Payment confirmation', -- sender line; the notification title is always "Renta UG"
      format('Your cash payment for %s%s has been received and recorded. Rent for this period is paid in full. %s',
        array_to_string(v_completed, ', '),
        coalesce(' at ' || v_house, ''),
        case when v_balance_after = 0 then 'You have no outstanding balance. Thank you.'
             else format('Outstanding balance: UGX %s.', to_char(v_balance_after, 'FM999,999,999,999')) end)
    );
  end if;

  return json_build_object('applied', p_amount, 'balance_after', v_balance_after, 'parts', array_to_json(v_parts));
end $$;

revoke execute on function public.record_cash_payment(uuid, bigint, timestamptz, text) from public, anon;
grant execute on function public.record_cash_payment(uuid, bigint, timestamptz, text) to authenticated;

-- ────────────── 18_smart_notifications.sql ──────────────

-- 18 · smart notifications
--   • new types: security (sign-in alerts), welcome (connected to landlord), status (rent check), rent_due (overdue reminder)
--   • sign-in alert: device and time, for tenants, landlords and the main admin
--   • welcome: when a tenant connects to their landlord (+ a note in the landlord's inbox)
--   • rent status: on sign-in and the first time the app is opened each day
--   • overdue reminders: every 5 hours (07:00–22:00 Kampala) while rent is overdue or the paid period has ended
--   • landlords can't see their tenants' sign-in alerts
-- Every notification's TITLE is shown as "Renta UG"; the `title` column holds the sender line
-- (e.g. "Rent reminder", "Account security"), followed by the message in `body`.
-- Safe to run more than once. No data is deleted.

-- ── Types ──
alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in ('general', 'maintenance', 'payment', 'reminder', 'security', 'welcome', 'status', 'rent_due'));

create index if not exists notifications_tenant_type_created_idx on public.notifications (tenant_id, type, created_at desc);

-- ── Landlords: everything for their tenants EXCEPT the tenant's private sign-in alerts ──
drop policy if exists "notifications landlord" on public.notifications;
create policy "notifications landlord" on public.notifications for all to authenticated
  using (public.is_landlord() and landlord_id = auth.uid() and type <> 'security')
  with check (public.is_landlord() and landlord_id = auth.uid() and public.owns_tenant(tenant_id));

-- ── Helpers ──
create or replace function public.ugx(p_amount bigint) returns text
language sql immutable set search_path = '' as $$
  select 'UGX ' || to_char(coalesce(p_amount, 0), 'FM999,999,999,999');
$$;

create or replace function public.kampala_today() returns date
language sql stable set search_path = '' as $$
  select (now() at time zone 'Africa/Kampala')::date;
$$;

create or replace function public.days_text(p_days integer) returns text
language sql immutable set search_path = '' as $$
  select case when p_days = 1 then '1 day' else p_days || ' days' end;
$$;

-- ── Rent status for one tenant (internal) ──
-- p_force = true  → always send (sign-in)
-- p_force = false → at most once per day (opening the app)
create or replace function public.send_rent_status(p_tenant_id uuid, p_force boolean) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  t record;
  today date := public.kampala_today();
  v_key text := format('status:%s:%s', p_tenant_id, public.kampala_today());
  v_owed bigint;
  v_overdue bigint;
  v_oldest_overdue date;
  v_next_due date;
  v_next_amount bigint;
  v_days_left integer;
  v_body text;
begin
  select tn.*, p.name as house into t
  from public.tenants tn join public.properties p on p.id = tn.property_id
  where tn.id = p_tenant_id and tn.property_id is not null;
  if not found then return; end if;

  if not p_force and exists (select 1 from public.notifications where dedupe_key = v_key) then
    return;
  end if;

  select coalesce(sum(amount - amount_paid), 0),
         coalesce(sum(amount - amount_paid) filter (where due_date < today), 0),
         min(due_date) filter (where due_date < today)
    into v_owed, v_overdue, v_oldest_overdue
  from public.payments where tenant_id = t.id and status = 'pending';

  select due_date, amount - amount_paid into v_next_due, v_next_amount
  from public.payments where tenant_id = t.id and status = 'pending' and due_date >= today
  order by due_date limit 1;

  v_days_left := case when t.lease_end is not null then t.lease_end - today end;

  if v_overdue > 0 then
    v_body := format('Your rent of %s for %s was due on %s and is now %s overdue. Please make payment through the Payments page at your earliest convenience.',
      public.ugx(v_overdue), t.house, to_char(v_oldest_overdue, 'FMDD Mon YYYY'), public.days_text(today - v_oldest_overdue));
  elsif v_days_left is not null and v_days_left < 0 then
    v_body := format('Your paid rental period for %s ended on %s. Please make a payment to renew your tenancy, or contact your landlord to discuss your plans.',
      t.house, to_char(t.lease_end, 'FMDD Mon YYYY'));
  elsif v_next_due = today then
    v_body := format('Your rent of %s for %s is due today. You can pay securely via MTN Mobile Money or Airtel Money on the Payments page.',
      public.ugx(v_next_amount), t.house);
  elsif v_next_due is not null and v_next_due - today <= 7 then
    v_body := format('Your rent of %s for %s is due on %s (in %s). You can pay securely via MTN Mobile Money or Airtel Money on the Payments page.',
      public.ugx(v_next_amount), t.house, to_char(v_next_due, 'FMDay, FMDD Mon'), public.days_text(v_next_due - today));
  elsif v_days_left is not null and v_days_left <= 7 then
    v_body := format('Your current rental period for %s ends %s. Please arrange your next payment or inform your landlord of your plans.',
      t.house,
      case when v_days_left = 0 then 'today'
           when v_days_left = 1 then 'tomorrow, ' || to_char(t.lease_end, 'FMDD Mon YYYY')
           else format('on %s (in %s)', to_char(t.lease_end, 'FMDD Mon YYYY'), public.days_text(v_days_left)) end);
  elsif v_owed > 0 then
    v_body := format('Your next rent payment of %s for %s is due on %s. No action is required at this time.',
      public.ugx(v_next_amount), t.house, to_char(v_next_due, 'FMDD Mon YYYY'));
  else
    v_body := 'Your rent is fully paid.' ||
      case when v_days_left is not null
        then format(' Your current rental period for %s runs until %s (%s remaining).', t.house, to_char(t.lease_end, 'FMDD Mon YYYY'), public.days_text(v_days_left))
        else '' end || ' Thank you.';
  end if;

  insert into public.notifications (landlord_id, tenant_id, type, title, body, dedupe_key)
  values (t.landlord_id, t.id, 'status', 'Rent status', v_body,
          case when exists (select 1 from public.notifications where dedupe_key = v_key) then null else v_key end)
  on conflict (dedupe_key) do nothing;
end $$;

revoke execute on function public.send_rent_status(uuid, boolean) from public, anon, authenticated;

-- ── Tenant opens the app: rent status at most once a day ──
create or replace function public.check_rent_status() returns void
language plpgsql volatile security definer set search_path = '' as $$
declare v_tenant uuid;
begin
  select id into v_tenant from public.tenants where user_id = auth.uid() and property_id is not null;
  if v_tenant is not null then
    perform public.send_rent_status(v_tenant, false);
  end if;
end $$;

-- ── Anyone signs in: security alert (+ rent status for tenants) ──
create or replace function public.notify_sign_in(p_device text) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  v_role text;
  v_device text := left(coalesce(nullif(trim(p_device), ''), 'an unknown device'), 80);
  v_when text := to_char(now() at time zone 'Africa/Kampala', 'FMHH12:MI AM "on" FMDD Mon YYYY');
  v_body text;
  t record;
begin
  if me is null then return; end if;
  select role into v_role from public.profiles where id = me;
  v_body := format('A new sign-in to your account was detected on %s at %s (EAT). If this was not you, please change your password immediately under Settings > Change password.', v_device, v_when);

  if v_role in ('landlord', 'superadmin') then
    insert into public.staff_notifications (user_id, type, title, body, url)
    values (me, 'security', 'Account security', v_body, case when v_role = 'landlord' then '/landlord/inbox' else '/admin2026/inbox' end);
    return;
  end if;

  -- Tenants: notifications belong to a tenant record (none yet = not connected, nothing to store)
  select id, landlord_id, property_id into t from public.tenants where user_id = me;
  if not found then return; end if;

  insert into public.notifications (landlord_id, tenant_id, type, title, body)
  values (t.landlord_id, t.id, 'security', 'Account security', v_body);

  if t.property_id is not null then
    perform public.send_rent_status(t.id, true);
  end if;
end $$;

revoke execute on function public.check_rent_status() from public, anon;
revoke execute on function public.notify_sign_in(text) from public, anon;
grant execute on function public.check_rent_status() to authenticated;
grant execute on function public.notify_sign_in(text) to authenticated;

-- ── Tenant connects to their landlord: welcome + note to the landlord ──
create or replace function public.notify_tenant_connected() returns trigger
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_house text;
  v_landlord text;
begin
  if new.user_id is null or new.property_id is null or old.user_id is not distinct from new.user_id then
    return new;
  end if;
  select name into v_house from public.properties where id = new.property_id;
  select nullif(full_name, '') into v_landlord from public.profiles where id = new.landlord_id;

  insert into public.notifications (landlord_id, tenant_id, type, title, body)
  values (new.landlord_id, new.id, 'welcome', 'Account connected',
    format('Your account is now connected to %s%s. Rent charges, payment receipts and notices from your landlord will appear here.',
      coalesce(v_house, 'your rental'), coalesce(', managed by ' || v_landlord, '')));

  insert into public.staff_notifications (user_id, type, title, body, url)
  values (new.landlord_id, 'tenant', 'Tenant connected',
    format('%s has connected their Renta account for %s and will now receive your notifications.', new.full_name, coalesce(v_house, 'their rental')),
    '/landlord/tenants');
  return new;
end $$;

drop trigger if exists tenants_notify_connected on public.tenants;
create trigger tenants_notify_connected after update of user_id on public.tenants
  for each row execute function public.notify_tenant_connected();

-- ── Every 5 hours while rent is overdue or the paid period has ended ──
create or replace function public.send_overdue_reminders() returns integer
language plpgsql volatile security definer set search_path = '' as $$
declare
  today date := public.kampala_today();
  v_hour integer := extract(hour from now() at time zone 'Africa/Kampala');
  n integer;
begin
  if v_hour < 7 or v_hour >= 22 then return 0; end if; -- quiet hours: no reminders at night

  insert into public.notifications (landlord_id, tenant_id, type, title, body)
  select t.landlord_id, t.id, 'rent_due', 'Rent reminder',
    case when o.amount > 0
      then format('This is a reminder that %s for %s has been outstanding since %s. Please make payment through the Payments page as soon as possible.',
             public.ugx(o.amount), p.name, to_char(o.since, 'FMDD Mon YYYY'))
      else format('Your paid rental period for %s ended on %s. Please make a payment to renew your tenancy, or contact your landlord to discuss your plans.',
             p.name, to_char(t.lease_end, 'FMDD Mon YYYY')) end
  from public.tenants t
  join public.properties p on p.id = t.property_id
  cross join lateral (
    select coalesce(sum(amount - amount_paid), 0) as amount, min(due_date) as since
    from public.payments where tenant_id = t.id and status = 'pending' and due_date < today
  ) o
  where t.property_id is not null
    and t.user_id is not null
    and (o.amount > 0 or (t.lease_end is not null and t.lease_end < today))
    and not exists (
      select 1 from public.notifications x
      where x.tenant_id = t.id and x.type = 'rent_due' and x.created_at > now() - interval '4 hours 50 minutes'
    );

  get diagnostics n = row_count;
  return n;
end $$;

revoke execute on function public.send_overdue_reminders() from public, anon, authenticated;

-- Checked every hour; each tenant gets one at most every 5 hours
create extension if not exists pg_cron;
select cron.schedule('renta-overdue-reminders', '0 * * * *', 'select public.send_overdue_reminders()');

-- ────────────── 19_login_email_check.sql ──────────────

-- 19 · login email check
-- The sign-in page checks the email while it's typed and shows ✓ / ✗ and the account type.
-- Returns one of:
--   'first_login' → landlord who hasn't set a password yet (password box is hidden; they set one next)
--   'landlord'    → landlord account
--   'tenant'      → tenant account
--   'suspended'   → landlord account suspended by the main admin
--   'not_found'   → no account (the main admin is also reported as not found: it signs in at /admin2026)
-- Safe to run more than once.

create or replace function public.login_email_status(p_email text) returns text
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select case
       when p.role = 'landlord' and not p.active then 'suspended'
       when p.role = 'landlord' and p.must_change_password then 'first_login'
       when p.role = 'landlord' then 'landlord'
       when p.role = 'tenant' then 'tenant'
       else 'not_found'
     end
     from public.profiles p
     where lower(p.email) = lower(trim(p_email))
     limit 1),
    'not_found');
$$;

revoke execute on function public.login_email_status(text) from public;
grant execute on function public.login_email_status(text) to anon, authenticated;

-- ────────────── 20_login_phone_check.sql ──────────────

-- 20 · login phone check
-- The sign-in page accepts an email OR a phone number in the same box.
-- When a phone number is typed, this tells the page what kind of account it belongs to
-- (same answers as login_email_status), WITHOUT revealing the account's email.
-- Numbers match on their last 9 digits, so 0772 123456, +256772123456 and 256 772 123 456 are the same.
-- Safe to run more than once.

create or replace function public.login_phone_status(p_phone text) returns text
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select case
       when p.role = 'landlord' and not p.active then 'suspended'
       when p.role = 'landlord' and p.must_change_password then 'first_login'
       when p.role = 'landlord' then 'landlord'
       when p.role = 'tenant' then 'tenant'
       else 'not_found'
     end
     from public.profiles p
     where length(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g')) >= 9
       and right(regexp_replace(coalesce(p.phone, ''), '\D', '', 'g'), 9)
         = right(regexp_replace(p_phone, '\D', '', 'g'), 9)
     order by p.created_at desc nulls last
     limit 1),
    'not_found');
$$;

revoke execute on function public.login_phone_status(text) from public;
grant execute on function public.login_phone_status(text) to anon, authenticated;

-- ────────────── 21_recharge.sql ──────────────

-- 21 · recharge (pay rent in advance)
-- A tenant can pay any unpaid rent PLUS 1–12 months ahead in ONE mobile money payment.
-- The server records it as one momo attempt with `advance_months` set. Only after the payment
-- is verified does it create the rent charges for the months ahead and pay everything off,
-- oldest first. A failed or cancelled payment leaves nothing behind.
-- Safe to run more than once.

-- A recharge may not be tied to one existing rent charge (there may be none yet)
alter table public.momo_attempts alter column payment_id drop not null;

alter table public.momo_attempts add column if not exists advance_months int;
alter table public.momo_attempts drop constraint if exists momo_attempts_advance_months_check;
alter table public.momo_attempts add constraint momo_attempts_advance_months_check
  check (advance_months is null or advance_months between 1 and 12);

create index if not exists momo_attempts_tenant_pending_idx on public.momo_attempts (tenant_id) where status = 'pending';

-- ────────────── 22_month_start_notices.sql ──────────────

-- 22 · new paid month notices
-- When a month the tenant has ALREADY paid for begins (e.g. recharged in advance), they get a
-- notification: "Your December rent is already paid… runs 1 Dec – 31 Dec… paid up to …".
-- Runs every morning; each tenant gets it once per month (dedupe_key), only if that month's
-- rent was fully paid before the month started.
-- Safe to run more than once.

create or replace function public.send_month_start_notices() returns integer
language plpgsql volatile security definer set search_path = '' as $$
declare
  today date := (now() at time zone 'Africa/Kampala')::date;
  v_period text := to_char(today, 'YYYY-MM');
  v_start date := date_trunc('month', today)::date;
  v_end date := (date_trunc('month', today) + interval '1 month - 1 day')::date;
  n integer;
begin
  insert into public.notifications (landlord_id, tenant_id, type, title, body, dedupe_key)
  select
    t.landlord_id,
    t.id,
    'reminder',
    'New month started', -- sender line; the notification title is always "Renta UG"
    format('Your %s rent for %s is already paid. This month runs from %s to %s (%s days).%s',
      to_char(v_start, 'FMMonth YYYY'),
      pr.name,
      to_char(v_start, 'FMDD Mon'),
      to_char(v_end, 'FMDD Mon YYYY'),
      v_end - v_start + 1,
      case when ahead.until is not null and ahead.until > v_period
        then format(' You are paid up to the end of %s.', to_char(to_date(ahead.until || '-01', 'YYYY-MM-DD'), 'FMMonth YYYY'))
        else ' Remember to recharge before the month ends.' end),
    format('month_start:%s:%s', t.id, v_period)
  from public.tenants t
  join public.properties pr on pr.id = t.property_id
  join public.payments p on p.tenant_id = t.id and p.period = v_period and p.status = 'paid'
  cross join lateral (
    -- latest month paid from this one onwards
    select max(x.period) as until
    from public.payments x
    where x.tenant_id = t.id and x.status = 'paid' and x.period >= v_period
  ) ahead
  where t.property_id is not null
    and t.user_id is not null
    and p.paid_at is not null
    and (p.paid_at at time zone 'Africa/Kampala')::date < v_start + 1 -- paid before (or on) the 1st
    and today - v_start <= 2 -- only in the first days of the month
  on conflict (dedupe_key) do nothing;

  get diagnostics n = row_count;
  return n;
end $$;

revoke execute on function public.send_month_start_notices() from public, anon, authenticated;

-- Every day at 05:00 UTC = 08:00 in Kampala
create extension if not exists pg_cron;
select cron.schedule('renta-month-start-notices', '0 5 * * *', 'select public.send_month_start_notices()');

-- ────────────── 23_notification_delete.sql ──────────────

-- 23 · tenants can delete notifications
-- "Delete" hides the notification for the TENANT only (tenant_hidden = true). The landlord keeps
-- their record of what was sent. Tenants may only change `read` and `tenant_hidden` on their own
-- notifications (the "notifications mark read" policy from 08 limits it to their own rows).
-- Safe to run more than once.

alter table public.notifications add column if not exists tenant_hidden boolean not null default false;

revoke update on public.notifications from anon, authenticated;
grant update (read, tenant_hidden) on public.notifications to authenticated;

-- ────────────── 24_cash_confirmation.sql ──────────────

-- 24 · cash payments with confirmation + tenants managed by their landlord
--
--  Tenants without a smartphone
--   • tenants.managed_by_landlord: the landlord registered this tenant and manages them (no app account).
--     Shown only to the tenant's landlord and the main admin. Notices, charges and payments are still
--     recorded for them as usual.
--
--  Cash payments ("I paid my landlord in cash")
--   • Anyone can REPORT cash: the tenant in the app, or the landlord for any of their tenants.
--   • It waits in cash_payments as 'pending' until it is CONFIRMED (amount can be corrected) or REJECTED:
--       reported by the tenant   → confirmed by their landlord OR the main admin
--       recorded by the landlord → confirmed by the main admin (nobody confirms their own entry)
--   • On confirmation the amount is credited to the tenant's oldest unpaid rent first, a receipt is
--     kept, and the tenant is notified. Landlord and main admin get a note in their inbox.
--   • Landlords can no longer credit cash directly (record_cash_payment is switched off for the app).
-- Safe to run more than once. No data is deleted.

-- ── Tenants managed by the landlord ──
alter table public.tenants add column if not exists managed_by_landlord boolean not null default false;

-- ── Cash payments queue ──
create table if not exists public.cash_payments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  landlord_id uuid not null references auth.users (id) on delete cascade,
  amount bigint not null check (amount > 0),              -- amount reported
  paid_on date not null,                                  -- day the cash was handed over
  note text,
  submitted_by uuid references auth.users (id) on delete set null,
  submitted_role text not null check (submitted_role in ('tenant', 'landlord')),
  status text not null default 'pending' check (status in ('pending', 'confirmed', 'rejected')),
  confirmed_amount bigint,                                -- amount actually credited
  reviewed_by uuid references auth.users (id) on delete set null,
  reviewed_role text check (reviewed_role in ('landlord', 'superadmin')),
  reviewed_at timestamptz,
  reject_reason text,
  created_at timestamptz not null default now()
);
create index if not exists cash_payments_tenant_id_idx on public.cash_payments (tenant_id);
create index if not exists cash_payments_landlord_id_idx on public.cash_payments (landlord_id);
create index if not exists cash_payments_pending_idx on public.cash_payments (status) where status = 'pending';
alter table public.cash_payments enable row level security;

drop policy if exists "cash tenant read" on public.cash_payments;
drop policy if exists "cash landlord read" on public.cash_payments;
drop policy if exists "cash superadmin read" on public.cash_payments;
create policy "cash tenant read" on public.cash_payments for select to authenticated using (tenant_id = public.my_tenant_id());
create policy "cash landlord read" on public.cash_payments for select to authenticated
  using (public.is_landlord() and landlord_id = auth.uid());
create policy "cash superadmin read" on public.cash_payments for select to authenticated using (public.is_superadmin());

-- Read only for signed-in users; every change goes through the functions below
revoke all on public.cash_payments from anon, authenticated;
grant select on public.cash_payments to authenticated;
grant all on public.cash_payments to service_role;

do $$ begin
  alter publication supabase_realtime add table public.cash_payments;
exception when duplicate_object then null; end $$;

-- ── Helpers ──
create or replace function public.tenant_outstanding(p_tenant_id uuid) returns bigint
language sql stable security definer set search_path = '' as $$
  select coalesce(sum(amount - amount_paid), 0) from public.payments where tenant_id = p_tenant_id and status = 'pending';
$$;
revoke execute on function public.tenant_outstanding(uuid) from public, anon, authenticated;

-- Inbox note for every main admin
create or replace function public.notify_admins(p_type text, p_title text, p_body text) returns void
language sql volatile security definer set search_path = '' as $$
  insert into public.staff_notifications (user_id, type, title, body, url)
  select id, p_type, p_title, p_body, '/admin2026/cash' from public.profiles where role = 'superadmin';
$$;
revoke execute on function public.notify_admins(text, text, text) from public, anon, authenticated;

-- ── Report / record cash ──
-- Tenant: p_tenant_id may be null (their own record is used). Landlord: one of their tenants.
create or replace function public.submit_cash_payment(
  p_tenant_id uuid,
  p_amount bigint,
  p_paid_on date default null,
  p_note text default null
) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  v_role text;
  v_tenant record;
  v_house text;
  v_landlord_name text;
  v_outstanding bigint;
  v_pending bigint;
  v_paid_on date := coalesce(p_paid_on, public.kampala_today());
  v_id uuid;
begin
  select role into v_role from public.profiles where id = me;

  if v_role = 'tenant' then
    select * into v_tenant from public.tenants where id = coalesce(p_tenant_id, public.my_tenant_id()) and user_id = me;
    if not found or v_tenant.property_id is null then
      raise exception 'You are not connected to a house.';
    end if;
  elsif public.is_landlord() then
    select * into v_tenant from public.tenants where id = p_tenant_id and landlord_id = me;
    if not found then raise exception 'Tenant not found.'; end if;
    v_role := 'landlord';
  else
    raise exception 'Only tenants and landlords can record cash payments.';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Enter an amount greater than zero.';
  end if;
  if v_paid_on > public.kampala_today() then
    raise exception 'The payment date cannot be in the future.';
  end if;

  v_outstanding := public.tenant_outstanding(v_tenant.id);
  select coalesce(sum(amount), 0) into v_pending from public.cash_payments where tenant_id = v_tenant.id and status = 'pending';
  if v_outstanding = 0 then
    raise exception 'There is no unpaid rent to pay. Ask the landlord to create a rent charge first.';
  end if;
  if p_amount + v_pending > v_outstanding then
    raise exception '%', format('That is more than the unpaid rent of %s%s.',
      public.ugx(v_outstanding),
      case when v_pending > 0 then format(' (%s is already waiting for confirmation)', public.ugx(v_pending)) else '' end);
  end if;

  insert into public.cash_payments (tenant_id, landlord_id, amount, paid_on, note, submitted_by, submitted_role)
  values (v_tenant.id, v_tenant.landlord_id, p_amount, v_paid_on, nullif(trim(p_note), ''), me, v_role)
  returning id into v_id;

  select name into v_house from public.properties where id = v_tenant.property_id;
  select nullif(full_name, '') into v_landlord_name from public.profiles where id = v_tenant.landlord_id;

  if v_role = 'tenant' then
    insert into public.staff_notifications (user_id, type, title, body, url)
    values (v_tenant.landlord_id, 'cash', 'Cash payment to confirm',
      format('%s says they paid you %s in cash on %s%s. Please confirm the amount you received.',
        v_tenant.full_name, public.ugx(p_amount), to_char(v_paid_on, 'FMDD Mon YYYY'), coalesce(' for ' || v_house, '')),
      '/landlord/payments');
    perform public.notify_admins('cash', 'Cash payment reported',
      format('%s (%s) reported paying %s in cash on %s. Waiting for confirmation.',
        v_tenant.full_name, coalesce(v_house, 'no house'), public.ugx(p_amount), to_char(v_paid_on, 'FMDD Mon YYYY')));
  else
    perform public.notify_admins('cash', 'Cash payment to confirm',
      format('%s recorded %s in cash from %s (%s) on %s. Please confirm.',
        coalesce(v_landlord_name, 'A landlord'), public.ugx(p_amount), v_tenant.full_name, coalesce(v_house, 'no house'),
        to_char(v_paid_on, 'FMDD Mon YYYY')));
    insert into public.notifications (landlord_id, tenant_id, type, title, body)
    values (v_tenant.landlord_id, v_tenant.id, 'payment', 'Cash payment received',
      format('Your landlord recorded a cash payment of %s from you on %s. It will be added to your rent as soon as Renta UG confirms it.',
        public.ugx(p_amount), to_char(v_paid_on, 'FMDD Mon YYYY')));
  end if;

  return v_id;
end $$;

-- ── Who may review a cash entry ──
create or replace function public.can_review_cash(c public.cash_payments) returns text
language plpgsql stable security definer set search_path = '' as $$
begin
  if public.is_superadmin() then return 'superadmin'; end if;
  if public.is_landlord() and c.landlord_id = auth.uid() then
    if c.submitted_role = 'landlord' then
      raise exception 'Cash you recorded is confirmed by Renta UG (the main admin).';
    end if;
    return 'landlord';
  end if;
  raise exception 'You cannot review this payment.';
end $$;
revoke execute on function public.can_review_cash(public.cash_payments) from public, anon, authenticated;

-- ── Confirm: credit the (possibly corrected) amount to the tenant, oldest rent first ──
create or replace function public.confirm_cash_payment(p_id uuid, p_amount bigint default null) returns json
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  c public.cash_payments;
  v_reviewer text;
  v_amount bigint;
  v_outstanding bigint;
  v_left bigint;
  v_take bigint;
  v_completed text[] := '{}';
  v_balance_after bigint;
  v_tenant record;
  v_house text;
  v_landlord_name text;
  r record;
begin
  select * into c from public.cash_payments where id = p_id for update;
  if not found then raise exception 'Payment not found.'; end if;
  if c.status <> 'pending' then raise exception 'This payment has already been %.', c.status; end if;
  v_reviewer := public.can_review_cash(c);

  v_amount := coalesce(p_amount, c.amount);
  if v_amount <= 0 then raise exception 'Enter an amount greater than zero.'; end if;
  v_outstanding := public.tenant_outstanding(c.tenant_id);
  if v_amount > v_outstanding then
    raise exception 'That is more than the unpaid rent of %.', public.ugx(v_outstanding);
  end if;

  v_left := v_amount;
  for r in
    select * from public.payments
    where tenant_id = c.tenant_id and status = 'pending'
    order by due_date, period
    for update
  loop
    exit when v_left <= 0;
    v_take := least(v_left, r.amount - r.amount_paid);
    v_left := v_left - v_take;

    insert into public.payment_receipts (payment_id, tenant_id, landlord_id, amount, method, note, received_at, recorded_by)
    values (r.id, c.tenant_id, c.landlord_id, v_take, 'Cash', c.note, c.paid_on::timestamptz + interval '12 hours', me);

    update public.payments
    set amount_paid = amount_paid + v_take,
        status = case when amount_paid + v_take >= amount then 'paid' else 'pending' end,
        paid_at = case when amount_paid + v_take >= amount then now() else paid_at end,
        method = 'Cash'
    where id = r.id;

    if r.amount_paid + v_take >= r.amount then
      v_completed := v_completed || to_char(to_date(r.period || '-01', 'YYYY-MM-DD'), 'FMMonth YYYY');
    end if;
  end loop;

  update public.cash_payments
  set status = 'confirmed', confirmed_amount = v_amount, reviewed_by = me, reviewed_role = v_reviewer, reviewed_at = now()
  where id = c.id;

  v_balance_after := public.tenant_outstanding(c.tenant_id);
  select * into v_tenant from public.tenants where id = c.tenant_id;
  select name into v_house from public.properties where id = coalesce(v_tenant.property_id, v_tenant.last_property_id);
  select nullif(full_name, '') into v_landlord_name from public.profiles where id = c.landlord_id;

  -- Tenant
  insert into public.notifications (landlord_id, tenant_id, type, title, body)
  values (c.landlord_id, c.tenant_id, 'payment', 'Payment confirmation',
    format('Your cash payment of %s made on %s has been confirmed by %s%s.%s %s',
      public.ugx(v_amount),
      to_char(c.paid_on, 'FMDD Mon YYYY'),
      case when v_reviewer = 'superadmin' then 'Renta UG' else 'your landlord' end,
      case when v_amount <> c.amount then format(' (you reported %s)', public.ugx(c.amount)) else '' end,
      case when array_length(v_completed, 1) > 0
        then format(' Rent for %s is now paid in full.', array_to_string(v_completed, ', ')) else '' end,
      case when v_balance_after = 0 then 'You have no outstanding balance. Thank you.'
           else format('Outstanding balance: %s.', public.ugx(v_balance_after)) end));

  -- The other side
  if v_reviewer = 'superadmin' then
    insert into public.staff_notifications (user_id, type, title, body, url)
    values (c.landlord_id, 'cash', 'Cash payment confirmed',
      format('Renta UG confirmed %s in cash from %s%s. It has been added to their rent.',
        public.ugx(v_amount), v_tenant.full_name, coalesce(' (' || v_house || ')', '')),
      '/landlord/payments');
  else
    perform public.notify_admins('cash', 'Cash payment confirmed',
      format('%s confirmed %s in cash from %s%s.',
        coalesce(v_landlord_name, 'A landlord'), public.ugx(v_amount), v_tenant.full_name, coalesce(' (' || v_house || ')', '')));
  end if;

  return json_build_object('applied', v_amount, 'balance_after', v_balance_after, 'completed', array_to_json(v_completed));
end $$;

-- ── Reject ──
create or replace function public.reject_cash_payment(p_id uuid, p_reason text default null) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  c public.cash_payments;
  v_reviewer text;
  v_reason text := nullif(trim(p_reason), '');
  v_tenant_name text;
begin
  select * into c from public.cash_payments where id = p_id for update;
  if not found then raise exception 'Payment not found.'; end if;
  if c.status <> 'pending' then raise exception 'This payment has already been %.', c.status; end if;
  v_reviewer := public.can_review_cash(c);

  update public.cash_payments
  set status = 'rejected', reject_reason = v_reason, reviewed_by = me, reviewed_role = v_reviewer, reviewed_at = now()
  where id = c.id;

  insert into public.notifications (landlord_id, tenant_id, type, title, body)
  values (c.landlord_id, c.tenant_id, 'payment', 'Cash payment not confirmed',
    format('The cash payment of %s recorded for %s could not be confirmed%s. Please contact your landlord.',
      public.ugx(c.amount), to_char(c.paid_on, 'FMDD Mon YYYY'), coalesce(': ' || v_reason, '')));

  if v_reviewer = 'superadmin' and c.submitted_role = 'landlord' then
    select full_name into v_tenant_name from public.tenants where id = c.tenant_id;
    insert into public.staff_notifications (user_id, type, title, body, url)
    values (c.landlord_id, 'cash', 'Cash payment not confirmed',
      format('Renta UG did not confirm the %s cash you recorded from %s%s.',
        public.ugx(c.amount), v_tenant_name, coalesce(': ' || v_reason, '')),
      '/landlord/payments');
  end if;
end $$;

revoke execute on function public.submit_cash_payment(uuid, bigint, date, text) from public, anon;
revoke execute on function public.confirm_cash_payment(uuid, bigint) from public, anon;
revoke execute on function public.reject_cash_payment(uuid, text) from public, anon;
grant execute on function public.submit_cash_payment(uuid, bigint, date, text) to authenticated;
grant execute on function public.confirm_cash_payment(uuid, bigint) to authenticated;
grant execute on function public.reject_cash_payment(uuid, text) to authenticated;

-- Cash now always goes through confirmation
do $$ begin
  revoke execute on function public.record_cash_payment(uuid, bigint, timestamptz, text) from authenticated;
exception when undefined_function then null; end $$;

-- ────────────── 25_tenant_phone_first_login.sql ──────────────

-- 25 · tenant first sign-in by phone
-- A tenant without a smartphone is managed by their landlord. When they get one, the landlord gives
-- them app access (the server creates their login with must_change_password = true). The sign-in
-- page then recognises their phone number as 'tenant_first_login': no password needed, and they go
-- straight to adding their email and choosing a password.
-- Safe to run more than once.

create or replace function public.login_phone_status(p_phone text) returns text
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select case
       when p.role = 'landlord' and not p.active then 'suspended'
       when p.role = 'landlord' and p.must_change_password then 'first_login'
       when p.role = 'landlord' then 'landlord'
       when p.role = 'tenant' and p.must_change_password then 'tenant_first_login'
       when p.role = 'tenant' then 'tenant'
       else 'not_found'
     end
     from public.profiles p
     where length(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g')) >= 9
       and right(regexp_replace(coalesce(p.phone, ''), '\D', '', 'g'), 9)
         = right(regexp_replace(p_phone, '\D', '', 'g'), 9)
     order by p.created_at desc nulls last
     limit 1),
    'not_found');
$$;

revoke execute on function public.login_phone_status(text) from public;
grant execute on function public.login_phone_status(text) to anon, authenticated;

-- ────────────── 26_rentals.sql ──────────────

-- 26 · rentals (a business with several rooms / houses)
-- A landlord can own a rental (e.g. "Kira Rentals") and choose how many rooms it has.
-- Each room is an ordinary row in properties (so tenants, rent charges and payments work as before),
-- linked to its rental with properties.rental_id. Rooms can be renamed and each can have its own rent.
-- Safe to run more than once.

create table if not exists public.rentals (
  id uuid primary key default gen_random_uuid(),
  landlord_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  location text not null default '',
  type text not null default 'Rooms',
  created_at timestamptz not null default now()
);

create index if not exists rentals_landlord_id_idx on public.rentals (landlord_id);

-- Deleting a rental deletes its rooms (the app blocks it while rooms still have tenants)
alter table public.properties add column if not exists rental_id uuid references public.rentals (id) on delete cascade;
create index if not exists properties_rental_id_idx on public.properties (rental_id);

alter table public.rentals enable row level security;

drop policy if exists "rentals landlord" on public.rentals;
drop policy if exists "rentals superadmin read" on public.rentals;

create policy "rentals landlord" on public.rentals for all to authenticated
  using (public.is_landlord() and landlord_id = auth.uid())
  with check (public.is_landlord() and landlord_id = auth.uid());
create policy "rentals superadmin read" on public.rentals for select to authenticated
  using (public.is_superadmin());

grant select, insert, update, delete on public.rentals to authenticated;
grant all on public.rentals to service_role; -- the server (notifications, app access) reads rental names

-- A tenant in a room can see the name of the rental it belongs to ("Room 3 · Kira Rentals")
create or replace function public.my_rental_id() returns uuid
language sql stable security definer set search_path = '' as $$
  select p.rental_id from public.tenants t join public.properties p on p.id = t.property_id where t.user_id = auth.uid();
$$;
revoke execute on function public.my_rental_id() from public, anon;
grant execute on function public.my_rental_id() to authenticated;

drop policy if exists "rentals tenant read" on public.rentals;
create policy "rentals tenant read" on public.rentals for select to authenticated
  using (id = public.my_rental_id());

-- Live updates when rooms / rentals change (another device of the same landlord, or the tenant's view)
do $$
declare t text;
begin
  foreach t in array array['properties', 'rentals'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

-- ────────────── 27_one_house_per_tenant.sql ──────────────

-- 27 · a tenant lives in ONE house / room at a time
-- Blocks adding (or moving) a tenant into a house while the same person — same app account,
-- same email or same phone number (last 9 digits) — is already renting another house or room,
-- with this landlord or any other. Former stays (property_id is null) don't count.
-- Safe to run more than once.

create or replace function public.check_one_house_per_tenant() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_phone text := right(regexp_replace(coalesce(new.phone, ''), '\D', '', 'g'), 9);
  v_other record;
begin
  if new.property_id is null then
    return new;
  end if;

  select t.full_name, p.name as house into v_other
  from public.tenants t
  left join public.properties p on p.id = t.property_id
  where t.id <> new.id
    and t.property_id is not null
    and (
      (new.user_id is not null and t.user_id = new.user_id)
      or (new.email is not null and new.email not like '%@phone-signin.example.com' and lower(t.email) = lower(new.email))
      or (length(v_phone) = 9 and right(regexp_replace(coalesce(t.phone, ''), '\D', '', 'g'), 9) = v_phone)
    )
  limit 1;

  if found then
    raise exception '%', format('%s already rents %s. A tenant can only be in one house or room at a time.',
      v_other.full_name, coalesce(v_other.house, 'another house'));
  end if;
  return new;
end $$;

drop trigger if exists tenants_one_house on public.tenants;
create trigger tenants_one_house
  before insert or update of property_id, email, phone, user_id on public.tenants
  for each row execute function public.check_one_house_per_tenant();

-- ────────────── 28_cash_any_time.sql ──────────────

-- 28 · cash at any time
-- Cash can be recorded for any current tenant, whether rent is due or not.
-- When it's confirmed it pays unpaid rent first (oldest first); anything left pays the NEXT months
-- ahead at the house's monthly rent (rent charges are created for those months, like a recharge).
-- Up to 24 months ahead. Replaces submit_cash_payment / confirm_cash_payment from 24.
-- Safe to run more than once. No data is deleted.

-- Next rent month for a tenant: the month after their latest charge, or this month if that's later
create or replace function public.next_rent_period(p_tenant_id uuid) returns text
language sql stable security definer set search_path = '' as $$
  select greatest(
    coalesce(to_char((to_date(max(period) || '-01', 'YYYY-MM-DD') + interval '1 month'), 'YYYY-MM'), '0000-00'),
    to_char(public.kampala_today(), 'YYYY-MM'))
  from public.payments where tenant_id = p_tenant_id;
$$;
revoke execute on function public.next_rent_period(uuid) from public, anon, authenticated;

-- ── Report / record cash ──
create or replace function public.submit_cash_payment(
  p_tenant_id uuid,
  p_amount bigint,
  p_paid_on date default null,
  p_note text default null
) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  v_role text;
  v_tenant record;
  v_house text;
  v_rent bigint;
  v_landlord_name text;
  v_outstanding bigint;
  v_pending bigint;
  v_paid_on date := coalesce(p_paid_on, public.kampala_today());
  v_id uuid;
begin
  select role into v_role from public.profiles where id = me;

  if v_role = 'tenant' then
    select * into v_tenant from public.tenants where id = coalesce(p_tenant_id, public.my_tenant_id()) and user_id = me;
    if not found or v_tenant.property_id is null then
      raise exception 'You are not connected to a house.';
    end if;
  elsif public.is_landlord() then
    select * into v_tenant from public.tenants where id = p_tenant_id and landlord_id = me;
    if not found then raise exception 'Tenant not found.'; end if;
    if v_tenant.property_id is null then raise exception 'This tenant no longer rents from you.'; end if;
    v_role := 'landlord';
  else
    raise exception 'Only tenants and landlords can record cash payments.';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Enter an amount greater than zero.';
  end if;
  if v_paid_on > public.kampala_today() then
    raise exception 'The payment date cannot be in the future.';
  end if;

  select name, rent into v_house, v_rent from public.properties where id = v_tenant.property_id;
  v_outstanding := public.tenant_outstanding(v_tenant.id);
  select coalesce(sum(amount), 0) into v_pending from public.cash_payments where tenant_id = v_tenant.id and status = 'pending';

  -- Beyond what's owed, the rest pays months ahead: needs a monthly rent, at most 24 months
  if p_amount + v_pending > v_outstanding then
    if coalesce(v_rent, 0) <= 0 then
      raise exception 'This house has no monthly rent set, so cash beyond what is owed cannot be recorded.';
    end if;
    if p_amount + v_pending - v_outstanding > v_rent * 24 then
      raise exception '%', format('That pays more than 2 years ahead (rent is %s a month).', public.ugx(v_rent));
    end if;
  end if;

  insert into public.cash_payments (tenant_id, landlord_id, amount, paid_on, note, submitted_by, submitted_role)
  values (v_tenant.id, v_tenant.landlord_id, p_amount, v_paid_on, nullif(trim(p_note), ''), me, v_role)
  returning id into v_id;

  select nullif(full_name, '') into v_landlord_name from public.profiles where id = v_tenant.landlord_id;

  if v_role = 'tenant' then
    insert into public.staff_notifications (user_id, type, title, body, url)
    values (v_tenant.landlord_id, 'cash', 'Cash payment to confirm',
      format('%s says they paid you %s in cash on %s%s. Please confirm the amount you received.',
        v_tenant.full_name, public.ugx(p_amount), to_char(v_paid_on, 'FMDD Mon YYYY'), coalesce(' for ' || v_house, '')),
      '/landlord/payments');
    perform public.notify_admins('cash', 'Cash payment reported',
      format('%s (%s) reported paying %s in cash on %s. Waiting for confirmation.',
        v_tenant.full_name, coalesce(v_house, 'no house'), public.ugx(p_amount), to_char(v_paid_on, 'FMDD Mon YYYY')));
  else
    perform public.notify_admins('cash', 'Cash payment to confirm',
      format('%s recorded %s in cash from %s (%s) on %s. Please confirm.',
        coalesce(v_landlord_name, 'A landlord'), public.ugx(p_amount), v_tenant.full_name, coalesce(v_house, 'no house'),
        to_char(v_paid_on, 'FMDD Mon YYYY')));
    insert into public.notifications (landlord_id, tenant_id, type, title, body)
    values (v_tenant.landlord_id, v_tenant.id, 'payment', 'Cash payment received',
      format('Your landlord recorded a cash payment of %s from you on %s. It will be added to your rent as soon as Renta UG confirms it.',
        public.ugx(p_amount), to_char(v_paid_on, 'FMDD Mon YYYY')));
  end if;

  return v_id;
end $$;

-- ── Confirm: unpaid rent first, then months ahead ──
create or replace function public.confirm_cash_payment(p_id uuid, p_amount bigint default null) returns json
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  c public.cash_payments;
  v_reviewer text;
  v_amount bigint;
  v_left bigint;
  v_take bigint;
  v_completed text[] := '{}';
  v_ahead int := 0;
  v_balance_after bigint;
  v_tenant record;
  v_rent bigint;
  v_house text;
  v_landlord_name text;
  v_period text;
  v_charge uuid;
  r record;
begin
  select * into c from public.cash_payments where id = p_id for update;
  if not found then raise exception 'Payment not found.'; end if;
  if c.status <> 'pending' then raise exception 'This payment has already been %.', c.status; end if;
  v_reviewer := public.can_review_cash(c);

  v_amount := coalesce(p_amount, c.amount);
  if v_amount <= 0 then raise exception 'Enter an amount greater than zero.'; end if;

  select * into v_tenant from public.tenants where id = c.tenant_id;
  select rent into v_rent from public.properties where id = v_tenant.property_id;
  if v_amount > public.tenant_outstanding(c.tenant_id) then
    if v_tenant.property_id is null or coalesce(v_rent, 0) <= 0 then
      raise exception 'That is more than the unpaid rent of %, and there is no monthly rent to pay ahead.', public.ugx(public.tenant_outstanding(c.tenant_id));
    end if;
    if v_amount - public.tenant_outstanding(c.tenant_id) > v_rent * 24 then
      raise exception 'That pays more than 2 years ahead.';
    end if;
  end if;

  v_left := v_amount;

  -- 1. Unpaid rent, oldest first
  for r in
    select * from public.payments
    where tenant_id = c.tenant_id and status = 'pending'
    order by due_date, period
    for update
  loop
    exit when v_left <= 0;
    v_take := least(v_left, r.amount - r.amount_paid);
    v_left := v_left - v_take;

    insert into public.payment_receipts (payment_id, tenant_id, landlord_id, amount, method, note, received_at, recorded_by)
    values (r.id, c.tenant_id, c.landlord_id, v_take, 'Cash', c.note, c.paid_on::timestamptz + interval '12 hours', me);

    update public.payments
    set amount_paid = amount_paid + v_take,
        status = case when amount_paid + v_take >= amount then 'paid' else 'pending' end,
        paid_at = case when amount_paid + v_take >= amount then now() else paid_at end,
        method = 'Cash'
    where id = r.id;

    if r.amount_paid + v_take >= r.amount then
      v_completed := v_completed || to_char(to_date(r.period || '-01', 'YYYY-MM-DD'), 'FMMonth YYYY');
    end if;
  end loop;

  -- 2. Whatever is left pays the next months ahead
  while v_left > 0 loop
    v_period := public.next_rent_period(c.tenant_id);
    v_take := least(v_left, v_rent);

    insert into public.payments (landlord_id, tenant_id, property_id, period, amount, amount_paid, due_date, status, paid_at, method)
    values (
      c.landlord_id, c.tenant_id, v_tenant.property_id, v_period, v_rent, v_take,
      to_date(v_period || '-05', 'YYYY-MM-DD'),
      case when v_take >= v_rent then 'paid' else 'pending' end,
      case when v_take >= v_rent then now() end,
      'Cash')
    returning id into v_charge;

    insert into public.payment_receipts (payment_id, tenant_id, landlord_id, amount, method, note, received_at, recorded_by)
    values (v_charge, c.tenant_id, c.landlord_id, v_take, 'Cash', c.note, c.paid_on::timestamptz + interval '12 hours', me);

    if v_take >= v_rent then
      v_completed := v_completed || to_char(to_date(v_period || '-01', 'YYYY-MM-DD'), 'FMMonth YYYY');
      v_ahead := v_ahead + 1;
    end if;
    v_left := v_left - v_take;
  end loop;

  update public.cash_payments
  set status = 'confirmed', confirmed_amount = v_amount, reviewed_by = me, reviewed_role = v_reviewer, reviewed_at = now()
  where id = c.id;

  v_balance_after := public.tenant_outstanding(c.tenant_id);
  select name into v_house from public.properties where id = coalesce(v_tenant.property_id, v_tenant.last_property_id);
  select nullif(full_name, '') into v_landlord_name from public.profiles where id = c.landlord_id;

  -- Tenant
  insert into public.notifications (landlord_id, tenant_id, type, title, body)
  values (c.landlord_id, c.tenant_id, 'payment', 'Payment confirmation',
    format('Your cash payment of %s made on %s has been confirmed by %s%s.%s%s %s',
      public.ugx(v_amount),
      to_char(c.paid_on, 'FMDD Mon YYYY'),
      case when v_reviewer = 'superadmin' then 'Renta UG' else 'your landlord' end,
      case when v_amount <> c.amount then format(' (you reported %s)', public.ugx(c.amount)) else '' end,
      case when array_length(v_completed, 1) > 0
        then format(' Rent for %s is now paid in full.', array_to_string(v_completed, ', ')) else '' end,
      case when v_ahead > 0 then format(' That includes %s month%s paid ahead.', v_ahead, case when v_ahead = 1 then '' else 's' end) else '' end,
      case when v_balance_after = 0 then 'You have no outstanding balance. Thank you.'
           else format('Outstanding balance: %s.', public.ugx(v_balance_after)) end));

  -- The other side
  if v_reviewer = 'superadmin' then
    insert into public.staff_notifications (user_id, type, title, body, url)
    values (c.landlord_id, 'cash', 'Cash payment confirmed',
      format('Renta UG confirmed %s in cash from %s%s. It has been added to their rent.',
        public.ugx(v_amount), v_tenant.full_name, coalesce(' (' || v_house || ')', '')),
      '/landlord/payments');
  else
    perform public.notify_admins('cash', 'Cash payment confirmed',
      format('%s confirmed %s in cash from %s%s.',
        coalesce(v_landlord_name, 'A landlord'), public.ugx(v_amount), v_tenant.full_name, coalesce(' (' || v_house || ')', '')));
  end if;

  return json_build_object('applied', v_amount, 'balance_after', v_balance_after, 'completed', array_to_json(v_completed), 'months_ahead', v_ahead);
end $$;

revoke execute on function public.submit_cash_payment(uuid, bigint, date, text) from public, anon;
revoke execute on function public.confirm_cash_payment(uuid, bigint) from public, anon;
grant execute on function public.submit_cash_payment(uuid, bigint, date, text) to authenticated;
grant execute on function public.confirm_cash_payment(uuid, bigint) to authenticated;

-- ────────────── 29_paid_rental_time.sql ──────────────

-- 29 · rental time comes from payments + connection codes only work for the right person
--
--  Rental time (tenants.lease_start / lease_end = "paid from" / "paid up to")
--   • Nobody types dates any more. Each time one month's rent becomes fully paid (mobile money,
--     recharge or confirmed cash), the tenant's rental time grows by exactly one month:
--       – new tenant (no rental time yet)     → starts on the day they pay, ends one month later
--       – tenant already in the room          → continues from where their paid time ended, even if
--                                               they pay late (the late days are not given back)
--   • Existing tenants are recalculated once from what they have already paid.
--
--  Connection codes
--   • A code only connects an account whose email OR phone number matches the tenant's record.
--
-- Safe to run more than once.

-- ── Rental time grows with every fully paid month ──
create or replace function public.extend_rental_time() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_day date := (coalesce(new.paid_at, now()) at time zone 'Africa/Kampala')::date;
begin
  if new.status <> 'paid' or (tg_op = 'UPDATE' and old.status = 'paid') then
    return new;
  end if;
  update public.tenants
  set lease_start = coalesce(lease_start, v_day),
      lease_end = (coalesce(lease_end, v_day) + interval '1 month')::date
  where id = new.tenant_id and property_id is not null;
  return new;
end $$;

drop trigger if exists payments_extend_rental_time on public.payments;
create trigger payments_extend_rental_time
  after insert or update of status on public.payments
  for each row execute function public.extend_rental_time();

-- ── One-time recalculation for current tenants: paid up to = start + months fully paid ──
update public.tenants t
set lease_start = s.start_day,
    lease_end = case when s.paid_months > 0 then (s.start_day + make_interval(months => s.paid_months))::date end
from (
  select tn.id,
         coalesce(
           tn.lease_start,
           (select min((p.paid_at at time zone 'Africa/Kampala')::date) from public.payments p where p.tenant_id = tn.id and p.status = 'paid'),
           (tn.created_at at time zone 'Africa/Kampala')::date
         ) as start_day,
         (select count(*)::int from public.payments p where p.tenant_id = tn.id and p.status = 'paid') as paid_months
  from public.tenants tn
  where tn.property_id is not null
) s
where t.id = s.id;

-- New tenants start with no rental time until they pay
update public.tenants set lease_start = null
where property_id is not null and lease_end is null
  and not exists (select 1 from public.payments p where p.tenant_id = tenants.id and p.status = 'paid');

-- ── Connection code: must match the account's email or phone ──
create or replace function public.redeem_connect_code(p_code text) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  t record;
  me uuid := auth.uid();
  v_email text;
  v_phone text;
  digits9 text;
begin
  if me is null then
    raise exception 'Please sign in first.';
  end if;
  if not exists (select 1 from public.profiles where id = me and role = 'tenant') then
    raise exception 'Only tenant accounts can use a connection code.';
  end if;
  if exists (select 1 from public.tenants where user_id = me and property_id is not null) then
    raise exception 'Your account is already connected to a rental.';
  end if;

  select * into t
  from public.tenants
  where connect_code = upper(trim(p_code))
    and connect_code_expires_at > now()
    and user_id is null
  for update;

  if t.id is null then
    raise exception 'This code is invalid or has expired. Ask your landlord for a new one.';
  end if;

  -- The signed-in account must be the person the landlord registered
  select lower(coalesce(u.email, '')), right(regexp_replace(coalesce(p.phone, u.phone, ''), '\D', '', 'g'), 9)
    into v_email, v_phone
  from auth.users u left join public.profiles p on p.id = u.id
  where u.id = me;
  digits9 := right(regexp_replace(coalesce(t.phone, ''), '\D', '', 'g'), 9);

  if not (
    (t.email is not null and lower(t.email) = v_email)
    or (length(digits9) = 9 and digits9 = v_phone)
  ) then
    raise exception 'This code is for a different account. Sign in with the email or phone number your landlord registered for you, or ask them to check your details.';
  end if;

  -- Detach any former-tenant record so user_id stays unique
  update public.tenants set user_id = null where user_id = me;

  update public.tenants
  set user_id = me,
      email = coalesce(email, nullif(v_email, '')),
      connect_code = null,
      connect_code_expires_at = null
  where id = t.id;

  return t.id;
end $$;

revoke execute on function public.redeem_connect_code(text) from public, anon;
grant execute on function public.redeem_connect_code(text) to authenticated;

-- ────────────── 30_move_out_requests.sql ──────────────

-- 30 · move-out requests
-- A tenant asks to leave their room: they rate the place, write a review and say why they're leaving.
-- The request waits for their landlord OR the main admin. Approved → the tenancy ends (the tenant moves
-- to Records with all history kept, the room becomes vacant) and the tenant's app signs them out.
-- Declined → the tenant is told why and keeps using the app as before.
-- Safe to run more than once. No data is deleted.

create table if not exists public.move_out_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  landlord_id uuid not null references auth.users (id) on delete cascade,
  property_id uuid references public.properties (id) on delete set null,
  user_id uuid references auth.users (id) on delete set null,
  rating int check (rating between 1 and 5),
  review text,
  reason text not null,
  details text,
  status text not null default 'pending' check (status in ('pending', 'approved', 'declined', 'cancelled')),
  decided_by uuid references auth.users (id) on delete set null,
  decided_role text check (decided_role in ('landlord', 'superadmin')),
  decided_at timestamptz,
  decision_note text,
  created_at timestamptz not null default now()
);
create index if not exists move_out_requests_tenant_idx on public.move_out_requests (tenant_id);
create index if not exists move_out_requests_landlord_idx on public.move_out_requests (landlord_id);
create unique index if not exists move_out_requests_one_pending on public.move_out_requests (tenant_id) where status = 'pending';

alter table public.move_out_requests enable row level security;
drop policy if exists "move out tenant read" on public.move_out_requests;
drop policy if exists "move out landlord read" on public.move_out_requests;
drop policy if exists "move out superadmin read" on public.move_out_requests;
create policy "move out tenant read" on public.move_out_requests for select to authenticated using (user_id = auth.uid());
create policy "move out landlord read" on public.move_out_requests for select to authenticated
  using (public.is_landlord() and landlord_id = auth.uid());
create policy "move out superadmin read" on public.move_out_requests for select to authenticated using (public.is_superadmin());

-- Read only; every change goes through the functions below
revoke all on public.move_out_requests from anon, authenticated;
grant select on public.move_out_requests to authenticated;
grant all on public.move_out_requests to service_role;

do $$ begin
  alter publication supabase_realtime add table public.move_out_requests;
exception when duplicate_object then null; end $$;

-- ── Tenant: ask to leave ──
create or replace function public.request_move_out(p_rating int, p_review text, p_reason text, p_details text default null)
returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  t record;
  v_house text;
  v_id uuid;
begin
  select * into t from public.tenants where user_id = me and property_id is not null;
  if not found then raise exception 'You are not renting a room right now.'; end if;
  if exists (select 1 from public.move_out_requests where tenant_id = t.id and status = 'pending') then
    raise exception 'You already have a request waiting for approval.';
  end if;
  if nullif(trim(p_reason), '') is null then raise exception 'Tell us why you are leaving.'; end if;
  if p_rating is not null and (p_rating < 1 or p_rating > 5) then raise exception 'Choose a rating from 1 to 5.'; end if;

  insert into public.move_out_requests (tenant_id, landlord_id, property_id, user_id, rating, review, reason, details)
  values (t.id, t.landlord_id, t.property_id, me, p_rating, nullif(trim(p_review), ''), trim(p_reason), nullif(trim(p_details), ''))
  returning id into v_id;

  select name into v_house from public.properties where id = t.property_id;
  insert into public.staff_notifications (user_id, type, title, body, url)
  values (t.landlord_id, 'move_out', 'Request to leave',
    format('%s has asked to leave %s. Reason: %s. Please review and approve or decline.', t.full_name, coalesce(v_house, 'their room'), trim(p_reason)),
    '/landlord/move-outs');
  insert into public.staff_notifications (user_id, type, title, body, url)
  select id, 'move_out', 'Request to leave',
    format('%s (%s) has asked to leave. Reason: %s.', t.full_name, coalesce(v_house, 'no house'), trim(p_reason)),
    '/admin2026/move-outs'
  from public.profiles where role = 'superadmin';
  return v_id;
end $$;

-- ── Tenant: changed their mind ──
create or replace function public.cancel_move_out() returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  r record;
begin
  update public.move_out_requests set status = 'cancelled', decided_at = now()
  where user_id = auth.uid() and status = 'pending'
  returning * into r;
  if r.id is null then raise exception 'There is no request to cancel.'; end if;
  insert into public.staff_notifications (user_id, type, title, body, url)
  select r.landlord_id, 'move_out', 'Request to leave cancelled',
    format('%s has cancelled their request to leave.', full_name), '/landlord/move-outs'
  from public.tenants where id = r.tenant_id;
end $$;

-- ── Landlord (own tenants) or main admin: approve or decline ──
create or replace function public.decide_move_out(p_id uuid, p_approve boolean, p_note text default null) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  r public.move_out_requests;
  v_role text;
  t record;
  v_house text;
begin
  select * into r from public.move_out_requests where id = p_id for update;
  if not found then raise exception 'Request not found.'; end if;
  if r.status <> 'pending' then raise exception 'This request has already been %.', r.status; end if;
  if public.is_superadmin() then v_role := 'superadmin';
  elsif public.is_landlord() and r.landlord_id = auth.uid() then v_role := 'landlord';
  else raise exception 'You cannot decide on this request.';
  end if;

  select * into t from public.tenants where id = r.tenant_id;
  select name into v_house from public.properties where id = coalesce(t.property_id, r.property_id);

  update public.move_out_requests
  set status = case when p_approve then 'approved' else 'declined' end,
      decided_by = auth.uid(), decided_role = v_role, decided_at = now(), decision_note = nullif(trim(p_note), '')
  where id = r.id;

  if p_approve then
    -- End the tenancy: history stays, the room becomes vacant
    if t.property_id is not null then
      update public.tenants
      set last_property_id = property_id, property_id = null, ended_at = now(), connect_code = null, connect_code_expires_at = null
      where id = t.id;
    end if;
    insert into public.notifications (landlord_id, tenant_id, type, title, body)
    values (r.landlord_id, r.tenant_id, 'general', 'Move-out approved',
      format('Your request to leave %s has been approved. Thank you for staying with us. Your payment history is kept safely.', coalesce(v_house, 'your room')));
  else
    insert into public.notifications (landlord_id, tenant_id, type, title, body)
    values (r.landlord_id, r.tenant_id, 'general', 'Move-out request declined',
      format('Your request to leave %s was not approved%s. Please talk to your landlord.', coalesce(v_house, 'your room'), coalesce(': ' || nullif(trim(p_note), ''), '')));
  end if;

  -- Tell the other side
  if v_role = 'superadmin' then
    insert into public.staff_notifications (user_id, type, title, body, url)
    values (r.landlord_id, 'move_out', case when p_approve then 'Tenant moved out' else 'Move-out declined' end,
      format('Renta UG %s the request from %s to leave %s.', case when p_approve then 'approved' else 'declined' end, t.full_name, coalesce(v_house, 'their room')),
      '/landlord/move-outs');
  else
    insert into public.staff_notifications (user_id, type, title, body, url)
    select id, 'move_out', case when p_approve then 'Tenant moved out' else 'Move-out declined' end,
      format('A landlord %s the request from %s to leave %s.', case when p_approve then 'approved' else 'declined' end, t.full_name, coalesce(v_house, 'their room')),
      '/admin2026/move-outs'
    from public.profiles where role = 'superadmin';
  end if;
end $$;

-- ── Tenant saw the goodbye and signed out: free the account ──
-- Unlinks the app account from the old stay (the landlord keeps the tenant, payments and request in
-- Records). Next sign-in the account is fresh: no old data, and it can connect to a new landlord with
-- a new code the normal way.
create or replace function public.finish_move_out() returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
begin
  if me is null then return; end if;
  -- Only once the move-out was approved and the tenancy has really ended
  if not exists (
    select 1 from public.move_out_requests r join public.tenants t on t.id = r.tenant_id
    where r.user_id = me and r.status = 'approved' and t.property_id is null
  ) then
    return;
  end if;
  update public.tenants set user_id = null where user_id = me and property_id is null;
  update public.move_out_requests set user_id = null where user_id = me and status <> 'pending';
end $$;

revoke execute on function public.finish_move_out() from public, anon;
grant execute on function public.finish_move_out() to authenticated;

revoke execute on function public.request_move_out(int, text, text, text) from public, anon;
revoke execute on function public.cancel_move_out() from public, anon;
revoke execute on function public.decide_move_out(uuid, boolean, text) from public, anon;
grant execute on function public.request_move_out(int, text, text, text) to authenticated;
grant execute on function public.cancel_move_out() to authenticated;
grant execute on function public.decide_move_out(uuid, boolean, text) to authenticated;

-- ────────────── 31_calm_notifications.sql ──────────────

-- 31 · calm, truthful notifications
-- Fewer messages, each one needed at that moment and true to the data:
--   • Sign-in alert: only when the account is used on a device it hasn't used in the last 60 days.
--   • No "rent status" on every sign-in / app open. Opening the app only sends ONE message, once ever:
--     "your rental time hasn't started, it starts the day you pay" for a new tenant who hasn't paid.
--     (The old status could wrongly say "Your rent is fully paid" to a tenant who had paid nothing.)
--   • Rental time ending: 3 days before, the day before and on the day only (was every day for a week).
--   • Overdue / rental time ended: once when it happens, then every 3 days (was every 5 hours), 08:00–20:00.
--   • "New month started" notices are switched off: rental time now runs from the day of payment,
--     so calendar-month messages no longer matched the truth.
--   • Welcome message says when the rental time starts.
-- Same function names and arguments as before, so the app needs no changes. Safe to run more than once.

-- ── Rent status (internal): only the "not started yet" note, once per tenant ──
create or replace function public.send_rent_status(p_tenant_id uuid, p_force boolean) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  t record;
begin
  select tn.*, p.name as house, p.rent into t
  from public.tenants tn join public.properties p on p.id = tn.property_id
  where tn.id = p_tenant_id and tn.property_id is not null;
  if not found then return; end if;

  -- Paid at least once → their rental time is running; reminders come from the daily jobs below
  if t.lease_end is not null or exists (select 1 from public.payments where tenant_id = t.id and amount_paid > 0) then
    return;
  end if;

  insert into public.notifications (landlord_id, tenant_id, type, title, body, dedupe_key)
  values (t.landlord_id, t.id, 'status', 'Rental time',
    format('Your rental time for %s has not started yet. It starts on the day you pay your first rent%s, and runs one month for every month you pay.',
      t.house, coalesce(' of ' || public.ugx(nullif(t.rent, 0)), '')),
    format('not_started:%s', t.id))
  on conflict (dedupe_key) do nothing;
end $$;
revoke execute on function public.send_rent_status(uuid, boolean) from public, anon, authenticated;

create or replace function public.check_rent_status() returns void
language plpgsql volatile security definer set search_path = '' as $$
declare v_tenant uuid;
begin
  select id into v_tenant from public.tenants where user_id = auth.uid() and property_id is not null;
  if v_tenant is not null then perform public.send_rent_status(v_tenant, false); end if;
end $$;
revoke execute on function public.check_rent_status() from public, anon;
grant execute on function public.check_rent_status() to authenticated;

-- ── Sign-in alert: only for a device not used in the last 60 days ──
create or replace function public.notify_sign_in(p_device text) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  v_role text;
  v_device text := left(coalesce(nullif(trim(p_device), ''), 'an unknown device'), 80);
  v_when text := to_char(now() at time zone 'Africa/Kampala', 'FMHH12:MI AM "on" FMDD Mon YYYY');
  v_needle text;
  v_body text;
  t record;
begin
  if me is null then return; end if;
  select role into v_role from public.profiles where id = me;
  v_needle := format('detected on %s at', v_device);
  v_body := format('A new sign-in to your account was detected on %s at %s (EAT). If this was not you, change your password now under Settings > Change password.', v_device, v_when);

  if v_role in ('landlord', 'superadmin') then
    if exists (select 1 from public.staff_notifications
               where user_id = me and type = 'security' and created_at > now() - interval '60 days'
                 and position(v_needle in body) > 0) then
      return; -- a device they already use
    end if;
    insert into public.staff_notifications (user_id, type, title, body, url)
    values (me, 'security', 'Account security', v_body, case when v_role = 'landlord' then '/landlord/inbox' else '/admin2026/inbox' end);
    return;
  end if;

  select id, landlord_id, property_id into t from public.tenants where user_id = me;
  if not found then return; end if;

  if not exists (select 1 from public.notifications
                 where tenant_id = t.id and type = 'security' and created_at > now() - interval '60 days'
                   and position(v_needle in body) > 0) then
    insert into public.notifications (landlord_id, tenant_id, type, title, body)
    values (t.landlord_id, t.id, 'security', 'Account security', v_body);
  end if;

  if t.property_id is not null then perform public.send_rent_status(t.id, false); end if;
end $$;
revoke execute on function public.notify_sign_in(text) from public, anon;
grant execute on function public.notify_sign_in(text) to authenticated;

-- ── Rental time ending: 3 days before, the day before, and on the day ──
create or replace function public.send_lease_reminders() returns integer
language plpgsql volatile security definer set search_path = '' as $$
declare
  today date := public.kampala_today();
  n integer;
begin
  insert into public.notifications (landlord_id, tenant_id, type, title, body, dedupe_key)
  select t.landlord_id, t.id, 'reminder', 'Rental time',
    case d.days_left
      when 0 then format('Your paid rental time for %s ends today. Pay now to continue: your next month runs on from today.', p.name)
      when 1 then format('Your paid rental time for %s ends tomorrow, %s. Pay before then to continue without a gap.', p.name, to_char(t.lease_end, 'FMDD Mon YYYY'))
      else format('Your paid rental time for %s ends in 3 days, on %s. Recharge any time: the new month is added on top.', p.name, to_char(t.lease_end, 'FMDD Mon YYYY'))
    end,
    format('lease_end:%s:%s', t.id, today)
  from public.tenants t
  join public.properties p on p.id = t.property_id
  cross join lateral (select (t.lease_end - today) as days_left) d
  where t.property_id is not null
    and t.user_id is not null
    and t.lease_end is not null
    and d.days_left in (0, 1, 3)
  on conflict (dedupe_key) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.send_lease_reminders() from public, anon, authenticated;

-- ── Overdue / rental time ended: once, then every 3 days, daytime only ──
create or replace function public.send_overdue_reminders() returns integer
language plpgsql volatile security definer set search_path = '' as $$
declare
  today date := public.kampala_today();
  v_hour integer := extract(hour from now() at time zone 'Africa/Kampala');
  n integer;
begin
  if v_hour < 8 or v_hour >= 20 then return 0; end if;

  insert into public.notifications (landlord_id, tenant_id, type, title, body)
  select t.landlord_id, t.id, 'rent_due', 'Rent reminder',
    case when o.amount > 0
      then format('%s for %s has been unpaid since %s. Please pay on the Payments page.',
             public.ugx(o.amount), p.name, to_char(o.since, 'FMDD Mon YYYY'))
      else format('Your paid rental time for %s ended on %s. Pay to continue: the new month runs on from %s.',
             p.name, to_char(t.lease_end, 'FMDD Mon YYYY'), to_char(t.lease_end, 'FMDD Mon')) end
  from public.tenants t
  join public.properties p on p.id = t.property_id
  cross join lateral (
    select coalesce(sum(amount - amount_paid), 0) as amount, min(due_date) as since
    from public.payments where tenant_id = t.id and status = 'pending' and due_date < today
  ) o
  where t.property_id is not null
    and t.user_id is not null
    and (o.amount > 0 or (t.lease_end is not null and t.lease_end < today))
    and not exists (
      select 1 from public.notifications x
      where x.tenant_id = t.id and x.type = 'rent_due' and x.created_at > now() - interval '71 hours'
    );
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.send_overdue_reminders() from public, anon, authenticated;

-- ── Calendar "new month started" notices: off ──
create or replace function public.send_month_start_notices() returns integer
language sql volatile security definer set search_path = '' as $$ select 0; $$;
revoke execute on function public.send_month_start_notices() from public, anon, authenticated;
do $$ begin
  perform cron.unschedule('renta-month-start-notices');
exception when others then null; end $$;

-- ── Welcome: truthful about when the rental time starts ──
create or replace function public.notify_tenant_connected() returns trigger
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_house text;
  v_landlord text;
  v_started boolean;
begin
  if new.user_id is null or new.property_id is null or old.user_id is not distinct from new.user_id then
    return new;
  end if;
  select name into v_house from public.properties where id = new.property_id;
  select nullif(full_name, '') into v_landlord from public.profiles where id = new.landlord_id;
  v_started := new.lease_end is not null;

  insert into public.notifications (landlord_id, tenant_id, type, title, body, dedupe_key)
  values (new.landlord_id, new.id, 'welcome', 'Account connected',
    format('Welcome! Your account is connected to %s%s. %s',
      coalesce(v_house, 'your rental'), coalesce(', managed by ' || v_landlord, ''),
      case when v_started then format('You are paid up to %s.', to_char(new.lease_end, 'FMDD Mon YYYY'))
           else 'Your rental time starts on the day you pay your first rent.' end),
    format('not_started:%s', new.id)) -- also covers the "not started" note, so it isn't sent twice
  on conflict (dedupe_key) do nothing;

  insert into public.staff_notifications (user_id, type, title, body, url)
  values (new.landlord_id, 'tenant', 'Tenant connected',
    format('%s has connected their Renta account for %s.', new.full_name, coalesce(v_house, 'their rental')),
    '/landlord/tenants');
  return new;
end $$;

-- ────────────── 32_admin_console.sql ──────────────

-- 32 · main admin console
-- The main admin can now change things across the whole platform, not just read them. Every change
-- goes through a function below that checks the caller is the main admin and writes an entry to the
-- activity log (admin_audit), so there is always a record of who changed what.
--   • admin_update_property(id, name, location, rent)
--   • admin_delete_property(id)                 only an empty property with no history
--   • admin_update_tenant(id, name, phone, email)
--   • admin_end_tenancy(id, reason)             history kept; tenant + landlord are told
--   • admin_broadcast(audience, landlord, message)  announcement to tenants / landlords / everyone
--   • admin_note(action, summary)               log something done elsewhere (e.g. on the server)
-- Safe to run more than once. No data is deleted.

create table if not exists public.admin_audit (
  id uuid primary key default gen_random_uuid(),
  actor uuid references auth.users (id) on delete set null,
  action text not null,
  target_type text,
  target_id uuid,
  summary text not null,
  created_at timestamptz not null default now()
);
create index if not exists admin_audit_created_idx on public.admin_audit (created_at desc);
alter table public.admin_audit enable row level security;
drop policy if exists "audit superadmin read" on public.admin_audit;
create policy "audit superadmin read" on public.admin_audit for select to authenticated using (public.is_superadmin());
revoke all on public.admin_audit from anon, authenticated;
grant select on public.admin_audit to authenticated;
grant all on public.admin_audit to service_role;
do $$ begin
  alter publication supabase_realtime add table public.admin_audit;
exception when duplicate_object then null; end $$;

-- ── Internal helpers ──
create or replace function public.admin_require() returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_superadmin() then raise exception 'Only the main admin can do this.'; end if;
end $$;
revoke execute on function public.admin_require() from public, anon, authenticated;

create or replace function public.admin_log(p_action text, p_type text, p_id uuid, p_summary text) returns void
language sql volatile security definer set search_path = '' as $$
  insert into public.admin_audit (actor, action, target_type, target_id, summary)
  values (auth.uid(), p_action, p_type, p_id, p_summary);
$$;
revoke execute on function public.admin_log(text, text, uuid, text) from public, anon, authenticated;

-- ── Properties ──
create or replace function public.admin_update_property(p_id uuid, p_name text, p_location text, p_rent bigint) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  old record;
  v_changes text[] := '{}';
begin
  perform public.admin_require();
  select * into old from public.properties where id = p_id for update;
  if not found then raise exception 'Property not found.'; end if;
  if nullif(trim(p_name), '') is null then raise exception 'Enter a name.'; end if;
  if p_rent is null or p_rent < 0 then raise exception 'Enter a valid monthly rent.'; end if;

  update public.properties
  set name = trim(p_name), location = coalesce(nullif(trim(p_location), ''), location), rent = p_rent
  where id = p_id;

  if old.name is distinct from trim(p_name) then v_changes := v_changes || format('name "%s" → "%s"', old.name, trim(p_name)); end if;
  if nullif(trim(p_location), '') is not null and old.location is distinct from trim(p_location) then
    v_changes := v_changes || format('location → %s', trim(p_location));
  end if;
  if old.rent is distinct from p_rent then v_changes := v_changes || format('rent %s → %s', public.ugx(old.rent), public.ugx(p_rent)); end if;

  if array_length(v_changes, 1) > 0 then
    perform public.admin_log('property.update', 'property', p_id, format('Edited %s: %s', trim(p_name), array_to_string(v_changes, ', ')));
    insert into public.staff_notifications (user_id, type, title, body, url)
    values (old.landlord_id, 'admin', 'Property updated by Renta UG',
      format('Renta UG updated %s: %s.', trim(p_name), array_to_string(v_changes, ', ')), '/landlord/properties');
  end if;
end $$;

create or replace function public.admin_delete_property(p_id uuid) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare p record;
begin
  perform public.admin_require();
  select * into p from public.properties where id = p_id;
  if not found then raise exception 'Property not found.'; end if;
  if exists (select 1 from public.tenants where property_id = p_id or last_property_id = p_id)
     or exists (select 1 from public.payments where property_id = p_id) then
    raise exception 'This property has tenants or payment history, so it cannot be deleted. Edit it instead.';
  end if;
  delete from public.properties where id = p_id;
  perform public.admin_log('property.delete', 'property', p_id, format('Deleted empty property %s', p.name));
  insert into public.staff_notifications (user_id, type, title, body, url)
  values (p.landlord_id, 'admin', 'Property removed by Renta UG', format('Renta UG removed the empty property %s from your account.', p.name), '/landlord/properties');
end $$;

-- ── Tenants ──
create or replace function public.admin_update_tenant(p_id uuid, p_name text, p_phone text, p_email text) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare old record;
begin
  perform public.admin_require();
  select * into old from public.tenants where id = p_id for update;
  if not found then raise exception 'Tenant not found.'; end if;
  if nullif(trim(p_name), '') is null then raise exception 'Enter a name.'; end if;
  update public.tenants
  set full_name = trim(p_name),
      phone = nullif(trim(p_phone), ''),
      email = coalesce(nullif(lower(trim(p_email)), ''), email)
  where id = p_id;
  perform public.admin_log('tenant.update', 'tenant', p_id,
    format('Edited tenant %s%s', trim(p_name), case when old.full_name <> trim(p_name) then format(' (was %s)', old.full_name) else '' end));
end $$;

create or replace function public.admin_end_tenancy(p_id uuid, p_reason text default null) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  t record;
  v_house text;
begin
  perform public.admin_require();
  select * into t from public.tenants where id = p_id for update;
  if not found then raise exception 'Tenant not found.'; end if;
  if t.property_id is null then raise exception 'This tenancy has already ended.'; end if;
  select name into v_house from public.properties where id = t.property_id;

  update public.tenants
  set last_property_id = property_id, property_id = null, ended_at = now(), connect_code = null, connect_code_expires_at = null
  where id = p_id;

  -- A waiting request to leave is now settled
  update public.move_out_requests
  set status = 'approved', decided_by = auth.uid(), decided_role = 'superadmin', decided_at = now(),
      decision_note = coalesce(nullif(trim(p_reason), ''), decision_note)
  where tenant_id = p_id and status = 'pending';

  insert into public.notifications (landlord_id, tenant_id, type, title, body)
  values (t.landlord_id, t.id, 'general', 'Tenancy ended',
    format('Your tenancy at %s has been ended by Renta UG%s. Your payment history is kept safely.',
      coalesce(v_house, 'your rental'), coalesce(': ' || nullif(trim(p_reason), ''), '')));
  insert into public.staff_notifications (user_id, type, title, body, url)
  values (t.landlord_id, 'admin', 'Tenancy ended by Renta UG',
    format('Renta UG ended %s''s tenancy at %s%s. The room is now vacant and their history is in Records.',
      t.full_name, coalesce(v_house, 'their rental'), coalesce(': ' || nullif(trim(p_reason), ''), '')),
    '/landlord/records');
  perform public.admin_log('tenant.end', 'tenant', p_id,
    format('Ended %s''s tenancy at %s%s', t.full_name, coalesce(v_house, 'their rental'), coalesce(' (' || nullif(trim(p_reason), '') || ')', '')));
end $$;

-- ── Announcements ──
-- p_audience: 'tenants' | 'landlords' | 'everyone'. p_landlord limits it to one landlord (and their tenants).
create or replace function public.admin_broadcast(p_audience text, p_landlord uuid, p_message text) returns integer
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_msg text := trim(coalesce(p_message, ''));
  n_t integer := 0;
  n_l integer := 0;
begin
  perform public.admin_require();
  if length(v_msg) < 3 then raise exception 'Write a message first.'; end if;
  if length(v_msg) > 1000 then raise exception 'Keep the message under 1,000 characters.'; end if;
  if p_audience not in ('tenants', 'landlords', 'everyone') then raise exception 'Choose who gets the message.'; end if;

  if p_audience in ('tenants', 'everyone') then
    insert into public.notifications (landlord_id, tenant_id, type, title, body)
    select t.landlord_id, t.id, 'general', 'From Renta UG', v_msg
    from public.tenants t
    where t.property_id is not null and t.user_id is not null
      and (p_landlord is null or t.landlord_id = p_landlord);
    get diagnostics n_t = row_count;
  end if;

  if p_audience in ('landlords', 'everyone') then
    insert into public.staff_notifications (user_id, type, title, body, url)
    select p.id, 'admin', 'From Renta UG', v_msg, '/landlord/inbox'
    from public.profiles p
    where p.role = 'landlord' and p.active and (p_landlord is null or p.id = p_landlord);
    get diagnostics n_l = row_count;
  end if;

  perform public.admin_log('broadcast', 'broadcast', p_landlord,
    format('Announcement to %s%s (%s tenant%s, %s landlord%s): %s',
      p_audience, case when p_landlord is not null then ' of one landlord' else '' end,
      n_t, case when n_t = 1 then '' else 's' end, n_l, case when n_l = 1 then '' else 's' end, left(v_msg, 300)));
  return n_t + n_l;
end $$;

-- ── Log an action done elsewhere (e.g. landlord registered / suspended through the server) ──
create or replace function public.admin_note(p_action text, p_type text, p_id uuid, p_summary text) returns void
language plpgsql volatile security definer set search_path = '' as $$
begin
  perform public.admin_require();
  perform public.admin_log(left(p_action, 60), left(p_type, 30), p_id, left(p_summary, 500));
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'admin_update_property(uuid, text, text, bigint)',
    'admin_delete_property(uuid)',
    'admin_update_tenant(uuid, text, text, text)',
    'admin_end_tenancy(uuid, text)',
    'admin_broadcast(text, uuid, text)',
    'admin_note(text, text, uuid, text)'
  ] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

-- ────────────── 33_landlord_owns_issues.sql ──────────────

-- 33 · landlord issues stay with the landlord
-- The main admin oversees the platform; day-to-day matters between a landlord and their tenants
-- are handled by the landlord alone:
--   • Cash the LANDLORD records counts straight away (they received it). No waiting for Renta UG.
--   • Cash a TENANT reports is confirmed or rejected by their landlord only.
--   • Requests to leave are approved or declined by the landlord only.
--   • The main admin is no longer sent cash or request-to-leave notifications. They can still SEE
--     everything (Activity, Transactions) and step in from the admin console if ever needed
--     (e.g. end a tenancy).
-- Safe to run more than once. No data is deleted.

-- ── Main admin is not notified about landlords' cash ──
create or replace function public.notify_admins(p_type text, p_title text, p_body text) returns void
language sql volatile security definer set search_path = '' as $$ select; $$;

-- ── Only the landlord reviews cash (including any old entries still waiting for Renta UG) ──
create or replace function public.can_review_cash(c public.cash_payments) returns text
language plpgsql stable security definer set search_path = '' as $$
begin
  if public.is_landlord() and c.landlord_id = auth.uid() then return 'landlord'; end if;
  raise exception 'Only the tenant''s landlord can confirm this payment.';
end $$;
revoke execute on function public.can_review_cash(public.cash_payments) from public, anon, authenticated;

-- ── Report / record cash ──
-- Landlord records cash → confirmed immediately (added to the tenant's rent, tenant told once).
-- Tenant reports cash  → their landlord is asked to confirm it.
create or replace function public.submit_cash_payment(
  p_tenant_id uuid,
  p_amount bigint,
  p_paid_on date default null,
  p_note text default null
) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  v_role text;
  v_tenant record;
  v_house text;
  v_rent bigint;
  v_outstanding bigint;
  v_pending bigint;
  v_paid_on date := coalesce(p_paid_on, public.kampala_today());
  v_id uuid;
begin
  select role into v_role from public.profiles where id = me;

  if v_role = 'tenant' then
    select * into v_tenant from public.tenants where id = coalesce(p_tenant_id, public.my_tenant_id()) and user_id = me;
    if not found or v_tenant.property_id is null then raise exception 'You are not connected to a house.'; end if;
  elsif public.is_landlord() then
    select * into v_tenant from public.tenants where id = p_tenant_id and landlord_id = me;
    if not found then raise exception 'Tenant not found.'; end if;
    if v_tenant.property_id is null then raise exception 'This tenant no longer rents from you.'; end if;
    v_role := 'landlord';
  else
    raise exception 'Only tenants and landlords can record cash payments.';
  end if;

  if p_amount is null or p_amount <= 0 then raise exception 'Enter an amount greater than zero.'; end if;
  if v_paid_on > public.kampala_today() then raise exception 'The payment date cannot be in the future.'; end if;

  select name, rent into v_house, v_rent from public.properties where id = v_tenant.property_id;
  v_outstanding := public.tenant_outstanding(v_tenant.id);
  select coalesce(sum(amount), 0) into v_pending from public.cash_payments where tenant_id = v_tenant.id and status = 'pending';

  if p_amount + v_pending > v_outstanding then
    if coalesce(v_rent, 0) <= 0 then
      raise exception 'This house has no monthly rent set, so cash beyond what is owed cannot be recorded.';
    end if;
    if p_amount + v_pending - v_outstanding > v_rent * 24 then
      raise exception '%', format('That pays more than 2 years ahead (rent is %s a month).', public.ugx(v_rent));
    end if;
  end if;

  insert into public.cash_payments (tenant_id, landlord_id, amount, paid_on, note, submitted_by, submitted_role)
  values (v_tenant.id, v_tenant.landlord_id, p_amount, v_paid_on, nullif(trim(p_note), ''), me, v_role)
  returning id into v_id;

  if v_role = 'tenant' then
    insert into public.staff_notifications (user_id, type, title, body, url)
    values (v_tenant.landlord_id, 'cash', 'Cash payment to confirm',
      format('%s says they paid you %s in cash on %s%s. Please confirm the amount you received.',
        v_tenant.full_name, public.ugx(p_amount), to_char(v_paid_on, 'FMDD Mon YYYY'), coalesce(' for ' || v_house, '')),
      '/landlord/payments');
  else
    perform public.confirm_cash_payment(v_id, null); -- the landlord received it: it counts now
  end if;

  return v_id;
end $$;

-- ── Tenant asks to leave: only their landlord is asked ──
create or replace function public.request_move_out(p_rating int, p_review text, p_reason text, p_details text default null)
returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  t record;
  v_house text;
  v_id uuid;
begin
  select * into t from public.tenants where user_id = me and property_id is not null;
  if not found then raise exception 'You are not renting a room right now.'; end if;
  if exists (select 1 from public.move_out_requests where tenant_id = t.id and status = 'pending') then
    raise exception 'You already have a request waiting for approval.';
  end if;
  if nullif(trim(p_reason), '') is null then raise exception 'Tell us why you are leaving.'; end if;
  if p_rating is not null and (p_rating < 1 or p_rating > 5) then raise exception 'Choose a rating from 1 to 5.'; end if;

  insert into public.move_out_requests (tenant_id, landlord_id, property_id, user_id, rating, review, reason, details)
  values (t.id, t.landlord_id, t.property_id, me, p_rating, nullif(trim(p_review), ''), trim(p_reason), nullif(trim(p_details), ''))
  returning id into v_id;

  select name into v_house from public.properties where id = t.property_id;
  insert into public.staff_notifications (user_id, type, title, body, url)
  values (t.landlord_id, 'move_out', 'Request to leave',
    format('%s has asked to leave %s. Reason: %s. Please review and approve or decline.', t.full_name, coalesce(v_house, 'their room'), trim(p_reason)),
    '/landlord/move-outs');
  return v_id;
end $$;

-- ── Landlord approves or declines (their own tenants only) ──
create or replace function public.decide_move_out(p_id uuid, p_approve boolean, p_note text default null) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  r public.move_out_requests;
  t record;
  v_house text;
begin
  select * into r from public.move_out_requests where id = p_id for update;
  if not found then raise exception 'Request not found.'; end if;
  if r.status <> 'pending' then raise exception 'This request has already been %.', r.status; end if;
  if not (public.is_landlord() and r.landlord_id = auth.uid()) then
    raise exception 'Only the tenant''s landlord can decide on this request.';
  end if;

  select * into t from public.tenants where id = r.tenant_id;
  select name into v_house from public.properties where id = coalesce(t.property_id, r.property_id);

  update public.move_out_requests
  set status = case when p_approve then 'approved' else 'declined' end,
      decided_by = auth.uid(), decided_role = 'landlord', decided_at = now(), decision_note = nullif(trim(p_note), '')
  where id = r.id;

  if p_approve then
    if t.property_id is not null then
      update public.tenants
      set last_property_id = property_id, property_id = null, ended_at = now(), connect_code = null, connect_code_expires_at = null
      where id = t.id;
    end if;
    insert into public.notifications (landlord_id, tenant_id, type, title, body)
    values (r.landlord_id, r.tenant_id, 'general', 'Move-out approved',
      format('Your request to leave %s has been approved. Thank you for staying with us. Your payment history is kept safely.', coalesce(v_house, 'your room')));
  else
    insert into public.notifications (landlord_id, tenant_id, type, title, body)
    values (r.landlord_id, r.tenant_id, 'general', 'Move-out request declined',
      format('Your request to leave %s was not approved%s. Please talk to your landlord.', coalesce(v_house, 'your room'), coalesce(': ' || nullif(trim(p_note), ''), '')));
  end if;
end $$;

-- Old main-admin inbox items about landlords' cash and requests to leave: mark as read
update public.staff_notifications s set read = true
from public.profiles p
where p.id = s.user_id and p.role = 'superadmin' and s.type in ('cash', 'move_out') and not s.read;

revoke execute on function public.submit_cash_payment(uuid, bigint, date, text) from public, anon;
revoke execute on function public.request_move_out(int, text, text, text) from public, anon;
revoke execute on function public.decide_move_out(uuid, boolean, text) from public, anon;
grant execute on function public.submit_cash_payment(uuid, bigint, date, text) to authenticated;
grant execute on function public.request_move_out(int, text, text, text) to authenticated;
grant execute on function public.decide_move_out(uuid, boolean, text) to authenticated;

-- ────────────── 34_archive_and_clear.sql ──────────────

-- 34 · archive & clear the platform
-- The main admin can wipe every landlord and tenant from Renta UG in one go (e.g. to start fresh).
-- BEFORE anything is deleted, a full copy of everything they ever entered is saved in
-- platform_archives. Only the main admin can read the archive (Health & settings → Archives).
--
-- Kept:    the main admin account, the activity log (admin_audit), the archives themselves.
-- Deleted: landlord + tenant accounts and profiles, properties, rentals, tenant records, rent
--          months, payments, receipts, cash, mobile money attempts, requests to leave,
--          notifications, inbox messages and phones registered for notifications.
--
-- admin_archive_and_clear() can only be run by the server (service role). The server checks the
-- caller is the main admin, runs it, then deletes the login accounts it returns.
-- Safe to run this file more than once.

create table if not exists public.platform_archives (
  id uuid primary key default gen_random_uuid(),
  created_by uuid references auth.users (id) on delete set null,
  note text,
  counts jsonb not null default '{}'::jsonb,
  data jsonb not null,
  created_at timestamptz not null default now()
);
alter table public.platform_archives enable row level security;
drop policy if exists "archives superadmin read" on public.platform_archives;
create policy "archives superadmin read" on public.platform_archives for select to authenticated using (public.is_superadmin());
revoke all on public.platform_archives from anon, authenticated;
grant select on public.platform_archives to authenticated;
grant all on public.platform_archives to service_role;

create or replace function public.admin_archive_and_clear(p_actor uuid, p_note text default null) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_users uuid[];
  v_data jsonb;
  v_counts jsonb;
  v_id uuid;
begin
  if not exists (select 1 from public.profiles where id = p_actor and role = 'superadmin') then
    raise exception 'Only the main admin can do this.';
  end if;

  select coalesce(array_agg(id), '{}') into v_users from public.profiles where role in ('landlord', 'tenant');

  -- 1. Full copy of everything
  v_data := jsonb_build_object(
    'landlords',         coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.profiles x where x.role = 'landlord'), '[]'),
    'tenant_accounts',   coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.profiles x where x.role = 'tenant'), '[]'),
    'rentals',           coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.rentals x), '[]'),
    'properties',        coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.properties x), '[]'),
    'tenants',           coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.tenants x), '[]'),
    'payments',          coalesce((select jsonb_agg(to_jsonb(x) order by x.period) from public.payments x), '[]'),
    'payment_receipts',  coalesce((select jsonb_agg(to_jsonb(x) order by x.received_at) from public.payment_receipts x), '[]'),
    'cash_payments',     coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.cash_payments x), '[]'),
    'momo_attempts',     coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.momo_attempts x), '[]'),
    'move_out_requests', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.move_out_requests x), '[]'),
    'notifications',     coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.notifications x), '[]'),
    'inbox',             coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.staff_notifications x where x.user_id = any (v_users)), '[]')
  );
  select jsonb_object_agg(k, jsonb_array_length(v)) into v_counts from jsonb_each(v_data) as e(k, v);
  v_counts := v_counts || jsonb_build_object('collected', coalesce((select sum(amount_paid) from public.payments), 0));

  insert into public.platform_archives (created_by, note, counts, data)
  values (p_actor, nullif(trim(p_note), ''), v_counts, v_data)
  returning id into v_id;

  -- 2. Clear (children first)
  delete from public.notifications where true;
  delete from public.payment_receipts where true;
  delete from public.cash_payments where true;
  delete from public.momo_attempts where true;
  delete from public.move_out_requests where true;
  delete from public.payments where true;
  delete from public.tenants where true;
  delete from public.properties where true;
  delete from public.rentals where true;
  delete from public.staff_notifications where user_id = any (v_users);
  delete from public.push_subscriptions where user_id = any (v_users);
  delete from public.profiles where id = any (v_users);

  insert into public.admin_audit (actor, action, target_type, target_id, summary)
  values (p_actor, 'platform.clear', 'archive', v_id,
    format('Archived and cleared the platform: %s landlords, %s tenant accounts, %s properties, %s tenant records, %s payments',
      v_counts ->> 'landlords', v_counts ->> 'tenant_accounts', v_counts ->> 'properties', v_counts ->> 'tenants', v_counts ->> 'payment_receipts'));

  return jsonb_build_object('archive_id', v_id, 'counts', v_counts, 'user_ids', to_jsonb(v_users));
end $$;

revoke execute on function public.admin_archive_and_clear(uuid, text) from public, anon, authenticated;
grant execute on function public.admin_archive_and_clear(uuid, text) to service_role;

-- ────────────── 35_consistency.sql ──────────────

-- 35 · keep the numbers in agreement
-- Every amount paid on a rent month must have a matching payment record (payment_receipts), because
-- Transactions, the admin statistics and the landlord reports add up the records. Older payments made
-- before payment records existed are filled in here with the method, reference and date the rent month
-- already has. Only the missing difference is added, so running this again changes nothing.
-- Safe to run more than once. No data is deleted.

insert into public.payment_receipts (payment_id, tenant_id, landlord_id, amount, method, reference, note, received_at)
select p.id, p.tenant_id, p.landlord_id,
       p.amount_paid - coalesce(r.total, 0),
       coalesce(nullif(p.method, ''), 'Payment'),
       p.reference,
       'Recorded before payment records existed',
       coalesce(p.paid_at, p.created_at, now())
from public.payments p
left join (select payment_id, sum(amount) as total from public.payment_receipts group by payment_id) r on r.payment_id = p.id
where p.amount_paid > coalesce(r.total, 0);

-- ────────────── 36_part_payments.sql ──────────────

-- 36 · part payments: a month starts counting once at least 60% of its rent is paid
--
--  • A tenant can pay part of what they owe (not less than 60%). The rest stays as their balance due.
--  • Rental time grows by one month the moment a month's rent reaches 60% paid (or is fully paid in
--    one go). Paying the remaining 40% later does not add another month.
--  • A new tenant starts with no rental time; it starts on the day of their first qualifying payment.
--
-- Safe to run more than once. No data is deleted.

create or replace function public.extend_rental_time() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_day date := (coalesce(new.paid_at, now()) at time zone 'Africa/Kampala')::date;
  v_now_ok boolean;
  v_was_ok boolean := false;
begin
  v_now_ok := new.status = 'paid' or (new.amount > 0 and new.amount_paid * 10 >= new.amount * 6);
  if tg_op = 'UPDATE' then
    v_was_ok := old.status = 'paid' or (old.amount > 0 and old.amount_paid * 10 >= old.amount * 6);
  end if;
  if not v_now_ok or v_was_ok then
    return new;
  end if;
  update public.tenants
  set lease_start = coalesce(lease_start, v_day),
      lease_end = (coalesce(lease_end, v_day) + interval '1 month')::date
  where id = new.tenant_id and property_id is not null;
  return new;
end $$;

drop trigger if exists payments_extend_rental_time on public.payments;
create trigger payments_extend_rental_time
  after insert or update of status, amount_paid on public.payments
  for each row execute function public.extend_rental_time();

-- One-time catch-up: tenants with no rental time yet who already have a month at 60%+ paid
update public.tenants t
set lease_start = s.start_day,
    lease_end = (s.start_day + make_interval(months => s.months))::date
from (
  select p.tenant_id,
         min((coalesce(p.paid_at, p.created_at) at time zone 'Africa/Kampala')::date) as start_day,
         count(*)::int as months
  from public.payments p
  where p.amount > 0 and (p.status = 'paid' or p.amount_paid * 10 >= p.amount * 6)
  group by p.tenant_id
) s
where t.id = s.tenant_id and t.property_id is not null and t.lease_end is null;

-- ────────────── 37_email_verification.sql ──────────────

-- 37 · email verification codes for new sign-ups
--
-- A new person fills in the sign-up form; the server emails them a 6-character code (letters and
-- numbers) that works for 20 minutes. The account is only created once the right code is entered, so
-- nobody can register with an email they don't own. This table holds the waiting sign-ups.
--
-- It is only ever read and written by the server (service role). Nobody can read it from the app.
-- Safe to run more than once.

create table if not exists public.email_verifications (
  email text primary key,
  full_name text not null,
  password_enc text not null, -- encrypted by the server; removed as soon as the account is created
  code_hash text not null,
  expires_at timestamptz not null,
  attempts int not null default 0,
  sent_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table public.email_verifications enable row level security; -- no policies = closed to the app
revoke all on public.email_verifications from public, anon, authenticated;

-- Tidy up expired sign-ups every hour (pg_cron is already used for the reminders)
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'renta-clean-email-verifications';
    perform cron.schedule('renta-clean-email-verifications', '17 * * * *',
      $job$delete from public.email_verifications where expires_at < now() - interval '1 hour'$job$);
  end if;
exception when others then
  null; -- cleaning up is optional: the server also removes expired rows itself
end $$;

-- ────────────── 39_sms_confirmations.sql ──────────────

-- 39 · text messages (SMS) when a landlord confirms a cash payment
-- The server texts the tenant the same message the app shows (tenants with or without a smartphone). These columns remember which notifications were already texted, so nobody
-- gets the same SMS twice. Run once in Supabase → SQL Editor. Safe to run more than once.

alter table public.notifications add column if not exists sms_sent_at timestamptz;
alter table public.notifications add column if not exists sms_error text;

-- Don't text old payment messages when SMS is first switched on
update public.notifications set sms_sent_at = coalesce(sms_sent_at, created_at)
where sms_sent_at is null and type = 'payment';

-- ────────────── 40_app_installs.sql ──────────────

-- 40 · live app install counts (replaces the typed-in downloads of 38)
-- Each phone that opens the Google Play app or the App Store app registers itself ONCE (a random device code, no personal details). The main admin's
-- Downloads page counts these rows live, so nobody types numbers in any more.
-- Run once in Supabase → SQL Editor. Safe to run more than once.

create table if not exists public.app_installs (
  device_id text primary key,
  platform text not null check (platform in ('android', 'ios')),
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now()
);
create index if not exists app_installs_platform_idx on public.app_installs (platform);

alter table public.app_installs enable row level security;
drop policy if exists "installs superadmin read" on public.app_installs;
create policy "installs superadmin read" on public.app_installs for select to authenticated using (public.is_superadmin());

-- Nobody writes to the table directly; phones call register_install below
revoke all on public.app_installs from public, anon, authenticated;
grant select on public.app_installs to authenticated;
grant all on public.app_installs to service_role;

create or replace function public.register_install(p_device text, p_platform text) returns void
language plpgsql volatile security definer set search_path = '' as $$
begin
  if p_platform not in ('android', 'ios') or p_device is null or length(p_device) not between 16 and 64 then
    return;
  end if;
  insert into public.app_installs (device_id, platform) values (p_device, p_platform)
  on conflict (device_id) do update set last_seen = now();
end $$;

revoke execute on function public.register_install(text, text) from public;
grant execute on function public.register_install(text, text) to anon, authenticated;

do $$ begin
  alter publication supabase_realtime add table public.app_installs;
exception when duplicate_object then null; end $$;

-- Home-screen (web) installs are not counted any more
delete from public.app_installs where platform = 'web';

-- The old typed-in table is no longer used
drop table if exists public.app_downloads;

-- ────────────── 41_manual_mobile_money.sql ──────────────

-- 41 · mobile money sent straight to the landlord + rent cycles + error reports + health checks
--
--  Mobile money (no payment company in between)
--   • Each landlord adds the numbers they receive money on (MTN, Airtel) with the
--     registered name the network shows: landlord_pay_accounts.
--   • Every tenant gets their own one-word payment reason (tenants.pay_code, e.g. JOHN427). They type
--     it as the "reason" when they send money, so the landlord can match the payment.
--   • The tenant sends the money with their phone, then taps "I've paid". That creates a payment
--     WAITING FOR THE LANDLORD (cash_payments, method = 'mobile_money'). The tenant is told it is
--     being reviewed. When the landlord confirms, it counts exactly like cash: unpaid rent first,
--     then months ahead, saved as "Mobile money".
--   • A landlord can also record mobile money for a tenant without a smartphone: it counts at once.
--
--  Rent cycles
--   • The landlord chooses the date of the FIRST payment: the tenant's first month starts that day.
--   • After that, each month runs on from the day the last one ended. Days after the end that are not
--     paid for are "debt days": they are taken from the next month (the next month still ends one
--     month after the old end), and the tenant is told so when the payment is confirmed.
--
--  Error reports + health checks (main admin)
--   • error_reports: errors from any page or the server, grouped (same error = one row + a count).
--   • health_checks: the server checks every part of the system every 20 minutes and keeps the result.
--
-- Safe to run more than once. No data is deleted.

-- ── Landlord receiving numbers ──
create table if not exists public.landlord_pay_accounts (
  id uuid primary key default gen_random_uuid(),
  landlord_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  network text not null,
  phone text not null,
  account_name text not null,
  dial_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (landlord_id, network)
);
alter table public.landlord_pay_accounts enable row level security;

-- Only MTN and Airtel (Lycamobile was removed; drops any Lyca number saved by an earlier version)
delete from public.landlord_pay_accounts where network not in ('mtn', 'airtel');
alter table public.landlord_pay_accounts drop constraint if exists landlord_pay_accounts_network_check;
alter table public.landlord_pay_accounts add constraint landlord_pay_accounts_network_check check (network in ('mtn', 'airtel'));

drop policy if exists "pay accounts landlord" on public.landlord_pay_accounts;
drop policy if exists "pay accounts tenant read" on public.landlord_pay_accounts;
drop policy if exists "pay accounts admin read" on public.landlord_pay_accounts;
create policy "pay accounts landlord" on public.landlord_pay_accounts for all to authenticated
  using (public.is_landlord() and landlord_id = auth.uid())
  with check (public.is_landlord() and landlord_id = auth.uid());
create policy "pay accounts tenant read" on public.landlord_pay_accounts for select to authenticated
  using (landlord_id = public.my_landlord_id());
create policy "pay accounts admin read" on public.landlord_pay_accounts for select to authenticated
  using (public.is_superadmin());

revoke all on public.landlord_pay_accounts from anon;
grant select, insert, update, delete on public.landlord_pay_accounts to authenticated;
grant all on public.landlord_pay_accounts to service_role;

do $$ begin
  alter publication supabase_realtime add table public.landlord_pay_accounts;
exception when duplicate_object then null; end $$;

-- ── One payment word per tenant ──
alter table public.tenants add column if not exists pay_code text;
create unique index if not exists tenants_pay_code_key on public.tenants (pay_code) where pay_code is not null;

create or replace function public.new_pay_code(p_name text) returns text
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_base text := upper(left(regexp_replace(split_part(trim(coalesce(p_name, '')), ' ', 1), '[^A-Za-z]', '', 'g'), 6));
  v_code text;
begin
  if length(v_base) < 2 then v_base := 'RENT'; end if;
  loop
    v_code := v_base || (100 + floor(random() * 900))::int;
    exit when not exists (select 1 from public.tenants where pay_code = v_code);
  end loop;
  return v_code;
end $$;
revoke execute on function public.new_pay_code(text) from public, anon, authenticated;

create or replace function public.set_tenant_pay_code() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.pay_code is null then new.pay_code := public.new_pay_code(new.full_name); end if;
  return new;
end $$;
drop trigger if exists tenants_pay_code on public.tenants;
create trigger tenants_pay_code before insert on public.tenants
  for each row execute function public.set_tenant_pay_code();

-- Existing tenants: one at a time, so every word stays unique
do $$
declare r record;
begin
  for r in select id, full_name from public.tenants where pay_code is null loop
    update public.tenants set pay_code = public.new_pay_code(r.full_name) where id = r.id;
  end loop;
end $$;

-- ── Payments waiting for the landlord: cash OR mobile money ──
alter table public.cash_payments add column if not exists method text not null default 'cash';
alter table public.cash_payments add column if not exists network text;
do $$ begin
  alter table public.cash_payments add constraint cash_payments_method_check check (method in ('cash', 'mobile_money'));
exception when duplicate_object then null; end $$;

-- ── Rental time: the first month starts on the date the landlord chose ──
create or replace function public.extend_rental_time() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_day date := (coalesce(new.paid_at, now()) at time zone 'Africa/Kampala')::date;
  v_now_ok boolean;
  v_was_ok boolean := false;
begin
  v_now_ok := new.status = 'paid' or (new.amount > 0 and new.amount_paid * 10 >= new.amount * 6);
  if tg_op = 'UPDATE' then
    v_was_ok := old.status = 'paid' or (old.amount > 0 and old.amount_paid * 10 >= old.amount * 6);
  end if;
  if not v_now_ok or v_was_ok then
    return new;
  end if;
  -- New tenant: from their start date (chosen by the landlord). Otherwise straight on from the old end,
  -- so late (debt) days are not given back.
  update public.tenants
  set lease_start = coalesce(lease_start, v_day),
      lease_end = (coalesce(lease_end, lease_start, v_day) + interval '1 month')::date
  where id = new.tenant_id and property_id is not null;
  return new;
end $$;

-- ── Report / record a payment (cash or mobile money) ──
-- Tenant: reports it → their landlord confirms. Landlord: records it → it counts straight away.
create or replace function public.submit_payment(
  p_tenant_id uuid,
  p_amount bigint,
  p_paid_on date default null,
  p_note text default null,
  p_method text default 'cash',
  p_network text default null
) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  v_role text;
  v_tenant record;
  v_house text;
  v_rent bigint;
  v_outstanding bigint;
  v_pending bigint;
  v_paid_on date := coalesce(p_paid_on, public.kampala_today());
  v_method text := coalesce(nullif(p_method, ''), 'cash');
  v_network text := nullif(lower(p_network), '');
  v_net_label text;
  v_id uuid;
begin
  if v_method not in ('cash', 'mobile_money') then raise exception 'Choose cash or mobile money.'; end if;
  if v_method = 'mobile_money' and v_network is not null and v_network not in ('mtn', 'airtel') then
    raise exception 'Choose MTN or Airtel.';
  end if;
  v_net_label := case v_network when 'mtn' then 'MTN' when 'airtel' then 'Airtel' end;

  select role into v_role from public.profiles where id = me;
  if v_role = 'tenant' then
    select * into v_tenant from public.tenants where id = coalesce(p_tenant_id, public.my_tenant_id()) and user_id = me;
    if not found or v_tenant.property_id is null then raise exception 'You are not connected to a house.'; end if;
    if (select count(*) from public.cash_payments where tenant_id = v_tenant.id and status = 'pending') >= 3 then
      raise exception 'You already have payments waiting for your landlord. Wait for them to be checked first.';
    end if;
    if v_method = 'mobile_money' and not exists (
      select 1 from public.landlord_pay_accounts where landlord_id = v_tenant.landlord_id and network = v_network
    ) then
      raise exception 'Your landlord has not added a number for this network.';
    end if;
  elsif public.is_landlord() then
    select * into v_tenant from public.tenants where id = p_tenant_id and landlord_id = me;
    if not found then raise exception 'Tenant not found.'; end if;
    if v_tenant.property_id is null then raise exception 'This tenant no longer rents from you.'; end if;
    v_role := 'landlord';
  else
    raise exception 'Only tenants and landlords can record payments.';
  end if;

  if p_amount is null or p_amount <= 0 then raise exception 'Enter an amount greater than zero.'; end if;
  if v_paid_on > public.kampala_today() then raise exception 'The payment date cannot be in the future.'; end if;
  if v_paid_on < public.kampala_today() - 366 then raise exception 'The payment date is more than a year ago.'; end if;

  select name, rent into v_house, v_rent from public.properties where id = v_tenant.property_id;
  v_outstanding := public.tenant_outstanding(v_tenant.id);
  select coalesce(sum(amount), 0) into v_pending from public.cash_payments where tenant_id = v_tenant.id and status = 'pending';

  if p_amount + v_pending > v_outstanding then
    if coalesce(v_rent, 0) <= 0 then
      raise exception 'This house has no monthly rent set, so money beyond what is owed cannot be recorded.';
    end if;
    if p_amount + v_pending - v_outstanding > v_rent * 24 then
      raise exception '%', format('That pays more than 2 years ahead (rent is %s a month).', public.ugx(v_rent));
    end if;
  end if;

  insert into public.cash_payments (tenant_id, landlord_id, amount, paid_on, note, submitted_by, submitted_role, method, network)
  values (v_tenant.id, v_tenant.landlord_id, p_amount, v_paid_on, nullif(trim(p_note), ''), me, v_role, v_method, v_network)
  returning id into v_id;

  if v_role = 'tenant' then
    if v_method = 'mobile_money' then
      insert into public.staff_notifications (user_id, type, title, body, url)
      values (v_tenant.landlord_id, 'cash', 'Mobile money to confirm',
        format('%s says they sent you %s on %s with the reason %s%s. Check your phone, then confirm it.',
          v_tenant.full_name, public.ugx(p_amount), coalesce(v_net_label, 'mobile money'), coalesce(v_tenant.pay_code, '—'),
          coalesce(' (' || v_house || ')', '')),
        '/landlord/payments');
      insert into public.notifications (landlord_id, tenant_id, type, title, body)
      values (v_tenant.landlord_id, v_tenant.id, 'payment', 'Payment being reviewed',
        format('We received your %s payment of %s. Your landlord is checking it and your rent will be updated soon.',
          coalesce(v_net_label, 'mobile money'), public.ugx(p_amount)));
    else
      insert into public.staff_notifications (user_id, type, title, body, url)
      values (v_tenant.landlord_id, 'cash', 'Cash payment to confirm',
        format('%s says they paid you %s in cash on %s%s. Please confirm the amount you received.',
          v_tenant.full_name, public.ugx(p_amount), to_char(v_paid_on, 'FMDD Mon YYYY'), coalesce(' for ' || v_house, '')),
        '/landlord/payments');
    end if;
  else
    perform public.confirm_cash_payment(v_id, null); -- the landlord received it: it counts now
  end if;

  return v_id;
end $$;

-- Older app versions call this name: cash only
create or replace function public.submit_cash_payment(
  p_tenant_id uuid,
  p_amount bigint,
  p_paid_on date default null,
  p_note text default null
) returns uuid
language sql volatile security definer set search_path = '' as $$
  select public.submit_payment(p_tenant_id, p_amount, p_paid_on, p_note, 'cash', null);
$$;

-- ── Confirm: unpaid rent first, then months ahead. Tells the tenant about debt days. ──
create or replace function public.confirm_cash_payment(p_id uuid, p_amount bigint default null) returns json
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  c public.cash_payments;
  v_reviewer text;
  v_amount bigint;
  v_left bigint;
  v_take bigint;
  v_completed text[] := '{}';
  v_ahead int := 0;
  v_balance_after bigint;
  v_tenant record;
  v_rent bigint;
  v_period text;
  v_charge uuid;
  v_label text;
  v_paid_at timestamptz;
  v_old_end date;
  v_new_end date;
  v_debt int := 0;
  v_days int;
  r record;
begin
  select * into c from public.cash_payments where id = p_id for update;
  if not found then raise exception 'Payment not found.'; end if;
  if c.status <> 'pending' then raise exception 'This payment has already been %.', c.status; end if;
  v_reviewer := public.can_review_cash(c);

  v_amount := coalesce(p_amount, c.amount);
  if v_amount <= 0 then raise exception 'Enter an amount greater than zero.'; end if;
  -- Saved on the receipt and the rent month: "MTN Mobile Money", "Airtel Money" or "Cash"
  v_label := case when c.method = 'mobile_money'
    then case c.network when 'mtn' then 'MTN Mobile Money' when 'airtel' then 'Airtel Money' else 'Mobile money' end
    else 'Cash' end;
  v_paid_at := c.paid_on::timestamptz + interval '12 hours';

  select * into v_tenant from public.tenants where id = c.tenant_id;
  select rent into v_rent from public.properties where id = v_tenant.property_id;
  if v_amount > public.tenant_outstanding(c.tenant_id) then
    if v_tenant.property_id is null or coalesce(v_rent, 0) <= 0 then
      raise exception 'That is more than the unpaid rent of %, and there is no monthly rent to pay ahead.', public.ugx(public.tenant_outstanding(c.tenant_id));
    end if;
    if v_amount - public.tenant_outstanding(c.tenant_id) > v_rent * 24 then
      raise exception 'That pays more than 2 years ahead.';
    end if;
  end if;

  -- First payment: the tenant's first month starts on the day it was paid (chosen by the landlord)
  v_old_end := v_tenant.lease_end;
  if v_old_end is null and v_tenant.property_id is not null then
    update public.tenants set lease_start = c.paid_on where id = c.tenant_id;
  end if;

  v_left := v_amount;

  -- 1. Unpaid rent, oldest first
  for r in
    select * from public.payments
    where tenant_id = c.tenant_id and status = 'pending'
    order by due_date, period
    for update
  loop
    exit when v_left <= 0;
    v_take := least(v_left, r.amount - r.amount_paid);
    v_left := v_left - v_take;

    insert into public.payment_receipts (payment_id, tenant_id, landlord_id, amount, method, note, received_at, recorded_by)
    values (r.id, c.tenant_id, c.landlord_id, v_take, v_label, c.note, v_paid_at, me);

    update public.payments
    set amount_paid = amount_paid + v_take,
        status = case when amount_paid + v_take >= amount then 'paid' else 'pending' end,
        paid_at = case when amount_paid + v_take >= amount then v_paid_at else paid_at end,
        method = v_label
    where id = r.id;

    if r.amount_paid + v_take >= r.amount then
      v_completed := v_completed || to_char(to_date(r.period || '-01', 'YYYY-MM-DD'), 'FMMonth YYYY');
    end if;
  end loop;

  -- 2. Whatever is left pays the next months ahead
  while v_left > 0 loop
    v_period := public.next_rent_period(c.tenant_id);
    v_take := least(v_left, v_rent);

    insert into public.payments (landlord_id, tenant_id, property_id, period, amount, amount_paid, due_date, status, paid_at, method)
    values (
      c.landlord_id, c.tenant_id, v_tenant.property_id, v_period, v_rent, v_take,
      to_date(v_period || '-05', 'YYYY-MM-DD'),
      case when v_take >= v_rent then 'paid' else 'pending' end,
      case when v_take >= v_rent then v_paid_at end,
      v_label)
    returning id into v_charge;

    insert into public.payment_receipts (payment_id, tenant_id, landlord_id, amount, method, note, received_at, recorded_by)
    values (v_charge, c.tenant_id, c.landlord_id, v_take, v_label, c.note, v_paid_at, me);

    if v_take >= v_rent then
      v_completed := v_completed || to_char(to_date(v_period || '-01', 'YYYY-MM-DD'), 'FMMonth YYYY');
    end if;
    v_left := v_left - v_take;
  end loop;

  update public.cash_payments
  set status = 'confirmed', confirmed_amount = v_amount, reviewed_by = me, reviewed_role = v_reviewer, reviewed_at = now()
  where id = c.id;

  v_balance_after := public.tenant_outstanding(c.tenant_id);
  select lease_end into v_new_end from public.tenants where id = c.tenant_id;
  if v_old_end is not null and c.paid_on > v_old_end then
    v_debt := c.paid_on - v_old_end;
  end if;
  if v_new_end is not null then
    v_days := v_new_end - greatest(c.paid_on, coalesce(v_old_end, c.paid_on));
    -- Whole months paid beyond the month running today (from the real rent cycle, not calendar months)
    if v_new_end is distinct from v_old_end then
      select (extract(year from a) * 12 + extract(month from a))::int into v_ahead
      from (select age(v_new_end, public.kampala_today()) as a) x;
      v_ahead := greatest(0, v_ahead);
    end if;
  end if;

  -- Tenant (also sent by SMS when SMS is switched on)
  insert into public.notifications (landlord_id, tenant_id, type, title, body)
  values (c.landlord_id, c.tenant_id, 'payment', 'Payment confirmation',
    format('Your %s payment of %s made on %s has been successfully received and confirmed by %s%s.%s%s%s %s',
      case when c.method = 'mobile_money' then 'mobile money' else 'cash' end,
      public.ugx(v_amount),
      to_char(c.paid_on, 'FMDD Mon YYYY'),
      case when v_reviewer = 'superadmin' then 'Renta UG' else 'your landlord' end,
      case when v_amount <> c.amount then format(' (you reported %s)', public.ugx(c.amount)) else '' end,
      case when v_debt > 0 and v_new_end is distinct from v_old_end then format(' You paid %s day%s late: those debt days were taken from your new month.',
        v_debt, case when v_debt = 1 then '' else 's' end) else '' end,
      case when v_new_end is not null and v_new_end is distinct from v_old_end
        then format(' Your rent now runs to %s.', to_char(v_new_end, 'FMDD Mon YYYY')) else '' end,
      case when v_ahead > 0 then format(' That includes %s month%s paid ahead.', v_ahead, case when v_ahead = 1 then '' else 's' end) else '' end,
      case when v_balance_after = 0 then 'You have no outstanding balance. Thank you.'
           else format('Outstanding balance: %s.', public.ugx(v_balance_after)) end));

  return json_build_object(
    'applied', v_amount, 'balance_after', v_balance_after, 'completed', array_to_json(v_completed),
    'months_ahead', v_ahead, 'debt_days', v_debt, 'paid_to', v_new_end, 'days', v_days);
end $$;

-- ── Reject ──
create or replace function public.reject_cash_payment(p_id uuid, p_reason text default null) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  c public.cash_payments;
  v_reviewer text;
  v_reason text := nullif(trim(p_reason), '');
begin
  select * into c from public.cash_payments where id = p_id for update;
  if not found then raise exception 'Payment not found.'; end if;
  if c.status <> 'pending' then raise exception 'This payment has already been %.', c.status; end if;
  v_reviewer := public.can_review_cash(c);

  update public.cash_payments
  set status = 'rejected', reject_reason = v_reason, reviewed_by = me, reviewed_role = v_reviewer, reviewed_at = now()
  where id = c.id;

  insert into public.notifications (landlord_id, tenant_id, type, title, body)
  values (c.landlord_id, c.tenant_id, 'payment', 'Payment not confirmed',
    format('Your %s payment of %s from %s could not be confirmed by your landlord%s. Please contact them.',
      case when c.method = 'mobile_money' then 'mobile money' else 'cash' end,
      public.ugx(c.amount), to_char(c.paid_on, 'FMDD Mon YYYY'), coalesce(': ' || v_reason, '')));
end $$;

revoke execute on function public.submit_payment(uuid, bigint, date, text, text, text) from public, anon;
revoke execute on function public.submit_cash_payment(uuid, bigint, date, text) from public, anon;
revoke execute on function public.confirm_cash_payment(uuid, bigint) from public, anon;
revoke execute on function public.reject_cash_payment(uuid, text) from public, anon;
grant execute on function public.submit_payment(uuid, bigint, date, text, text, text) to authenticated;
grant execute on function public.submit_cash_payment(uuid, bigint, date, text) to authenticated;
grant execute on function public.confirm_cash_payment(uuid, bigint) to authenticated;
grant execute on function public.reject_cash_payment(uuid, text) to authenticated;

-- ── Overdue reminder: same timing as 31 (once, then every 3 days, 08:00–20:00), wording about debt days ──
create or replace function public.send_overdue_reminders() returns integer
language plpgsql volatile security definer set search_path = '' as $$
declare
  today date := public.kampala_today();
  v_hour integer := extract(hour from now() at time zone 'Africa/Kampala');
  n integer;
begin
  if v_hour < 8 or v_hour >= 20 then return 0; end if;

  insert into public.notifications (landlord_id, tenant_id, type, title, body)
  select t.landlord_id, t.id, 'rent_due', 'Rent reminder',
    case when o.amount > 0
      then format('%s for %s has been unpaid since %s. Please pay on the Payments page.',
             public.ugx(o.amount::bigint), p.name, to_char(o.since, 'FMDD Mon YYYY'))
      else format('Your rent month for %s ended on %s. You now have %s debt day%s: they will be taken from your next month, which still runs from %s. Please pay soon.',
             p.name, to_char(t.lease_end, 'FMDD Mon YYYY'), today - t.lease_end,
             case when today - t.lease_end = 1 then '' else 's' end, to_char(t.lease_end, 'FMDD Mon')) end
  from public.tenants t
  join public.properties p on p.id = t.property_id
  cross join lateral (
    select coalesce(sum(amount - amount_paid), 0) as amount, min(due_date) as since
    from public.payments where tenant_id = t.id and status = 'pending' and due_date < today
  ) o
  where t.property_id is not null
    and t.user_id is not null
    and (o.amount > 0 or (t.lease_end is not null and t.lease_end < today))
    and not exists (
      select 1 from public.notifications x
      where x.tenant_id = t.id and x.type = 'rent_due' and x.created_at > now() - interval '71 hours'
    );
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.send_overdue_reminders() from public, anon, authenticated;

-- ── Error reports (any page, the server, the health checks) ──
create table if not exists public.error_reports (
  id uuid primary key default gen_random_uuid(),
  source text not null default 'app' check (source in ('app', 'server', 'health')),
  area text,
  message text not null,
  detail text,
  url text,
  user_id uuid,
  user_role text,
  user_agent text,
  fingerprint text not null,
  count int not null default 1,
  status text not null default 'open' check (status in ('open', 'fixed', 'ignored')),
  auto_fixed boolean not null default false,
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now()
);
create index if not exists error_reports_last_seen_idx on public.error_reports (last_seen desc);
create unique index if not exists error_reports_open_key on public.error_reports (fingerprint) where status = 'open';
alter table public.error_reports enable row level security;

drop policy if exists "errors admin read" on public.error_reports;
drop policy if exists "errors admin update" on public.error_reports;
drop policy if exists "errors admin delete" on public.error_reports;
create policy "errors admin read" on public.error_reports for select to authenticated using (public.is_superadmin());
create policy "errors admin update" on public.error_reports for update to authenticated using (public.is_superadmin()) with check (public.is_superadmin());
create policy "errors admin delete" on public.error_reports for delete to authenticated using (public.is_superadmin());
revoke all on public.error_reports from anon, authenticated;
grant select, update, delete on public.error_reports to authenticated;
grant all on public.error_reports to service_role;

do $$ begin
  alter publication supabase_realtime add table public.error_reports;
exception when duplicate_object then null; end $$;

-- Anyone (even signed out) can report an error; the same error is counted, not repeated.
-- The main admin is told the first time a new error appears.
create or replace function public.report_error(
  p_source text, p_area text, p_message text, p_detail text default null, p_url text default null,
  p_user_agent text default null, p_auto_fixed boolean default false
) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_source text := case when p_source in ('app', 'server', 'health') then p_source else 'app' end;
  v_message text := left(coalesce(nullif(trim(p_message), ''), 'Unknown error'), 500);
  v_area text := left(nullif(trim(p_area), ''), 120);
  v_fp text;
  v_role text;
  v_new boolean := false;
begin
  -- Same error = same message in the same area (numbers and ids removed, so they group together)
  v_fp := md5(v_source || '|' || coalesce(v_area, '') || '|' ||
    regexp_replace(v_message, '[0-9a-f]{8}-[0-9a-f-]{27,}|\d+', '#', 'g'));
  select role into v_role from public.profiles where id = auth.uid();

  update public.error_reports
  set count = count + 1, last_seen = now(), detail = coalesce(left(p_detail, 4000), detail),
      url = coalesce(left(p_url, 300), url), auto_fixed = auto_fixed or coalesce(p_auto_fixed, false)
  where fingerprint = v_fp and status = 'open';

  if not found then
    -- Don't let a flood of different errors fill the table
    if (select count(*) from public.error_reports where first_seen > now() - interval '1 hour') >= 200 then return; end if;
    insert into public.error_reports (source, area, message, detail, url, user_id, user_role, user_agent, fingerprint, auto_fixed)
    values (v_source, v_area, v_message, left(p_detail, 4000), left(p_url, 300), auth.uid(), v_role, left(p_user_agent, 300), v_fp, coalesce(p_auto_fixed, false))
    on conflict do nothing;
    v_new := found;
  end if;

  if v_new and not coalesce(p_auto_fixed, false)
     and (select count(*) from public.staff_notifications where type = 'error' and created_at > now() - interval '1 hour') < 20 then
    insert into public.staff_notifications (user_id, type, title, body, url)
    select id, 'error',
      case v_source when 'health' then 'System check found a problem' when 'server' then 'Server error' else 'Error in the app' end,
      left(coalesce(v_area || ': ', '') || v_message, 300), '/admin2026/system'
    from public.profiles where role = 'superadmin';
  end if;
end $$;
revoke execute on function public.report_error(text, text, text, text, text, text, boolean) from public;
grant execute on function public.report_error(text, text, text, text, text, text, boolean) to anon, authenticated, service_role;

-- ── Health checks (written by the server every 20 minutes) ──
create table if not exists public.health_checks (
  id uuid primary key default gen_random_uuid(),
  run_at timestamptz not null default now(),
  ok boolean not null,
  results jsonb not null default '[]',
  trigger text not null default 'schedule'
);
create index if not exists health_checks_run_at_idx on public.health_checks (run_at desc);
alter table public.health_checks enable row level security;
drop policy if exists "health admin read" on public.health_checks;
create policy "health admin read" on public.health_checks for select to authenticated using (public.is_superadmin());
revoke all on public.health_checks from anon, authenticated;
grant select on public.health_checks to authenticated;
grant all on public.health_checks to service_role;

do $$ begin
  alter publication supabase_realtime add table public.health_checks;
exception when duplicate_object then null; end $$;

-- ────────────── 42_tenant_own_details.sql ──────────────

-- 42 · landlords add a tenant with just an EMAIL or PHONE NUMBER + the room; the tenant brings their own details
--
--  • Added by email: the code only works for the account with that email.
--  • Added by phone: the code works for the account with that phone number, or for an account that has no
--    phone number yet (e.g. signed up with email); that account then gets the phone the landlord typed.
--    An account with a DIFFERENT phone number is refused.
--  • A record with neither (older data) works for any tenant account that enters the code in its 20 minutes.
--  • When the tenant connects, their OWN name, email and phone (from their account) are saved on the
--    tenant record, replacing whatever the landlord typed.
-- Safe to run more than once.

create or replace function public.redeem_connect_code(p_code text) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  t record;
  me uuid := auth.uid();
  v_email text;
  v_phone9 text;
  v_phone text;
  v_name text;
  digits9 text;
begin
  if me is null then
    raise exception 'Please sign in first.';
  end if;
  if not exists (select 1 from public.profiles where id = me and role = 'tenant') then
    raise exception 'Only tenant accounts can use a connection code.';
  end if;
  if exists (select 1 from public.tenants where user_id = me and property_id is not null) then
    raise exception 'Your account is already connected to a rental.';
  end if;

  select * into t
  from public.tenants
  where connect_code = upper(trim(p_code))
    and connect_code_expires_at > now()
    and user_id is null
  for update;

  if t.id is null then
    raise exception 'This code is invalid or has expired. Ask your landlord for a new one.';
  end if;

  select lower(coalesce(u.email, '')), nullif(trim(coalesce(p.phone, u.phone, '')), ''), nullif(trim(p.full_name), '')
    into v_email, v_phone, v_name
  from auth.users u left join public.profiles p on p.id = u.id
  where u.id = me;
  v_phone9 := right(regexp_replace(coalesce(v_phone, ''), '\D', '', 'g'), 9);
  digits9 := right(regexp_replace(coalesce(t.phone, ''), '\D', '', 'g'), 9);

  -- The landlord gave an email or phone: only that person's account may connect
  if (t.email is not null or length(digits9) = 9) and not (
    (t.email is not null and lower(t.email) = v_email)
    or (length(digits9) = 9 and (digits9 = v_phone9 or (t.email is null and length(v_phone9) < 9)))
  ) then
    raise exception 'This code is for a different account. Sign in with the email or phone number your landlord registered for you, or ask them to check your details.';
  end if;

  -- Detach any former-tenant record so user_id stays unique
  update public.tenants set user_id = null where user_id = me;

  -- The tenant's own details replace what the landlord typed
  update public.tenants
  set user_id = me,
      full_name = coalesce(v_name, full_name),
      email = case when v_email = '' or v_email like '%@phone-signin.example.com' then email else v_email end,
      phone = coalesce(v_phone, phone),
      connect_code = null,
      connect_code_expires_at = null
  where id = t.id;

  return t.id;
end $$;

revoke execute on function public.redeem_connect_code(text) from public, anon;
grant execute on function public.redeem_connect_code(text) to authenticated;

-- ────────────── 43_heard_from.sql ──────────────

-- 43 · "Where did you hear about Renta UG?"
-- Asked once in the welcome tour (landlords and tenants). One answer per account.
-- The main admin sees the totals on the Statistics page. Safe to run again.

create table if not exists public.signup_sources (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  role       text,
  source     text not null check (char_length(source) between 1 and 40),
  detail     text check (detail is null or char_length(detail) <= 120),
  created_at timestamptz not null default now()
);

alter table public.signup_sources enable row level security;

-- The role always comes from the account itself, never from the browser
create or replace function public.signup_source_role() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.role := (select role from public.profiles where id = new.user_id);
  new.detail := nullif(trim(new.detail), '');
  return new;
end $$;

drop trigger if exists signup_source_role on public.signup_sources;
create trigger signup_source_role before insert or update on public.signup_sources
  for each row execute function public.signup_source_role();

drop policy if exists "signup_sources own insert" on public.signup_sources;
create policy "signup_sources own insert" on public.signup_sources
  for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "signup_sources read" on public.signup_sources;
create policy "signup_sources read" on public.signup_sources
  for select to authenticated using (user_id = auth.uid() or public.is_superadmin());

drop policy if exists "signup_sources admin delete" on public.signup_sources;
create policy "signup_sources admin delete" on public.signup_sources
  for delete to authenticated using (public.is_superadmin());

grant select, insert on public.signup_sources to authenticated;
grant delete on public.signup_sources to authenticated;

-- ────────────── 44_security_hardening.sql ──────────────

-- 44 · security hardening (safe to run again)
--
-- 1. setup_codes: a one-time code is now needed for a FIRST sign-in (a landlord registered by the
--    main admin, or a tenant given app access by their landlord). Before, an email or phone number
--    alone was enough, and those are not secret. Only a hash of the code is stored. Server only.
-- 2. login_failures: wrong-password counter per account for sign-in through the server (phone
--    sign-in), so passwords can't be guessed endlessly. Server only.
-- 3. tenants.user_id can only be set by the connection-code flow or the server, never by a landlord
--    writing the row directly (that would attach someone else's account to their tenant record).

create table if not exists public.setup_codes (
  user_id uuid primary key references auth.users (id) on delete cascade,
  code_hash text not null,
  expires_at timestamptz not null,
  attempts int not null default 0,
  created_at timestamptz not null default now()
);
alter table public.setup_codes enable row level security;
revoke all on public.setup_codes from public, anon, authenticated;
grant all on public.setup_codes to service_role;

create table if not exists public.login_failures (
  key text primary key,          -- 'phone:772123456'
  fails int not null default 0,
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.login_failures enable row level security;
revoke all on public.login_failures from public, anon, authenticated;
grant all on public.login_failures to service_role;

-- Direct writes from the app run as the "authenticated" role; the connection-code function
-- (security definer) and the server (service_role) run as other roles and are allowed.
create or replace function public.guard_tenant_user_id() returns trigger
language plpgsql set search_path = '' as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' and new.user_id is not null then
      raise exception 'A tenant account can only be linked with a connection code.';
    end if;
    if tg_op = 'UPDATE' and new.user_id is distinct from old.user_id and new.user_id is not null then
      raise exception 'A tenant account can only be linked with a connection code.';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists tenants_guard_user_id on public.tenants;
create trigger tenants_guard_user_id
  before insert or update of user_id on public.tenants
  for each row execute function public.guard_tenant_user_id();

-- ────────────── 45_landlord_subscriptions.sql ──────────────

-- 45 · landlord subscriptions (safe to run again; no data is deleted)
--
-- Landlords pay Renta UG a MONTHLY or YEARLY subscription to manage their properties.
--  • Prices, the free-trial length and Renta UG's MTN / Airtel receiving numbers are set by the main admin
--    (billing_settings, one row).
--  • Every landlord has: subscription_until (last day covered), subscription_plan (null = free trial) and a
--    billing_code: their payment reason, like a tenant's pay code.
--  • New landlords (and all existing ones, once) get the free trial.
--  • A landlord pays with mobile money from their phone, then submits the payment. It waits as 'pending'
--    until the main admin confirms it; the subscription is then extended (on top of any time left).
--  • When the subscription has ended a landlord can still SEE everything and renew, but every change
--    (houses, tenants, payments, notices, requests to leave…) is refused by the database itself.
--  • Reminders in the landlord's inbox 7, 3 and 1 days before the end, on the day, and the day after.

-- ── Settings ──
create table if not exists public.billing_settings (
  id int primary key default 1 check (id = 1),
  monthly_price bigint not null default 30000 check (monthly_price > 0),
  yearly_price bigint not null default 300000 check (yearly_price > 0),
  trial_days int not null default 30 check (trial_days between 0 and 365),
  mtn_phone text,
  mtn_name text,
  airtel_phone text,
  airtel_name text,
  updated_at timestamptz not null default now()
);
insert into public.billing_settings (id) values (1) on conflict (id) do nothing;
alter table public.billing_settings enable row level security;
drop policy if exists "billing settings read" on public.billing_settings;
create policy "billing settings read" on public.billing_settings for select to authenticated using (true);
revoke all on public.billing_settings from public, anon, authenticated;
grant select on public.billing_settings to authenticated;
grant all on public.billing_settings to service_role;

-- ── The landlord's subscription (on their profile; users can't write these columns) ──
alter table public.profiles add column if not exists subscription_until date;
alter table public.profiles add column if not exists subscription_plan text;
alter table public.profiles add column if not exists billing_code text;
create unique index if not exists profiles_billing_code_key on public.profiles (billing_code) where billing_code is not null;
do $$ begin
  alter table public.profiles add constraint profiles_subscription_plan_check check (subscription_plan in ('monthly', 'yearly'));
exception when duplicate_object then null; end $$;

create or replace function public.new_billing_code() returns text
language plpgsql volatile security definer set search_path = '' as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  c text;
begin
  loop
    c := 'RUG';
    for i in 1..5 loop
      c := c || substr(alphabet, 1 + get_byte(extensions.gen_random_bytes(1), 0) % 32, 1);
    end loop;
    exit when not exists (select 1 from public.profiles where billing_code = c);
  end loop;
  return c;
end $$;
revoke execute on function public.new_billing_code() from public, anon, authenticated;

-- A profile becomes a landlord → payment code + free trial (once)
create or replace function public.landlord_billing_defaults() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.role = 'landlord' then
    if new.billing_code is null then new.billing_code := public.new_billing_code(); end if;
    if new.subscription_until is null then
      new.subscription_until := public.kampala_today() + (select trial_days from public.billing_settings where id = 1);
    end if;
  end if;
  return new;
end $$;
drop trigger if exists profiles_landlord_billing on public.profiles;
create trigger profiles_landlord_billing before insert or update of role on public.profiles
  for each row execute function public.landlord_billing_defaults();

-- Existing landlords: code + free trial from today (one at a time so codes stay unique)
do $$
declare r record;
begin
  for r in select id from public.profiles where role = 'landlord' and (billing_code is null or subscription_until is null) loop
    update public.profiles
    set billing_code = coalesce(billing_code, public.new_billing_code()),
        subscription_until = coalesce(subscription_until, public.kampala_today() + (select trial_days from public.billing_settings where id = 1))
    where id = r.id;
  end loop;
end $$;

-- ── Subscription payments (written only through the functions below) ──
create table if not exists public.subscription_payments (
  id uuid primary key default gen_random_uuid(),
  landlord_id uuid not null references auth.users (id) on delete cascade,
  plan text not null check (plan in ('monthly', 'yearly')),
  months int not null check (months in (1, 12)),
  amount bigint not null check (amount > 0),
  network text not null check (network in ('mtn', 'airtel')),
  sender_phone text not null,
  sender_name text not null,
  reference text not null,
  paid_on date not null,
  status text not null default 'pending' check (status in ('pending', 'confirmed', 'rejected', 'cancelled')),
  period_start date,
  period_end date,
  reviewed_by uuid references auth.users (id) on delete set null,
  reviewed_at timestamptz,
  reject_reason text,
  created_at timestamptz not null default now()
);
create index if not exists subscription_payments_landlord_idx on public.subscription_payments (landlord_id, created_at desc);
create unique index if not exists subscription_payments_one_pending on public.subscription_payments (landlord_id) where status = 'pending';
alter table public.subscription_payments enable row level security;
drop policy if exists "subscription payments own" on public.subscription_payments;
drop policy if exists "subscription payments admin" on public.subscription_payments;
create policy "subscription payments own" on public.subscription_payments for select to authenticated using (landlord_id = auth.uid());
create policy "subscription payments admin" on public.subscription_payments for select to authenticated using (public.is_superadmin());
revoke all on public.subscription_payments from public, anon, authenticated;
grant select on public.subscription_payments to authenticated;
grant all on public.subscription_payments to service_role;

do $$ begin
  alter publication supabase_realtime add table public.subscription_payments;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.billing_settings;
exception when duplicate_object then null; end $$;

-- ── Is this landlord's subscription running today? (non-landlords: always true) ──
create or replace function public.landlord_subscribed(p_user uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select p.role <> 'landlord' or coalesce(p.subscription_until >= public.kampala_today(), false) from public.profiles p where p.id = p_user),
    true);
$$;
revoke execute on function public.landlord_subscribed(uuid) from public, anon;
grant execute on function public.landlord_subscribed(uuid) to authenticated, service_role;

-- ── Ended subscription → the landlord's changes are refused (reading is unaffected) ──
create or replace function public.require_active_subscription() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is not null and not public.landlord_subscribed(auth.uid()) then
    raise exception 'Your Renta UG subscription has ended. Renew it on the Subscription page to keep managing your properties.';
  end if;
  return coalesce(new, old);
end $$;

do $$
declare t text;
begin
  foreach t in array array['properties', 'rentals', 'tenants', 'payments', 'cash_payments', 'landlord_pay_accounts', 'move_out_requests'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_require_subscription', t);
    execute format('create trigger %I before insert or update or delete on public.%I for each row execute function public.require_active_subscription()',
      t || '_require_subscription', t);
  end loop;
end $$;
-- Notices: sending / deleting needs a subscription; marking as read does not
drop trigger if exists notifications_require_subscription on public.notifications;
create trigger notifications_require_subscription before insert or delete on public.notifications
  for each row execute function public.require_active_subscription();

-- ── Landlord: submit a payment they sent ──
create or replace function public.submit_subscription_payment(
  p_plan text, p_network text, p_sender_phone text, p_sender_name text, p_paid_on date default null
) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  s public.billing_settings;
  p record;
  v_paid_on date := coalesce(p_paid_on, public.kampala_today());
  v_phone text := regexp_replace(coalesce(p_sender_phone, ''), '[^0-9+]', '', 'g');
  v_amount bigint;
  v_id uuid;
begin
  select * into p from public.profiles where id = me;
  if p.role is distinct from 'landlord' then raise exception 'Only landlords have a subscription.'; end if;
  if not p.active then raise exception 'This account is suspended. Please contact Renta UG.'; end if;
  if p_plan not in ('monthly', 'yearly') then raise exception 'Choose monthly or yearly.'; end if;
  if p_network not in ('mtn', 'airtel') then raise exception 'Choose MTN or Airtel.'; end if;

  select * into s from public.billing_settings where id = 1;
  if (p_network = 'mtn' and s.mtn_phone is null) or (p_network = 'airtel' and s.airtel_phone is null) then
    raise exception 'Renta UG has not added a number for this network yet.';
  end if;
  if length(right(regexp_replace(v_phone, '\D', '', 'g'), 9)) < 9 then raise exception 'Enter the number you paid from.'; end if;
  if length(trim(coalesce(p_sender_name, ''))) < 3 then raise exception 'Enter the names registered on that number.'; end if;
  if v_paid_on > public.kampala_today() then raise exception 'The payment date cannot be in the future.'; end if;
  if v_paid_on < public.kampala_today() - 30 then raise exception 'That payment date is more than 30 days ago. Contact Renta UG.'; end if;
  if exists (select 1 from public.subscription_payments where landlord_id = me and status = 'pending') then
    raise exception 'You already have a payment waiting to be confirmed.';
  end if;

  v_amount := case p_plan when 'yearly' then s.yearly_price else s.monthly_price end;

  insert into public.subscription_payments (landlord_id, plan, months, amount, network, sender_phone, sender_name, reference, paid_on)
  values (me, p_plan, case p_plan when 'yearly' then 12 else 1 end, v_amount, p_network, v_phone,
          upper(left(trim(p_sender_name), 80)), coalesce(p.billing_code, '—'), v_paid_on)
  returning id into v_id;

  insert into public.staff_notifications (user_id, type, title, body, url)
  select id, 'subscription', 'Subscription payment to confirm',
    format('%s says they sent %s on %s for a %s subscription (reason %s, from %s). Check the money, then confirm it.',
      coalesce(nullif(p.full_name, ''), p.email), public.ugx(v_amount),
      case p_network when 'mtn' then 'MTN' else 'Airtel' end, p_plan, coalesce(p.billing_code, '—'), v_phone),
    '/admin2026/subscriptions'
  from public.profiles where role = 'superadmin';

  return v_id;
end $$;

-- ── Landlord: withdraw a payment that is still waiting ──
create or replace function public.cancel_subscription_payment(p_id uuid) returns void
language plpgsql volatile security definer set search_path = '' as $$
begin
  update public.subscription_payments set status = 'cancelled', reviewed_at = now()
  where id = p_id and landlord_id = auth.uid() and status = 'pending';
  if not found then raise exception 'There is no waiting payment to cancel.'; end if;
end $$;

-- ── Main admin: confirm → extend the subscription on top of any time left ──
create or replace function public.admin_confirm_subscription_payment(p_id uuid) returns json
language plpgsql volatile security definer set search_path = '' as $$
declare
  r public.subscription_payments;
  p record;
  v_start date;
  v_end date;
begin
  perform public.admin_require();
  select * into r from public.subscription_payments where id = p_id for update;
  if not found then raise exception 'Payment not found.'; end if;
  if r.status <> 'pending' then raise exception 'This payment has already been %.', r.status; end if;
  select * into p from public.profiles where id = r.landlord_id for update;

  v_start := case when p.subscription_until >= public.kampala_today() then p.subscription_until + 1 else public.kampala_today() end;
  v_end := (v_start + make_interval(months => r.months) - interval '1 day')::date;

  update public.profiles set subscription_until = v_end, subscription_plan = r.plan where id = r.landlord_id;
  update public.subscription_payments
  set status = 'confirmed', period_start = v_start, period_end = v_end, reviewed_by = auth.uid(), reviewed_at = now()
  where id = r.id;

  insert into public.staff_notifications (user_id, type, title, body, url)
  values (r.landlord_id, 'subscription', 'Subscription renewed',
    format('Thank you! Your %s payment of %s was received. Your Renta UG subscription now runs until %s.',
      r.plan, public.ugx(r.amount), to_char(v_end, 'FMDD Mon YYYY')),
    '/landlord/subscription');
  perform public.admin_log('subscription.confirm', 'landlord', r.landlord_id,
    format('Confirmed %s %s subscription from %s, now runs to %s', public.ugx(r.amount), r.plan,
      coalesce(nullif(p.full_name, ''), p.email), to_char(v_end, 'FMDD Mon YYYY')));
  return json_build_object('until', v_end, 'start', v_start);
end $$;

-- ── Main admin: reject (the money did not arrive) ──
create or replace function public.admin_reject_subscription_payment(p_id uuid, p_reason text default null) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  r public.subscription_payments;
  v_reason text := nullif(trim(p_reason), '');
begin
  perform public.admin_require();
  select * into r from public.subscription_payments where id = p_id for update;
  if not found then raise exception 'Payment not found.'; end if;
  if r.status <> 'pending' then raise exception 'This payment has already been %.', r.status; end if;
  update public.subscription_payments
  set status = 'rejected', reject_reason = v_reason, reviewed_by = auth.uid(), reviewed_at = now()
  where id = r.id;
  insert into public.staff_notifications (user_id, type, title, body, url)
  values (r.landlord_id, 'subscription', 'Subscription payment not confirmed',
    format('Your %s payment of %s from %s could not be confirmed%s. Please check it, or contact Renta UG.',
      r.plan, public.ugx(r.amount), to_char(r.paid_on, 'FMDD Mon YYYY'), coalesce(': ' || v_reason, '')),
    '/landlord/subscription');
  perform public.admin_log('subscription.reject', 'landlord', r.landlord_id,
    format('Rejected %s %s subscription payment%s', public.ugx(r.amount), r.plan, coalesce(' (' || v_reason || ')', '')));
end $$;

-- ── Main admin: add free days (goodwill, a payment made another way, a longer trial…) ──
create or replace function public.admin_grant_subscription(p_landlord uuid, p_days int, p_note text default null) returns date
language plpgsql volatile security definer set search_path = '' as $$
declare
  p record;
  v_end date;
begin
  perform public.admin_require();
  if p_days is null or p_days < 1 or p_days > 730 then raise exception 'Choose between 1 and 730 days.'; end if;
  select * into p from public.profiles where id = p_landlord and role = 'landlord' for update;
  if not found then raise exception 'Landlord not found.'; end if;
  v_end := greatest(coalesce(p.subscription_until, public.kampala_today() - 1), public.kampala_today() - 1) + p_days;
  update public.profiles set subscription_until = v_end where id = p_landlord;
  insert into public.staff_notifications (user_id, type, title, body, url)
  values (p_landlord, 'subscription', 'Subscription extended',
    format('Renta UG added %s day%s to your subscription%s. It now runs until %s.',
      p_days, case when p_days = 1 then '' else 's' end, coalesce(': ' || nullif(trim(p_note), ''), ''), to_char(v_end, 'FMDD Mon YYYY')),
    '/landlord/subscription');
  perform public.admin_log('subscription.grant', 'landlord', p_landlord,
    format('Added %s days to %s''s subscription (now to %s)%s', p_days, coalesce(nullif(p.full_name, ''), p.email),
      to_char(v_end, 'FMDD Mon YYYY'), coalesce(': ' || nullif(trim(p_note), ''), '')));
  return v_end;
end $$;

-- ── Main admin: prices, trial, receiving numbers ──
create or replace function public.admin_save_billing_settings(
  p_monthly bigint, p_yearly bigint, p_trial_days int,
  p_mtn_phone text, p_mtn_name text, p_airtel_phone text, p_airtel_name text
) returns void
language plpgsql volatile security definer set search_path = '' as $$
begin
  perform public.admin_require();
  if p_monthly is null or p_monthly < 500 then raise exception 'Enter a monthly price of at least UGX 500.'; end if;
  if p_yearly is null or p_yearly < 500 then raise exception 'Enter a yearly price of at least UGX 500.'; end if;
  if p_trial_days is null or p_trial_days < 0 or p_trial_days > 365 then raise exception 'The free trial must be 0 to 365 days.'; end if;
  if nullif(trim(p_mtn_phone), '') is not null and length(trim(coalesce(p_mtn_name, ''))) < 3 then
    raise exception 'Enter the name MTN shows for that number.';
  end if;
  if nullif(trim(p_airtel_phone), '') is not null and length(trim(coalesce(p_airtel_name, ''))) < 3 then
    raise exception 'Enter the name Airtel shows for that number.';
  end if;
  update public.billing_settings
  set monthly_price = p_monthly, yearly_price = p_yearly, trial_days = p_trial_days,
      mtn_phone = nullif(trim(p_mtn_phone), ''), mtn_name = nullif(upper(trim(p_mtn_name)), ''),
      airtel_phone = nullif(trim(p_airtel_phone), ''), airtel_name = nullif(upper(trim(p_airtel_name)), ''),
      updated_at = now()
  where id = 1;
  perform public.admin_log('billing.settings', 'billing', null,
    format('Subscription prices: %s / month, %s / year, %s-day free trial', public.ugx(p_monthly), public.ugx(p_yearly), p_trial_days));
end $$;

-- ── Daily reminders in the landlord's inbox ──
create or replace function public.send_subscription_reminders() returns integer
language plpgsql volatile security definer set search_path = '' as $$
declare
  today date := public.kampala_today();
  n integer;
begin
  insert into public.staff_notifications (user_id, type, title, body, url)
  select p.id, 'subscription',
    case when d.left_days < 0 then 'Subscription ended' else 'Subscription ending soon' end,
    case
      when d.left_days < 0 then format('Your Renta UG %s ended on %s. You can still see everything, but changes are paused until you renew.',
        case when p.subscription_plan is null then 'free trial' else 'subscription' end, to_char(p.subscription_until, 'FMDD Mon YYYY'))
      when d.left_days = 0 then format('Your Renta UG %s ends today. Renew now to keep managing your properties without a break.',
        case when p.subscription_plan is null then 'free trial' else 'subscription' end)
      else format('Your Renta UG %s ends in %s day%s, on %s. Renew any time: the new period is added on top.',
        case when p.subscription_plan is null then 'free trial' else 'subscription' end,
        d.left_days, case when d.left_days = 1 then '' else 's' end, to_char(p.subscription_until, 'FMDD Mon YYYY'))
    end,
    '/landlord/subscription'
  from public.profiles p
  cross join lateral (select p.subscription_until - today as left_days) d
  where p.role = 'landlord' and p.active and p.subscription_until is not null
    and d.left_days in (7, 3, 1, 0, -1)
    and not exists (
      select 1 from public.staff_notifications x
      where x.user_id = p.id and x.type = 'subscription' and x.title in ('Subscription ending soon', 'Subscription ended')
        and x.created_at > now() - interval '20 hours'
    );
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.send_subscription_reminders() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'renta-subscription-reminders';
    perform cron.schedule('renta-subscription-reminders', '0 6 * * *', 'select public.send_subscription_reminders()');
  end if;
exception when others then null;
end $$;

-- ── Who may call what ──
revoke execute on function public.submit_subscription_payment(text, text, text, text, date) from public, anon;
revoke execute on function public.cancel_subscription_payment(uuid) from public, anon;
revoke execute on function public.admin_confirm_subscription_payment(uuid) from public, anon;
revoke execute on function public.admin_reject_subscription_payment(uuid, text) from public, anon;
revoke execute on function public.admin_grant_subscription(uuid, int, text) from public, anon;
revoke execute on function public.admin_save_billing_settings(bigint, bigint, int, text, text, text, text) from public, anon;
grant execute on function public.submit_subscription_payment(text, text, text, text, date) to authenticated;
grant execute on function public.cancel_subscription_payment(uuid) to authenticated;
grant execute on function public.admin_confirm_subscription_payment(uuid) to authenticated;
grant execute on function public.admin_reject_subscription_payment(uuid, text) to authenticated;
grant execute on function public.admin_grant_subscription(uuid, int, text) to authenticated;
grant execute on function public.admin_save_billing_settings(bigint, bigint, int, text, text, text, text) to authenticated;

-- ────────────── 46_subscription_tiers.sql ──────────────

-- 46 · subscription scales + one permanent free landlord (safe to run again; no data is deleted)
--
--  Two scales, priced by how many houses / rooms a landlord has (all their properties, rooms included):
--    Small scale  UGX 55,000 / month   UGX 650,000 / year    up to small_max_units houses + rooms (default 10)
--    Big scale    UGX 105,000 / month  UGX 1,200,000 / year  any number
--  A landlord with more units than the small limit must choose Big scale, and a Small-scale subscriber
--  can't add houses / rooms beyond the limit (they upgrade to Big scale). The free trial has no limit.
--  Prices and the limit are set by the main admin (Subscriptions → Prices and payment numbers).
--
--  Permanent free landlord: ngumisiriza@gmail.com never pays and is never paused (subscription_exempt).
--  Nobody can switch this on from the app: only this file sets it.

-- ── Prices per scale ──
alter table public.billing_settings add column if not exists small_monthly bigint not null default 55000;
alter table public.billing_settings add column if not exists small_yearly bigint not null default 650000;
alter table public.billing_settings add column if not exists big_monthly bigint not null default 105000;
alter table public.billing_settings add column if not exists big_yearly bigint not null default 1200000;
alter table public.billing_settings add column if not exists small_max_units int not null default 10;

-- ── Landlord: their scale, and the permanent free flag (users can't write these columns) ──
alter table public.profiles add column if not exists subscription_tier text;
alter table public.profiles add column if not exists subscription_exempt boolean not null default false;
do $$ begin
  alter table public.profiles add constraint profiles_subscription_tier_check check (subscription_tier in ('small', 'big'));
exception when duplicate_object then null; end $$;

alter table public.subscription_payments add column if not exists tier text not null default 'small';
do $$ begin
  alter table public.subscription_payments add constraint subscription_payments_tier_check check (tier in ('small', 'big'));
exception when duplicate_object then null; end $$;

-- The one permanent free landlord account
update public.profiles set subscription_exempt = true where lower(email) = 'ngumisiriza@gmail.com';

-- ── Houses + rooms a landlord has ──
create or replace function public.landlord_unit_count(p_user uuid default auth.uid()) returns int
language sql stable security definer set search_path = '' as $$
  select count(*)::int from public.properties where landlord_id = p_user;
$$;
revoke execute on function public.landlord_unit_count(uuid) from public, anon;
grant execute on function public.landlord_unit_count(uuid) to authenticated;

-- ── Subscribed? Permanent free accounts always are ──
create or replace function public.landlord_subscribed(p_user uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select p.role <> 'landlord' or p.subscription_exempt or coalesce(p.subscription_until >= public.kampala_today(), false)
     from public.profiles p where p.id = p_user),
    true);
$$;

-- ── Guard: ended subscription → no changes; Small scale → no more than the unit limit ──
create or replace function public.require_active_subscription() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  p record;
  v_max int;
begin
  if auth.uid() is null then return coalesce(new, old); end if;
  if not public.landlord_subscribed(auth.uid()) then
    raise exception 'Your Renta UG subscription has ended. Renew it on the Subscription page to keep managing your properties.';
  end if;
  if tg_table_name = 'properties' and tg_op = 'INSERT' then
    select role, subscription_exempt, subscription_plan, subscription_tier into p from public.profiles where id = auth.uid();
    if p.role = 'landlord' and not p.subscription_exempt and p.subscription_plan is not null and p.subscription_tier = 'small' then
      select small_max_units into v_max from public.billing_settings where id = 1;
      if public.landlord_unit_count(auth.uid()) >= v_max then
        raise exception 'Small scale covers up to % houses and rooms. Upgrade to Big scale on the Subscription page to add more.', v_max;
      end if;
    end if;
  end if;
  return coalesce(new, old);
end $$;

-- ── Landlord: submit a payment (now with the scale) ──
drop function if exists public.submit_subscription_payment(text, text, text, text, date);
create or replace function public.submit_subscription_payment(
  p_tier text, p_plan text, p_network text, p_sender_phone text, p_sender_name text, p_paid_on date default null
) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  s public.billing_settings;
  p record;
  v_paid_on date := coalesce(p_paid_on, public.kampala_today());
  v_phone text := regexp_replace(coalesce(p_sender_phone, ''), '[^0-9+]', '', 'g');
  v_units int;
  v_amount bigint;
  v_id uuid;
begin
  select * into p from public.profiles where id = me;
  if p.role is distinct from 'landlord' then raise exception 'Only landlords have a subscription.'; end if;
  if p.subscription_exempt then raise exception 'Your account is free for life: there is nothing to pay.'; end if;
  if not p.active then raise exception 'This account is suspended. Please contact Renta UG.'; end if;
  if p_tier not in ('small', 'big') then raise exception 'Choose Small scale or Big scale.'; end if;
  if p_plan not in ('monthly', 'yearly') then raise exception 'Choose monthly or yearly.'; end if;
  if p_network not in ('mtn', 'airtel') then raise exception 'Choose MTN or Airtel.'; end if;

  select * into s from public.billing_settings where id = 1;
  v_units := public.landlord_unit_count(me);
  if p_tier = 'small' and v_units > s.small_max_units then
    raise exception 'You have % houses and rooms. Small scale covers up to %, so please choose Big scale.', v_units, s.small_max_units;
  end if;
  if (p_network = 'mtn' and s.mtn_phone is null) or (p_network = 'airtel' and s.airtel_phone is null) then
    raise exception 'Renta UG has not added a number for this network yet.';
  end if;
  if length(right(regexp_replace(v_phone, '\D', '', 'g'), 9)) < 9 then raise exception 'Enter the number you paid from.'; end if;
  if length(trim(coalesce(p_sender_name, ''))) < 5 or trim(p_sender_name) !~ '\S+\s+\S+' then
    raise exception 'Enter the full names registered on the line you paid from (at least two names).';
  end if;
  if v_paid_on > public.kampala_today() then raise exception 'The payment date cannot be in the future.'; end if;
  if v_paid_on < public.kampala_today() - 30 then raise exception 'That payment date is more than 30 days ago. Contact Renta UG.'; end if;
  if exists (select 1 from public.subscription_payments where landlord_id = me and status = 'pending') then
    raise exception 'You already have a payment waiting to be confirmed.';
  end if;

  v_amount := case
    when p_tier = 'big' and p_plan = 'yearly' then s.big_yearly
    when p_tier = 'big' then s.big_monthly
    when p_plan = 'yearly' then s.small_yearly
    else s.small_monthly end;

  insert into public.subscription_payments (landlord_id, tier, plan, months, amount, network, sender_phone, sender_name, reference, paid_on)
  values (me, p_tier, p_plan, case p_plan when 'yearly' then 12 else 1 end, v_amount, p_network, v_phone,
          upper(left(regexp_replace(trim(p_sender_name), '\s+', ' ', 'g'), 80)), coalesce(p.billing_code, '—'), v_paid_on)
  returning id into v_id;

  insert into public.staff_notifications (user_id, type, title, body, url)
  select id, 'subscription', 'Subscription payment to confirm',
    format('%s says they sent %s on %s for %s scale, %s (reason %s, from %s, registered to %s). Check the money, then confirm it.',
      coalesce(nullif(p.full_name, ''), p.email), public.ugx(v_amount),
      case p_network when 'mtn' then 'MTN' else 'Airtel' end, initcap(p_tier), p_plan, coalesce(p.billing_code, '—'), v_phone,
      upper(trim(p_sender_name))),
    '/admin2026/subscriptions'
  from public.profiles where role = 'superadmin';

  return v_id;
end $$;

-- ── Main admin: confirm → extend on top of any time left, and set the scale ──
create or replace function public.admin_confirm_subscription_payment(p_id uuid) returns json
language plpgsql volatile security definer set search_path = '' as $$
declare
  r public.subscription_payments;
  p record;
  v_start date;
  v_end date;
begin
  perform public.admin_require();
  select * into r from public.subscription_payments where id = p_id for update;
  if not found then raise exception 'Payment not found.'; end if;
  if r.status <> 'pending' then raise exception 'This payment has already been %.', r.status; end if;
  select * into p from public.profiles where id = r.landlord_id for update;

  v_start := case when p.subscription_until >= public.kampala_today() then p.subscription_until + 1 else public.kampala_today() end;
  v_end := (v_start + make_interval(months => r.months) - interval '1 day')::date;

  update public.profiles set subscription_until = v_end, subscription_plan = r.plan, subscription_tier = r.tier where id = r.landlord_id;
  update public.subscription_payments
  set status = 'confirmed', period_start = v_start, period_end = v_end, reviewed_by = auth.uid(), reviewed_at = now()
  where id = r.id;

  insert into public.staff_notifications (user_id, type, title, body, url)
  values (r.landlord_id, 'subscription', 'Subscription renewed',
    format('Thank you! Your %s scale %s payment of %s was received. Your Renta UG subscription now runs until %s.',
      initcap(r.tier), r.plan, public.ugx(r.amount), to_char(v_end, 'FMDD Mon YYYY')),
    '/landlord/subscription');
  perform public.admin_log('subscription.confirm', 'landlord', r.landlord_id,
    format('Confirmed %s %s scale %s subscription from %s, now runs to %s', public.ugx(r.amount), r.tier, r.plan,
      coalesce(nullif(p.full_name, ''), p.email), to_char(v_end, 'FMDD Mon YYYY')));
  return json_build_object('until', v_end, 'start', v_start);
end $$;

-- ── Main admin: prices per scale, the small-scale limit, trial, receiving numbers ──
drop function if exists public.admin_save_billing_settings(bigint, bigint, int, text, text, text, text);
create or replace function public.admin_save_billing_settings(
  p_small_monthly bigint, p_small_yearly bigint, p_big_monthly bigint, p_big_yearly bigint,
  p_small_max_units int, p_trial_days int,
  p_mtn_phone text, p_mtn_name text, p_airtel_phone text, p_airtel_name text
) returns void
language plpgsql volatile security definer set search_path = '' as $$
begin
  perform public.admin_require();
  if least(p_small_monthly, p_small_yearly, p_big_monthly, p_big_yearly) is null
     or least(p_small_monthly, p_small_yearly, p_big_monthly, p_big_yearly) < 500 then
    raise exception 'Every price must be at least UGX 500.';
  end if;
  if p_small_max_units is null or p_small_max_units < 1 or p_small_max_units > 10000 then raise exception 'Enter how many houses and rooms Small scale covers.'; end if;
  if p_trial_days is null or p_trial_days < 0 or p_trial_days > 365 then raise exception 'The free trial must be 0 to 365 days.'; end if;
  if nullif(trim(p_mtn_phone), '') is not null and length(trim(coalesce(p_mtn_name, ''))) < 3 then
    raise exception 'Enter the name MTN shows for that number.';
  end if;
  if nullif(trim(p_airtel_phone), '') is not null and length(trim(coalesce(p_airtel_name, ''))) < 3 then
    raise exception 'Enter the name Airtel shows for that number.';
  end if;
  update public.billing_settings
  set small_monthly = p_small_monthly, small_yearly = p_small_yearly, big_monthly = p_big_monthly, big_yearly = p_big_yearly,
      small_max_units = p_small_max_units, trial_days = p_trial_days,
      monthly_price = p_small_monthly, yearly_price = p_small_yearly, -- older app versions read these
      mtn_phone = nullif(trim(p_mtn_phone), ''), mtn_name = nullif(upper(trim(p_mtn_name)), ''),
      airtel_phone = nullif(trim(p_airtel_phone), ''), airtel_name = nullif(upper(trim(p_airtel_name)), ''),
      updated_at = now()
  where id = 1;
  perform public.admin_log('billing.settings', 'billing', null,
    format('Subscription prices: small %s / month, %s / year (up to %s units); big %s / month, %s / year; %s-day trial',
      public.ugx(p_small_monthly), public.ugx(p_small_yearly), p_small_max_units, public.ugx(p_big_monthly), public.ugx(p_big_yearly), p_trial_days));
end $$;

-- ── Reminders: never for the permanent free account ──
create or replace function public.send_subscription_reminders() returns integer
language plpgsql volatile security definer set search_path = '' as $$
declare
  today date := public.kampala_today();
  n integer;
begin
  insert into public.staff_notifications (user_id, type, title, body, url)
  select p.id, 'subscription',
    case when d.left_days < 0 then 'Subscription ended' else 'Subscription ending soon' end,
    case
      when d.left_days < 0 then format('Your Renta UG %s ended on %s. You can still see everything, but changes are paused until you renew.',
        case when p.subscription_plan is null then 'free trial' else 'subscription' end, to_char(p.subscription_until, 'FMDD Mon YYYY'))
      when d.left_days = 0 then format('Your Renta UG %s ends today. Renew now to keep managing your properties without a break.',
        case when p.subscription_plan is null then 'free trial' else 'subscription' end)
      else format('Your Renta UG %s ends in %s day%s, on %s. Renew any time: the new period is added on top.',
        case when p.subscription_plan is null then 'free trial' else 'subscription' end,
        d.left_days, case when d.left_days = 1 then '' else 's' end, to_char(p.subscription_until, 'FMDD Mon YYYY'))
    end,
    '/landlord/subscription'
  from public.profiles p
  cross join lateral (select p.subscription_until - today as left_days) d
  where p.role = 'landlord' and p.active and not p.subscription_exempt and p.subscription_until is not null
    and d.left_days in (7, 3, 1, 0, -1)
    and not exists (
      select 1 from public.staff_notifications x
      where x.user_id = p.id and x.type = 'subscription' and x.title in ('Subscription ending soon', 'Subscription ended')
        and x.created_at > now() - interval '20 hours'
    );
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.send_subscription_reminders() from public, anon, authenticated;

revoke execute on function public.submit_subscription_payment(text, text, text, text, text, date) from public, anon;
revoke execute on function public.admin_save_billing_settings(bigint, bigint, bigint, bigint, int, int, text, text, text, text) from public, anon;
grant execute on function public.submit_subscription_payment(text, text, text, text, text, date) to authenticated;
grant execute on function public.admin_save_billing_settings(bigint, bigint, bigint, bigint, int, int, text, text, text, text) to authenticated;

-- ────────────── 47_no_free_trial.sql ──────────────

-- 47 · no free trial (safe to run again; no data is deleted)
--
--  A landlord can't use Renta UG until they pay a subscription and the main admin confirms it.
--  • New landlords get their payment reference, but no free days.
--  • Free trials that are running now end (ONCE, the first time this file runs). Days the main admin
--    added by hand later ("Add days") are never touched again.
--  • Until confirmed, every change by the landlord is refused by the database (the app also shows only
--    the Subscription, Inbox and Settings pages).
--  • The permanent free account (subscription_exempt) is not affected.

alter table public.billing_settings add column if not exists trial_removed_at timestamptz;
update public.billing_settings set trial_days = 0 where id = 1;

-- ── New landlords: payment reference only ──
create or replace function public.landlord_billing_defaults() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.role = 'landlord' and new.billing_code is null then
    new.billing_code := public.new_billing_code();
  end if;
  return new;
end $$;

-- ── End the running free trials, once ──
do $$
begin
  if (select trial_removed_at from public.billing_settings where id = 1) is null then
    update public.profiles
    set subscription_until = null
    where role = 'landlord' and subscription_plan is null and not subscription_exempt and subscription_until is not null;
    update public.billing_settings set trial_removed_at = now() where id = 1;
  end if;
end $$;

-- ── Guard: no active subscription → no changes; Small scale → no more than the unit limit ──
create or replace function public.require_active_subscription() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  p record;
  v_max int;
begin
  if auth.uid() is null then return coalesce(new, old); end if;
  if not public.landlord_subscribed(auth.uid()) then
    raise exception 'Your Renta UG subscription is not active. Pay on the Subscription page: your account opens as soon as Renta UG confirms the payment.';
  end if;
  if tg_table_name = 'properties' and tg_op = 'INSERT' then
    select role, subscription_exempt, subscription_plan, subscription_tier into p from public.profiles where id = auth.uid();
    if p.role = 'landlord' and not p.subscription_exempt and p.subscription_plan is not null and p.subscription_tier = 'small' then
      select small_max_units into v_max from public.billing_settings where id = 1;
      if public.landlord_unit_count(auth.uid()) >= v_max then
        raise exception 'Small scale covers up to % houses and rooms. Upgrade to Big scale on the Subscription page to add more.', v_max;
      end if;
    end if;
  end if;
  return coalesce(new, old);
end $$;

-- ── Reminders: no trial wording; an ended subscription locks the account ──
create or replace function public.send_subscription_reminders() returns integer
language plpgsql volatile security definer set search_path = '' as $$
declare
  today date := public.kampala_today();
  n integer;
begin
  insert into public.staff_notifications (user_id, type, title, body, url)
  select p.id, 'subscription',
    case when d.left_days < 0 then 'Subscription ended' else 'Subscription ending soon' end,
    case
      when d.left_days < 0 then format('Your Renta UG subscription ended on %s. Your account is locked until you renew and Renta UG confirms the payment.',
        to_char(p.subscription_until, 'FMDD Mon YYYY'))
      when d.left_days = 0 then 'Your Renta UG subscription ends today. Renew now to keep managing your properties without a break.'
      else format('Your Renta UG subscription ends in %s day%s, on %s. Renew any time: the new period is added on top.',
        d.left_days, case when d.left_days = 1 then '' else 's' end, to_char(p.subscription_until, 'FMDD Mon YYYY'))
    end,
    '/landlord/subscription'
  from public.profiles p
  cross join lateral (select p.subscription_until - today as left_days) d
  where p.role = 'landlord' and p.active and not p.subscription_exempt and p.subscription_until is not null
    and d.left_days in (7, 3, 1, 0, -1)
    and not exists (
      select 1 from public.staff_notifications x
      where x.user_id = p.id and x.type = 'subscription' and x.title in ('Subscription ending soon', 'Subscription ended')
        and x.created_at > now() - interval '20 hours'
    );
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.send_subscription_reminders() from public, anon, authenticated;

-- ────────────── 48_no_reason_codes.sql ──────────────

-- 48 · no payment reason codes (safe to run again; no data is deleted)
--
--  Payments are matched by the FULL NAMES registered on the line the money was sent from, not by a
--  reason / reference code typed on the phone.
--  • Landlord subscriptions: the landlord only enters the names registered on the line they paid from.
--    The phone number is optional (older app versions still send it).
--  • Tenants: the landlord is told the names; no more "pay word".
--  • New tenants and landlords no longer get a code. Old codes stay in the database, unused.

-- ── Stop creating codes ──
drop trigger if exists tenants_pay_code on public.tenants;
drop trigger if exists profiles_landlord_billing on public.profiles;

-- ── Subscription payments: phone and reference are optional now ──
alter table public.subscription_payments alter column sender_phone drop not null;
alter table public.subscription_payments alter column reference drop not null;

create or replace function public.submit_subscription_payment(
  p_tier text, p_plan text, p_network text, p_sender_phone text, p_sender_name text, p_paid_on date default null
) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  s public.billing_settings;
  p record;
  v_paid_on date := coalesce(p_paid_on, public.kampala_today());
  v_phone text := nullif(regexp_replace(coalesce(p_sender_phone, ''), '[^0-9+]', '', 'g'), '');
  v_name text := upper(left(regexp_replace(trim(coalesce(p_sender_name, '')), '\s+', ' ', 'g'), 80));
  v_units int;
  v_amount bigint;
  v_id uuid;
begin
  select * into p from public.profiles where id = me;
  if p.role is distinct from 'landlord' then raise exception 'Only landlords have a subscription.'; end if;
  if p.subscription_exempt then raise exception 'Your account is free for life: there is nothing to pay.'; end if;
  if not p.active then raise exception 'This account is suspended. Please contact Renta UG.'; end if;
  if p_tier not in ('small', 'big') then raise exception 'Choose Small scale or Big scale.'; end if;
  if p_plan not in ('monthly', 'yearly') then raise exception 'Choose monthly or yearly.'; end if;
  if p_network not in ('mtn', 'airtel') then raise exception 'Choose MTN or Airtel.'; end if;

  select * into s from public.billing_settings where id = 1;
  v_units := public.landlord_unit_count(me);
  if p_tier = 'small' and v_units > s.small_max_units then
    raise exception 'You have % houses and rooms. Small scale covers up to %, so please choose Big scale.', v_units, s.small_max_units;
  end if;
  if (p_network = 'mtn' and s.mtn_phone is null) or (p_network = 'airtel' and s.airtel_phone is null) then
    raise exception 'Renta UG has not added a number for this network yet.';
  end if;
  if length(v_name) < 5 or v_name !~ '\S+\s+\S+' then
    raise exception 'Enter the full names registered on the line you paid from (at least two names).';
  end if;
  if v_paid_on > public.kampala_today() then raise exception 'The payment date cannot be in the future.'; end if;
  if v_paid_on < public.kampala_today() - 30 then raise exception 'That payment date is more than 30 days ago. Contact Renta UG.'; end if;
  if exists (select 1 from public.subscription_payments where landlord_id = me and status = 'pending') then
    raise exception 'You already have a payment waiting to be confirmed.';
  end if;

  v_amount := case
    when p_tier = 'big' and p_plan = 'yearly' then s.big_yearly
    when p_tier = 'big' then s.big_monthly
    when p_plan = 'yearly' then s.small_yearly
    else s.small_monthly end;

  insert into public.subscription_payments (landlord_id, tier, plan, months, amount, network, sender_phone, sender_name, reference, paid_on)
  values (me, p_tier, p_plan, case p_plan when 'yearly' then 12 else 1 end, v_amount, p_network, v_phone, v_name, null, v_paid_on)
  returning id into v_id;

  insert into public.staff_notifications (user_id, type, title, body, url)
  select id, 'subscription', 'Subscription payment to confirm',
    format('%s says they sent %s to your %s line for %s scale, %s, from a line registered to %s. Check the money, then confirm it.',
      coalesce(nullif(p.full_name, ''), p.email), public.ugx(v_amount),
      case p_network when 'mtn' then 'MTN' else 'Airtel' end, initcap(p_tier), p_plan, v_name),
    '/admin2026/subscriptions'
  from public.profiles where role = 'superadmin';

  return v_id;
end $$;
revoke execute on function public.submit_subscription_payment(text, text, text, text, text, date) from public, anon;
grant execute on function public.submit_subscription_payment(text, text, text, text, text, date) to authenticated;

-- ── Tenants: the landlord's message names the sender, no pay word ──
create or replace function public.submit_payment(
  p_tenant_id uuid,
  p_amount bigint,
  p_paid_on date default null,
  p_note text default null,
  p_method text default 'cash',
  p_network text default null
) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  v_role text;
  v_tenant record;
  v_house text;
  v_rent bigint;
  v_outstanding bigint;
  v_pending bigint;
  v_paid_on date := coalesce(p_paid_on, public.kampala_today());
  v_method text := coalesce(nullif(p_method, ''), 'cash');
  v_network text := nullif(lower(p_network), '');
  v_net_label text;
  v_note text := nullif(trim(p_note), '');
  v_id uuid;
begin
  if v_method not in ('cash', 'mobile_money') then raise exception 'Choose cash or mobile money.'; end if;
  if v_method = 'mobile_money' and v_network is not null and v_network not in ('mtn', 'airtel') then
    raise exception 'Choose MTN or Airtel.';
  end if;
  v_net_label := case v_network when 'mtn' then 'MTN' when 'airtel' then 'Airtel' end;

  select role into v_role from public.profiles where id = me;
  if v_role = 'tenant' then
    select * into v_tenant from public.tenants where id = coalesce(p_tenant_id, public.my_tenant_id()) and user_id = me;
    if not found or v_tenant.property_id is null then raise exception 'You are not connected to a house.'; end if;
    if (select count(*) from public.cash_payments where tenant_id = v_tenant.id and status = 'pending') >= 3 then
      raise exception 'You already have payments waiting for your landlord. Wait for them to be checked first.';
    end if;
    if v_method = 'mobile_money' and not exists (
      select 1 from public.landlord_pay_accounts where landlord_id = v_tenant.landlord_id and network = v_network
    ) then
      raise exception 'Your landlord has not added a number for this network.';
    end if;
    if v_method = 'mobile_money' and coalesce(length(v_note), 0) < 5 then
      raise exception 'Enter the full names registered on the line you paid from.';
    end if;
  elsif public.is_landlord() then
    select * into v_tenant from public.tenants where id = p_tenant_id and landlord_id = me;
    if not found then raise exception 'Tenant not found.'; end if;
    if v_tenant.property_id is null then raise exception 'This tenant no longer rents from you.'; end if;
    v_role := 'landlord';
  else
    raise exception 'Only tenants and landlords can record payments.';
  end if;

  if p_amount is null or p_amount <= 0 then raise exception 'Enter an amount greater than zero.'; end if;
  if v_paid_on > public.kampala_today() then raise exception 'The payment date cannot be in the future.'; end if;
  if v_paid_on < public.kampala_today() - 366 then raise exception 'The payment date is more than a year ago.'; end if;

  select name, rent into v_house, v_rent from public.properties where id = v_tenant.property_id;
  v_outstanding := public.tenant_outstanding(v_tenant.id);
  select coalesce(sum(amount), 0) into v_pending from public.cash_payments where tenant_id = v_tenant.id and status = 'pending';

  if p_amount + v_pending > v_outstanding then
    if coalesce(v_rent, 0) <= 0 then
      raise exception 'This house has no monthly rent set, so money beyond what is owed cannot be recorded.';
    end if;
    if p_amount + v_pending - v_outstanding > v_rent * 24 then
      raise exception '%', format('That pays more than 2 years ahead (rent is %s a month).', public.ugx(v_rent));
    end if;
  end if;

  insert into public.cash_payments (tenant_id, landlord_id, amount, paid_on, note, submitted_by, submitted_role, method, network)
  values (v_tenant.id, v_tenant.landlord_id, p_amount, v_paid_on, v_note, me, v_role, v_method, v_network)
  returning id into v_id;

  if v_role = 'tenant' then
    if v_method = 'mobile_money' then
      insert into public.staff_notifications (user_id, type, title, body, url)
      values (v_tenant.landlord_id, 'cash', 'Mobile money to confirm',
        format('%s says they sent you %s on %s%s. %s. Check your phone, then confirm it.',
          v_tenant.full_name, public.ugx(p_amount), coalesce(v_net_label, 'mobile money'),
          coalesce(' (' || v_house || ')', ''), coalesce(v_note, 'No sender names given')),
        '/landlord/payments');
      insert into public.notifications (landlord_id, tenant_id, type, title, body)
      values (v_tenant.landlord_id, v_tenant.id, 'payment', 'Payment being reviewed',
        format('We received your %s payment of %s. Your landlord is checking it and your rent will be updated soon.',
          coalesce(v_net_label, 'mobile money'), public.ugx(p_amount)));
    else
      insert into public.staff_notifications (user_id, type, title, body, url)
      values (v_tenant.landlord_id, 'cash', 'Cash payment to confirm',
        format('%s says they paid you %s in cash on %s%s. Please confirm the amount you received.',
          v_tenant.full_name, public.ugx(p_amount), to_char(v_paid_on, 'FMDD Mon YYYY'), coalesce(' for ' || v_house, '')),
        '/landlord/payments');
    end if;
  else
    perform public.confirm_cash_payment(v_id, null); -- the landlord received it: it counts now
  end if;

  return v_id;
end $$;
revoke execute on function public.submit_payment(uuid, bigint, date, text, text, text) from public, anon;
grant execute on function public.submit_payment(uuid, bigint, date, text, text, text) to authenticated;

-- ────────────── 49_protected_account.sql ──────────────

-- 49 · the permanent landlord account can never be deleted (safe to run again; no data is deleted)
--
--  ngumisiriza@gmail.com (subscription_exempt, set in 46) is permanent:
--  • its login account and profile cannot be deleted, suspended, demoted or lose the free flag:
--    the database refuses it, whoever asks (app, server, SQL Editor through the API);
--  • "Delete all users" (admin_archive_and_clear) keeps it, with ALL its data: rentals, houses, rooms,
--    tenant records, rent, payments, receipts, notices, inbox, requests to leave, its subscription
--    history, and the app accounts of the tenants renting from it.
--  To ever remove it, someone must first run `alter table ... disable trigger` by hand in Supabase.

-- Make sure the flag is set (again) on the one permanent account
update public.profiles set subscription_exempt = true where lower(email) = 'ngumisiriza@gmail.com' and not subscription_exempt;

-- Self-repair, every time this file runs: if the login exists, it always has a profile that is an
-- ACTIVE LANDLORD, free for life (never pays, never locked) and never banned from signing in.
-- It is listed first on the main admin's Landlords page.
insert into public.profiles (id, email, full_name, role, active, must_change_password, subscription_exempt)
select u.id, lower(u.email), coalesce(nullif(u.raw_user_meta_data ->> 'full_name', ''), 'Ngumisiriza'), 'landlord', true, false, true
from auth.users u
where lower(u.email) = 'ngumisiriza@gmail.com'
on conflict (id) do update
  set role = 'landlord', active = true, subscription_exempt = true, email = excluded.email;
update auth.users set banned_until = null where lower(email) = 'ngumisiriza@gmail.com' and banned_until is not null;

create or replace function public.is_protected_account(p_user uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select subscription_exempt from public.profiles where id = p_user), false);
$$;
revoke execute on function public.is_protected_account(uuid) from public, anon;
grant execute on function public.is_protected_account(uuid) to authenticated, service_role;

-- ── Profile: no delete, no suspension, no role change, flag stays on ──
create or replace function public.guard_protected_profile() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    if old.subscription_exempt then
      raise exception 'This is the permanent Renta UG landlord account. It cannot be deleted.';
    end if;
    return old;
  end if;
  if old.subscription_exempt and (
    not new.subscription_exempt or new.role is distinct from 'landlord' or not new.active
  ) then
    raise exception 'This is the permanent Renta UG landlord account. It cannot be suspended or changed to another kind of account.';
  end if;
  return new;
end $$;

drop trigger if exists profiles_guard_protected on public.profiles;
create trigger profiles_guard_protected
  before update or delete on public.profiles
  for each row execute function public.guard_protected_profile();

-- ── Login account: cannot be deleted (this also blocks the admin API's deleteUser) ──
create or replace function public.guard_protected_auth_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.profiles where id = old.id and subscription_exempt) then
    raise exception 'This is the permanent Renta UG landlord account. It cannot be deleted.';
  end if;
  return old;
end $$;

drop trigger if exists auth_users_guard_protected on auth.users;
create trigger auth_users_guard_protected
  before delete on auth.users
  for each row execute function public.guard_protected_auth_user();

-- ── "Delete all users": everyone except the permanent account (and its tenants), with an archive ──
create or replace function public.admin_archive_and_clear(p_actor uuid, p_note text default null) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_keep_landlords uuid[];
  v_keep_users uuid[];
  v_users uuid[];
  v_gone uuid[]; -- landlords whose data is removed
  v_data jsonb;
  v_counts jsonb;
  v_id uuid;
begin
  if not exists (select 1 from public.profiles where id = p_actor and role = 'superadmin') then
    raise exception 'Only the main admin can do this.';
  end if;

  -- Kept: the permanent landlord(s) and the app accounts of the tenants renting from them
  select coalesce(array_agg(id), '{}') into v_keep_landlords from public.profiles where subscription_exempt;
  select coalesce(array_agg(distinct u), '{}') into v_keep_users from (
    select unnest(v_keep_landlords) as u
    union select user_id from public.tenants where landlord_id = any (v_keep_landlords) and user_id is not null
  ) k;

  select coalesce(array_agg(id), '{}') into v_users
  from public.profiles where role in ('landlord', 'tenant') and not (id = any (v_keep_users));
  select coalesce(array_agg(id), '{}') into v_gone
  from public.profiles where role = 'landlord' and not (id = any (v_keep_landlords));

  -- 1. Full copy of everything that is about to be removed
  v_data := jsonb_build_object(
    'landlords',         coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.profiles x where x.role = 'landlord' and x.id = any (v_users)), '[]'),
    'tenant_accounts',   coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.profiles x where x.role = 'tenant' and x.id = any (v_users)), '[]'),
    'rentals',           coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.rentals x where not (x.landlord_id = any (v_keep_landlords))), '[]'),
    'properties',        coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.properties x where not (x.landlord_id = any (v_keep_landlords))), '[]'),
    'tenants',           coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.tenants x where not (x.landlord_id = any (v_keep_landlords))), '[]'),
    'payments',          coalesce((select jsonb_agg(to_jsonb(x) order by x.period) from public.payments x where not (x.landlord_id = any (v_keep_landlords))), '[]'),
    'payment_receipts',  coalesce((select jsonb_agg(to_jsonb(x) order by x.received_at) from public.payment_receipts x where not (x.landlord_id = any (v_keep_landlords))), '[]'),
    'cash_payments',     coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.cash_payments x where not (x.landlord_id = any (v_keep_landlords))), '[]'),
    'momo_attempts',     coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.momo_attempts x where not (x.landlord_id = any (v_keep_landlords))), '[]'),
    'move_out_requests', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.move_out_requests x where not (x.landlord_id = any (v_keep_landlords))), '[]'),
    'notifications',     coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.notifications x where not (x.landlord_id = any (v_keep_landlords))), '[]'),
    'inbox',             coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.staff_notifications x where x.user_id = any (v_users)), '[]')
  );
  select jsonb_object_agg(k, jsonb_array_length(v)) into v_counts from jsonb_each(v_data) as e(k, v);
  v_counts := v_counts || jsonb_build_object(
    'collected', coalesce((select sum(amount_paid) from public.payments where not (landlord_id = any (v_keep_landlords))), 0),
    'kept_accounts', coalesce(array_length(v_keep_users, 1), 0));

  insert into public.platform_archives (created_by, note, counts, data)
  values (p_actor, nullif(trim(p_note), ''), v_counts, v_data)
  returning id into v_id;

  -- 2. Clear everyone else (children first). The permanent account's data is never touched.
  delete from public.notifications where not (landlord_id = any (v_keep_landlords));
  delete from public.payment_receipts where not (landlord_id = any (v_keep_landlords));
  delete from public.cash_payments where not (landlord_id = any (v_keep_landlords));
  delete from public.momo_attempts where not (landlord_id = any (v_keep_landlords));
  delete from public.move_out_requests where not (landlord_id = any (v_keep_landlords));
  delete from public.payments where not (landlord_id = any (v_keep_landlords));
  delete from public.tenants where not (landlord_id = any (v_keep_landlords));
  delete from public.properties where not (landlord_id = any (v_keep_landlords));
  delete from public.rentals where not (landlord_id = any (v_keep_landlords));
  delete from public.staff_notifications where user_id = any (v_users);
  delete from public.push_subscriptions where user_id = any (v_users);
  delete from public.profiles where id = any (v_users);

  insert into public.admin_audit (actor, action, target_type, target_id, summary)
  values (p_actor, 'platform.clear', 'archive', v_id,
    format('Archived and cleared the platform: %s landlords, %s tenant accounts, %s properties, %s tenant records, %s payments (kept the permanent account and %s linked account%s)',
      v_counts ->> 'landlords', v_counts ->> 'tenant_accounts', v_counts ->> 'properties', v_counts ->> 'tenants', v_counts ->> 'payment_receipts',
      v_counts ->> 'kept_accounts', case when (v_counts ->> 'kept_accounts') = '1' then '' else 's' end));

  return jsonb_build_object('archive_id', v_id, 'counts', v_counts, 'user_ids', to_jsonb(v_users));
end $$;

revoke execute on function public.admin_archive_and_clear(uuid, text) from public, anon, authenticated;
grant execute on function public.admin_archive_and_clear(uuid, text) to service_role;

-- ────────────── 50_permanent_account.sql ──────────────

-- 50 · the permanent landlord account: fixed password, never a first sign-in, data never deleted
--
--  ngumisiriza@gmail.com (see 46 + 49) is permanent:
--  • Its password is fixed. Changing it in the app, by "forgot password" or by an admin reset has no
--    effect: the database keeps it. The password itself is NOT in this file (the code is public). It is
--    set from the private .env with `npm run permanent-account` (scripts/permanent-account.mjs), which
--    calls set_permanent_account() below: the only way to write it, and only with the server key.
--  • It never sees the first-sign-in pages: it is always a ready, active landlord.
--  • Its data (rentals, houses, rooms, tenants, rent, payments, receipts, cash) can only be deleted by
--    the account itself. Admins, the server, "delete all users" and direct database deletes are refused.
--  Safe to run again. No data is deleted.

-- Always a ready landlord: active, free for life, no first-sign-in step, no one-time setup code
update public.profiles
set role = 'landlord', active = true, must_change_password = false, subscription_exempt = true
where lower(email) = 'ngumisiriza@gmail.com'
  and (role <> 'landlord' or not active or must_change_password or not subscription_exempt);
delete from public.setup_codes where user_id in (select id from public.profiles where subscription_exempt);

-- ── Create / repair the login with its fixed password (server key only) ──
create or replace function public.set_permanent_account(p_password text) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_email text := 'ngumisiriza@gmail.com';
  v_id uuid;
begin
  if length(coalesce(p_password, '')) < 6 then raise exception 'The password must be at least 6 characters.'; end if;
  select id into v_id from auth.users where lower(email) = v_email;

  perform set_config('renta.permanent_repair', 'on', true); -- lets the guard below accept this one write
  if v_id is null then
    v_id := gen_random_uuid();
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change, email_change_token_new,
      email_change_token_current, phone_change, phone_change_token, reauthentication_token
    ) values (
      '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
      extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}', '{"full_name":"Ngumisiriza"}', now(), now(),
      '', '', '', '', '', '', '', ''
    );
  else
    update auth.users
    set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
        email_confirmed_at = coalesce(email_confirmed_at, now()),
        banned_until = null,
        updated_at = now()
    where id = v_id;
  end if;
  perform set_config('renta.permanent_repair', 'off', true);

  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), v_id, v_id::text,
    jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true), 'email', now(), now(), now())
  on conflict (provider_id, provider) do nothing;

  insert into public.profiles (id, email, full_name, role, active, must_change_password, subscription_exempt)
  values (v_id, v_email, 'Ngumisiriza', 'landlord', true, false, true)
  on conflict (id) do update
    set email = excluded.email, role = 'landlord', active = true, must_change_password = false, subscription_exempt = true;
  delete from public.setup_codes where user_id = v_id;
  return v_id;
end $$;
revoke execute on function public.set_permanent_account(text) from public, anon, authenticated;
grant execute on function public.set_permanent_account(text) to service_role;

-- ── Login: the password and email never change, and it is never banned ──
create or replace function public.guard_permanent_login() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(current_setting('renta.permanent_repair', true), 'off') = 'on' then return new; end if;
  if exists (select 1 from public.profiles where id = old.id and subscription_exempt) then
    new.encrypted_password := old.encrypted_password;
    new.email := old.email;
    new.banned_until := null;
  end if;
  return new;
end $$;

drop trigger if exists auth_users_permanent_login on auth.users;
create trigger auth_users_permanent_login
  before update on auth.users
  for each row execute function public.guard_permanent_login();

-- ── Profile: never a first sign-in, never suspended or demoted (49 refuses those; this also fixes
--    must_change_password and re-applies the flags if the profile is ever created again) ──
create or replace function public.guard_protected_profile() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    if old.subscription_exempt then
      raise exception 'This is the permanent Renta UG landlord account. It cannot be deleted.';
    end if;
    return old;
  end if;
  if old.subscription_exempt and (not new.subscription_exempt or new.role is distinct from 'landlord' or not new.active) then
    raise exception 'This is the permanent Renta UG landlord account. It cannot be suspended or changed to another kind of account.';
  end if;
  if new.subscription_exempt then new.must_change_password := false; end if;
  return new;
end $$;

create or replace function public.permanent_profile_on_insert() returns trigger
language plpgsql set search_path = '' as $$
begin
  if lower(coalesce(new.email, '')) = 'ngumisiriza@gmail.com' then
    new.role := 'landlord';
    new.active := true;
    new.must_change_password := false;
    new.subscription_exempt := true;
  end if;
  return new;
end $$;

drop trigger if exists profiles_permanent_insert on public.profiles;
create trigger profiles_permanent_insert
  before insert on public.profiles
  for each row execute function public.permanent_profile_on_insert();

-- ── Data: only the account itself can delete its own records ──
-- Admin functions, the server (service role) and "delete all users" are refused.
create or replace function public.guard_permanent_data() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.profiles where id = old.landlord_id and subscription_exempt)
     and auth.uid() is distinct from old.landlord_id then
    raise exception 'This belongs to the permanent Renta UG landlord account and cannot be deleted.';
  end if;
  return old;
end $$;

do $$
declare t text;
begin
  foreach t in array array['rentals', 'properties', 'tenants', 'payments', 'payment_receipts', 'cash_payments'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_guard_permanent', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.guard_permanent_data()', t || '_guard_permanent', t);
  end loop;
end $$;

-- ────────────── 51_capacity_and_cash_subscriptions.sql ──────────────

-- 51 · business size at first sign-in + subscriptions paid in cash (safe to run again; no data is deleted)
--
--  Business size
--   • Right after a new landlord creates their password, they say how many houses and rooms they will
--     register (profiles.planned_units). Renta UG recommends the package that fits it, and Small scale
--     can't be chosen when the number is above its limit.
--   • The main admin sees the number on the landlord's page.
--
--  Cash
--   • The main admin can record a subscription the landlord paid in cash: choose the landlord, the package
--     (Small / Big) and monthly / yearly. It is saved as a confirmed payment (network 'cash') and the
--     subscription is extended at once, on top of any time left, exactly like a confirmed mobile money payment.

-- ── Business size ──
alter table public.profiles add column if not exists planned_units int;
do $$ begin
  alter table public.profiles add constraint profiles_planned_units_check check (planned_units is null or planned_units between 1 and 100000);
exception when duplicate_object then null; end $$;

create or replace function public.set_planned_units(p_units int) returns void
language plpgsql volatile security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role = 'landlord') then
    raise exception 'Only landlords can set this.';
  end if;
  if p_units is null or p_units < 1 or p_units > 100000 then
    raise exception 'Enter how many houses and rooms you will register (at least 1).';
  end if;
  update public.profiles set planned_units = p_units where id = auth.uid();
end $$;
revoke execute on function public.set_planned_units(int) from public, anon;
grant execute on function public.set_planned_units(int) to authenticated;

-- ── Cash: a payment can also be 'cash' (recorded by the main admin) ──
alter table public.subscription_payments drop constraint if exists subscription_payments_network_check;
alter table public.subscription_payments add constraint subscription_payments_network_check check (network in ('mtn', 'airtel', 'cash'));
alter table public.subscription_payments add column if not exists note text;

create or replace function public.admin_record_subscription_cash(
  p_landlord uuid, p_tier text, p_plan text, p_paid_on date default null, p_note text default null
) returns json
language plpgsql volatile security definer set search_path = '' as $$
declare
  s public.billing_settings;
  p record;
  v_paid_on date := coalesce(p_paid_on, public.kampala_today());
  v_note text := nullif(left(trim(coalesce(p_note, '')), 200), '');
  v_units int;
  v_amount bigint;
  v_months int;
  v_start date;
  v_end date;
  v_id uuid;
begin
  perform public.admin_require();
  select * into p from public.profiles where id = p_landlord and role = 'landlord' for update;
  if not found then raise exception 'Landlord not found.'; end if;
  if p.subscription_exempt then raise exception 'This is the permanent free account: there is nothing to pay.'; end if;
  if p_tier not in ('small', 'big') then raise exception 'Choose Small scale or Big scale.'; end if;
  if p_plan not in ('monthly', 'yearly') then raise exception 'Choose monthly or yearly.'; end if;
  if v_paid_on > public.kampala_today() then raise exception 'The payment date cannot be in the future.'; end if;
  if v_paid_on < public.kampala_today() - 366 then raise exception 'The payment date is more than a year ago.'; end if;

  select * into s from public.billing_settings where id = 1;
  v_units := public.landlord_unit_count(p_landlord);
  if p_tier = 'small' and v_units > s.small_max_units then
    raise exception 'This landlord has % houses and rooms. Small scale covers up to %, so choose Big scale.', v_units, s.small_max_units;
  end if;

  v_amount := case
    when p_tier = 'big' and p_plan = 'yearly' then s.big_yearly
    when p_tier = 'big' then s.big_monthly
    when p_plan = 'yearly' then s.small_yearly
    else s.small_monthly end;
  v_months := case p_plan when 'yearly' then 12 else 1 end;

  -- On top of any time left, otherwise from today
  v_start := case when p.subscription_until >= public.kampala_today() then p.subscription_until + 1 else public.kampala_today() end;
  v_end := (v_start + make_interval(months => v_months) - interval '1 day')::date;

  insert into public.subscription_payments (
    landlord_id, tier, plan, months, amount, network, sender_phone, sender_name, reference, paid_on,
    status, period_start, period_end, reviewed_by, reviewed_at, note
  ) values (
    p_landlord, p_tier, p_plan, v_months, v_amount, 'cash', null, 'CASH', null, v_paid_on,
    'confirmed', v_start, v_end, auth.uid(), now(), v_note
  ) returning id into v_id;

  update public.profiles set subscription_until = v_end, subscription_plan = p_plan, subscription_tier = p_tier where id = p_landlord;

  insert into public.staff_notifications (user_id, type, title, body, url)
  values (p_landlord, 'subscription', 'Subscription paid in cash',
    format('Thank you! Renta UG received your cash payment of %s for %s scale, %s. Your subscription now runs until %s.',
      public.ugx(v_amount), initcap(p_tier), p_plan, to_char(v_end, 'FMDD Mon YYYY')),
    '/landlord/subscription');
  perform public.admin_log('subscription.cash', 'landlord', p_landlord,
    format('Recorded %s cash for %s scale %s subscription from %s, now runs to %s%s', public.ugx(v_amount), p_tier, p_plan,
      coalesce(nullif(p.full_name, ''), p.email), to_char(v_end, 'FMDD Mon YYYY'), coalesce(' (' || v_note || ')', '')));

  return json_build_object('id', v_id, 'amount', v_amount, 'start', v_start, 'until', v_end);
end $$;
revoke execute on function public.admin_record_subscription_cash(uuid, text, text, date, text) from public, anon;
grant execute on function public.admin_record_subscription_cash(uuid, text, text, date, text) to authenticated;

-- ────────────── 52_part_payment_days.sql ──────────────

-- 52 · part payments buy DAYS (safe to run again; no data is deleted)
--
--  A tenant can pay any part of a month's rent. The money buys rental time in proportion:
--    days = amount paid on that month ÷ the month's rent × 30   (rounded down)
--  e.g. half the rent → 15 days. Paying the rest later ("Complete payment") tops the same month up:
--  once the month is paid in full it counts as one whole rent month. A rent month is ALWAYS 30 days
--  (not 28, 29 or 31). The days already given are part of it, never counted twice.
--  Replaces the old rule (a whole month as soon as 60% was paid). Months that already got their whole
--  month under the old rule keep it (month_credited = true), so nobody loses time.
--
--  payments.credited_days   days of rental time this rent month has given so far (part payments)
--  payments.month_credited  true once the month has given its whole month

-- New columns; the months that already counted (paid, or 60%+ under the old rule) are marked ONCE,
-- only when the columns are first added.
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'payments' and column_name = 'month_credited'
  ) then
    alter table public.payments add column credited_days int not null default 0;
    alter table public.payments add column month_credited boolean not null default false;
    update public.payments
    set month_credited = true
    where amount > 0 and (status = 'paid' or amount_paid * 10 >= amount * 6);
  end if;
end $$;
alter table public.payments add column if not exists credited_days int not null default 0;

-- Rental time grows as money comes in (runs BEFORE the row is saved, so it can record what it gave)
create or replace function public.extend_rental_time() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_day date := (coalesce(new.paid_at, now()) at time zone 'Africa/Kampala')::date;
  v_days int;
  v_add interval;
begin
  if new.amount is null or new.amount <= 0 or new.month_credited then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.amount_paid <= coalesce(old.amount_paid, 0) and new.status is not distinct from old.status then
    return new;
  end if;

  if new.status = 'paid' or new.amount_paid >= new.amount then
    -- Paid in full: one rent month = 30 days (never 28 or 31), less the days already given for it
    v_add := make_interval(days => 30 - coalesce(new.credited_days, 0));
    new.month_credited := true;
  else
    v_days := floor(new.amount_paid::numeric * 30 / new.amount)::int;
    if v_days <= coalesce(new.credited_days, 0) then
      return new;
    end if;
    v_add := make_interval(days => v_days - coalesce(new.credited_days, 0));
    new.credited_days := v_days;
  end if;

  -- New tenant: from their start date (the confirmation sets it to the day paid). Otherwise straight on
  -- from the old end, so late (debt) days are not given back.
  update public.tenants
  set lease_start = coalesce(lease_start, v_day),
      lease_end = (coalesce(lease_end, lease_start, v_day) + v_add)::date
  where id = new.tenant_id and property_id is not null;
  return new;
end $$;

drop trigger if exists payments_extend_rental_time on public.payments;
create trigger payments_extend_rental_time
  before insert or update of status, amount_paid on public.payments
  for each row execute function public.extend_rental_time();

-- ────────────── 53_subscription_30_day_months.sql ──────────────

-- 53 · landlord subscriptions: a month is 30 days (safe to run again; no data is deleted)
--
--  Monthly subscription = exactly 30 days (never 28, 29 or 31), like rent months (database/52).
--  Yearly subscription  = 365 days.
--  Periods already confirmed keep their dates; this applies to payments confirmed from now on, whether
--  confirmed from mobile money (admin_confirm_subscription_payment) or recorded as cash
--  (admin_record_subscription_cash).

create or replace function public.subscription_days(p_months int) returns int
language sql immutable set search_path = '' as $$
  select case when p_months >= 12 then 365 * (p_months / 12) + 30 * (p_months % 12) else 30 * greatest(p_months, 1) end;
$$;
revoke execute on function public.subscription_days(int) from public, anon;
grant execute on function public.subscription_days(int) to authenticated, service_role;

-- ── Main admin: confirm a mobile money payment → on top of any time left ──
create or replace function public.admin_confirm_subscription_payment(p_id uuid) returns json
language plpgsql volatile security definer set search_path = '' as $$
declare
  r public.subscription_payments;
  p record;
  v_start date;
  v_end date;
begin
  perform public.admin_require();
  select * into r from public.subscription_payments where id = p_id for update;
  if not found then raise exception 'Payment not found.'; end if;
  if r.status <> 'pending' then raise exception 'This payment has already been %.', r.status; end if;
  select * into p from public.profiles where id = r.landlord_id for update;

  v_start := case when p.subscription_until >= public.kampala_today() then p.subscription_until + 1 else public.kampala_today() end;
  v_end := v_start + public.subscription_days(r.months) - 1;

  update public.profiles set subscription_until = v_end, subscription_plan = r.plan, subscription_tier = r.tier where id = r.landlord_id;
  update public.subscription_payments
  set status = 'confirmed', period_start = v_start, period_end = v_end, reviewed_by = auth.uid(), reviewed_at = now()
  where id = r.id;

  insert into public.staff_notifications (user_id, type, title, body, url)
  values (r.landlord_id, 'subscription', 'Subscription renewed',
    format('Thank you! Your %s scale %s payment of %s was received. Your Renta UG subscription now runs until %s (%s days).',
      initcap(r.tier), r.plan, public.ugx(r.amount), to_char(v_end, 'FMDD Mon YYYY'), public.subscription_days(r.months)),
    '/landlord/subscription');
  perform public.admin_log('subscription.confirm', 'landlord', r.landlord_id,
    format('Confirmed %s %s scale %s subscription from %s, now runs to %s', public.ugx(r.amount), r.tier, r.plan,
      coalesce(nullif(p.full_name, ''), p.email), to_char(v_end, 'FMDD Mon YYYY')));
  return json_build_object('until', v_end, 'start', v_start);
end $$;

-- ── Main admin: a subscription paid in cash → recorded as paid, extended at once ──
create or replace function public.admin_record_subscription_cash(
  p_landlord uuid, p_tier text, p_plan text, p_paid_on date default null, p_note text default null
) returns json
language plpgsql volatile security definer set search_path = '' as $$
declare
  s public.billing_settings;
  p record;
  v_paid_on date := coalesce(p_paid_on, public.kampala_today());
  v_note text := nullif(left(trim(coalesce(p_note, '')), 200), '');
  v_units int;
  v_amount bigint;
  v_months int;
  v_start date;
  v_end date;
  v_id uuid;
begin
  perform public.admin_require();
  select * into p from public.profiles where id = p_landlord and role = 'landlord' for update;
  if not found then raise exception 'Landlord not found.'; end if;
  if p.subscription_exempt then raise exception 'This is the permanent free account: there is nothing to pay.'; end if;
  if p_tier not in ('small', 'big') then raise exception 'Choose Small scale or Big scale.'; end if;
  if p_plan not in ('monthly', 'yearly') then raise exception 'Choose monthly or yearly.'; end if;
  if v_paid_on > public.kampala_today() then raise exception 'The payment date cannot be in the future.'; end if;
  if v_paid_on < public.kampala_today() - 366 then raise exception 'The payment date is more than a year ago.'; end if;

  select * into s from public.billing_settings where id = 1;
  v_units := public.landlord_unit_count(p_landlord);
  if p_tier = 'small' and v_units > s.small_max_units then
    raise exception 'This landlord has % houses and rooms. Small scale covers up to %, so choose Big scale.', v_units, s.small_max_units;
  end if;

  v_amount := case
    when p_tier = 'big' and p_plan = 'yearly' then s.big_yearly
    when p_tier = 'big' then s.big_monthly
    when p_plan = 'yearly' then s.small_yearly
    else s.small_monthly end;
  v_months := case p_plan when 'yearly' then 12 else 1 end;

  v_start := case when p.subscription_until >= public.kampala_today() then p.subscription_until + 1 else public.kampala_today() end;
  v_end := v_start + public.subscription_days(v_months) - 1;

  insert into public.subscription_payments (
    landlord_id, tier, plan, months, amount, network, sender_phone, sender_name, reference, paid_on,
    status, period_start, period_end, reviewed_by, reviewed_at, note
  ) values (
    p_landlord, p_tier, p_plan, v_months, v_amount, 'cash', null, 'CASH', null, v_paid_on,
    'confirmed', v_start, v_end, auth.uid(), now(), v_note
  ) returning id into v_id;

  update public.profiles set subscription_until = v_end, subscription_plan = p_plan, subscription_tier = p_tier where id = p_landlord;

  insert into public.staff_notifications (user_id, type, title, body, url)
  values (p_landlord, 'subscription', 'Subscription paid in cash',
    format('Thank you! Renta UG received your cash payment of %s for %s scale, %s. Your subscription now runs until %s (%s days).',
      public.ugx(v_amount), initcap(p_tier), p_plan, to_char(v_end, 'FMDD Mon YYYY'), public.subscription_days(v_months)),
    '/landlord/subscription');
  perform public.admin_log('subscription.cash', 'landlord', p_landlord,
    format('Recorded %s cash for %s scale %s subscription from %s, now runs to %s%s', public.ugx(v_amount), p_tier, p_plan,
      coalesce(nullif(p.full_name, ''), p.email), to_char(v_end, 'FMDD Mon YYYY'), coalesce(' (' || v_note || ')', '')));

  return json_build_object('id', v_id, 'amount', v_amount, 'start', v_start, 'until', v_end);
end $$;
revoke execute on function public.admin_record_subscription_cash(uuid, text, text, date, text) from public, anon;
grant execute on function public.admin_record_subscription_cash(uuid, text, text, date, text) to authenticated;

-- ────────────── 54_browser_write_limits.sql ──────────────

-- 54 · what the browser may write (safe to run again; no data is deleted)
--
--  The app talks to the database straight from the browser. Row rules (08) already stop anyone touching
--  another person's rows; this file also limits WHICH columns and values a signed-in user can write, so
--  nobody can edit the database through the browser beyond what the app itself does:
--   • Rent months, payments and receipts: written only by the database functions (confirming a payment,
--     recording cash…). A landlord can no longer insert, change or delete them directly.
--   • Tenants: only the fields the app edits (name, email, phone, house, managed / ended). Rental time
--     (lease dates), the linked app account and the connection code are set by the database only.
--   • Notices from a landlord: always a plain "general" notice, 1–1,000 characters. Nobody can fake a
--     "payment confirmation" or a security alert.
--   • Sensible sizes for names, phone numbers, addresses and rents.
--  Database functions (security definer) and the server are not affected.

-- ── Rent months, payments, receipts: database functions only ──
revoke insert, update, delete on public.payments from anon, authenticated;
revoke insert, update, delete on public.payment_receipts from anon, authenticated;

-- ── Tenants: only the fields the app edits ──
revoke insert, update on public.tenants from anon, authenticated;
grant insert (full_name, email, phone, property_id, managed_by_landlord) on public.tenants to authenticated;
grant update (full_name, email, phone, property_id, last_property_id, ended_at, managed_by_landlord) on public.tenants to authenticated;

-- ── Notices written from the app ──
revoke insert on public.notifications from anon, authenticated;
grant insert (tenant_id, type, title, body) on public.notifications to authenticated;

create or replace function public.guard_app_notice() returns trigger
language plpgsql set search_path = '' as $$
begin
  -- Only writes made directly from the browser; database functions run as the owner and are not limited
  if current_user in ('authenticated', 'anon') then
    new.type := 'general';
    new.title := left(trim(coalesce(new.title, '')), 120);
    new.body := trim(coalesce(new.body, ''));
    if length(new.body) < 1 or length(new.body) > 1000 then
      raise exception 'Write a message of up to 1,000 characters.';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists notifications_guard_app on public.notifications;
create trigger notifications_guard_app
  before insert on public.notifications
  for each row execute function public.guard_app_notice();

-- ── Sensible sizes (checked for new and changed rows; old rows are left as they are) ──
do $$
declare c text[];
begin
  foreach c slice 1 in array array[
    array['properties', 'properties_rent_range', 'check (rent is null or (rent >= 0 and rent <= 100000000000))'],
    array['properties', 'properties_name_length', 'check (char_length(name) between 1 and 120)'],
    array['properties', 'properties_location_length', 'check (location is null or char_length(location) <= 200)'],
    array['rentals', 'rentals_name_length', 'check (char_length(name) between 1 and 120)'],
    array['rentals', 'rentals_location_length', 'check (location is null or char_length(location) <= 200)'],
    array['tenants', 'tenants_name_length', 'check (char_length(full_name) between 1 and 120)'],
    array['tenants', 'tenants_email_length', 'check (email is null or char_length(email) <= 254)'],
    array['tenants', 'tenants_phone_length', 'check (phone is null or char_length(phone) <= 30)'],
    array['profiles', 'profiles_name_length', 'check (full_name is null or char_length(full_name) <= 120)'],
    array['profiles', 'profiles_phone_length', 'check (phone is null or char_length(phone) <= 30)'],
    array['landlord_pay_accounts', 'pay_accounts_name_length', 'check (char_length(account_name) between 1 and 80)'],
    array['landlord_pay_accounts', 'pay_accounts_phone_length', 'check (char_length(phone) between 9 and 20)']
  ] loop
    begin
      execute format('alter table public.%I add constraint %I %s not valid', c[1], c[2], c[3]);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;
