-- ============================================================================
-- Renta UG · update an EXISTING database (GENERATED, do not edit, run `npm run db:bundle`)
--
-- Keeps all data. Re-applies the security policies and newer additions.
-- Paste the whole file into Supabase → SQL Editor → Run. Safe to run more than once.
--
-- Includes: 07_functions.sql, 11_backfill_profiles.sql, 13_first_login_password.sql, 14_tenant_records.sql, 15_tenant_stays.sql, 08_policies.sql, 09_realtime.sql, 16_reminders_push_momo.sql, 17_cash_receipts_inbox.sql, 18_smart_notifications.sql, 19_login_email_check.sql
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
alter table public.notifications
  add constraint notifications_type_check check (type in ('general', 'maintenance', 'payment', 'reminder'));
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
