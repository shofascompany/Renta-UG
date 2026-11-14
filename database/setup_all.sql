-- ============================================================================
-- Renta UG · full database setup (GENERATED, do not edit, run `npm run db:bundle`)
--
-- ⚠ Starts by DELETING all existing Renta tables and data, then recreates everything.
-- Paste the whole file into Supabase → SQL Editor → Run.
-- It also creates the main admin login (12_main_admin.sql); sign in at /admin2026.
--
-- Includes: 00_reset.sql, 01_profiles.sql, 02_properties.sql, 03_tenants.sql, 04_payments.sql, 05_notifications.sql, 07_functions.sql, 08_policies.sql, 09_realtime.sql, 11_backfill_profiles.sql, 12_main_admin.sql, 13_first_login_password.sql, 14_tenant_records.sql, 15_tenant_stays.sql, 16_reminders_push_momo.sql, 17_cash_receipts_inbox.sql, 18_smart_notifications.sql, 19_login_email_check.sql, 20_login_phone_check.sql, 21_recharge.sql, 22_month_start_notices.sql, 23_notification_delete.sql, 24_cash_confirmation.sql, 25_tenant_phone_first_login.sql, 26_rentals.sql, 27_one_house_per_tenant.sql, 28_cash_any_time.sql, 29_paid_rental_time.sql, 30_move_out_requests.sql, 31_calm_notifications.sql, 32_admin_console.sql, 33_landlord_owns_issues.sql, 34_archive_and_clear.sql
-- ============================================================================

-- ────────────── 00_reset.sql ──────────────

-- 00 · reset
-- ⚠ Deletes ALL Renta tables and their data (properties, tenants, payments, notifications,
-- alerts, profiles). Login accounts in Supabase Auth are kept.

drop trigger if exists on_auth_user_created on auth.users;

drop table if exists
  public.platform_archives,
  public.admin_audit,
  public.move_out_requests,
  public.staff_notifications,
  public.payment_receipts,
  public.momo_attempts,
  public.push_subscriptions,
  public.alerts,
  public.notifications,
  public.payments,
  public.tenants,
  public.properties,
  public.rentals,
  public.profiles
cascade;

drop function if exists public.handle_new_user() cascade;
drop function if exists public.link_tenant_user() cascade;
drop function if exists public.new_connect_code(uuid) cascade;
drop function if exists public.redeem_connect_code(text) cascade;
drop function if exists public.complete_password_setup() cascade;
drop function if exists public.send_lease_reminders() cascade;
drop function if exists public.record_cash_payment(uuid, bigint, timestamptz, text) cascade;
drop function if exists public.save_push_subscription(text, text, text) cascade;
drop function if exists public.delete_push_subscription(text) cascade;
drop function if exists public.readd_tenant(uuid, uuid, text, text, text, date, date) cascade;
drop function if exists public.set_tenant_person_id() cascade;
drop function if exists public.my_property_id() cascade;
drop function if exists public.my_landlord_id() cascade;
drop function if exists public.owns_property(uuid) cascade;
drop function if exists public.owns_tenant(uuid) cascade;
drop function if exists public.is_admin() cascade;
drop function if exists public.is_superadmin() cascade;
drop function if exists public.is_landlord() cascade;
drop function if exists public.my_tenant_id() cascade;
drop function if exists public.check_one_house_per_tenant() cascade;
drop function if exists public.my_rental_id() cascade;
drop function if exists public.next_rent_period(uuid) cascade;
drop function if exists public.extend_rental_time() cascade;
drop function if exists public.request_move_out(int, text, text, text) cascade;
drop function if exists public.cancel_move_out() cascade;
drop function if exists public.decide_move_out(uuid, boolean, text) cascade;
drop function if exists public.finish_move_out() cascade;
drop function if exists public.admin_require() cascade;
drop function if exists public.admin_log(text, text, uuid, text) cascade;
drop function if exists public.admin_update_property(uuid, text, text, bigint) cascade;
drop function if exists public.admin_delete_property(uuid) cascade;
drop function if exists public.admin_update_tenant(uuid, text, text, text) cascade;
drop function if exists public.admin_end_tenancy(uuid, text) cascade;
drop function if exists public.admin_broadcast(text, uuid, text) cascade;
drop function if exists public.admin_note(text, text, uuid, text) cascade;
drop function if exists public.admin_archive_and_clear(uuid, text) cascade;

-- ────────────── 01_profiles.sql ──────────────

-- 01 · profiles
-- One row per login account (created automatically on sign-up, see 07_functions.sql).
-- role:
--   superadmin → the main admin from .env (ADMIN_*), signs in at /admin2026, monitors everything
--   landlord   → registered by the main admin, manages their own properties and tenants
--   tenant     → signs up themselves, connects to a landlord with a code

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  full_name text,
  phone text,
  role text not null default 'tenant' check (role in ('superadmin', 'landlord', 'tenant')),
  active boolean not null default true, -- false = landlord suspended by the main admin
  created_at timestamptz not null default now()
);

-- ────────────── 02_properties.sql ──────────────

-- 02 · properties
-- Houses/units, each owned by a landlord.

create table public.properties (
  id uuid primary key default gen_random_uuid(),
  landlord_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  location text not null,
  type text not null default 'Apartment',
  bedrooms int not null default 1,
  bathrooms int not null default 1,
  rent bigint not null check (rent >= 0), -- monthly rent in whole UGX
  created_at timestamptz not null default now()
);

create index properties_landlord_id_idx on public.properties (landlord_id);

-- ────────────── 03_tenants.sql ──────────────

-- 03 · tenants
-- People renting a property, added by their landlord.
-- The tenant creates their own account, then enters a connection code (valid 20 minutes)
-- that the landlord generates; that fills in `user_id` (see 07_functions.sql).
-- `property_id` is null for former tenants (history is kept).

create table public.tenants (
  id uuid primary key default gen_random_uuid(),
  landlord_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  user_id uuid unique references auth.users (id) on delete set null,
  property_id uuid references public.properties (id) on delete set null,
  full_name text not null,
  email text,
  phone text,
  lease_start date,
  lease_end date,
  connect_code text unique,              -- 6-character code shared with the tenant
  connect_code_expires_at timestamptz,   -- code stops working after this
  last_property_id uuid references public.properties (id) on delete set null, -- house before the tenancy ended
  ended_at timestamptz,                  -- when the tenancy ended (null = current tenant)
  created_at timestamptz not null default now()
);

create unique index tenants_landlord_email_key on public.tenants (landlord_id, lower(email));
create index tenants_landlord_id_idx on public.tenants (landlord_id);
create index tenants_property_id_idx on public.tenants (property_id);

-- ────────────── 04_payments.sql ──────────────

-- 04 · payments
-- One rent charge per tenant per month. Starts as 'pending'; becomes 'paid' when fully paid by mobile
-- money (verified by the server) or cash recorded by the landlord (part payments: see 17).
-- "Overdue" is not stored: the app derives it from due_date.

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  landlord_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  property_id uuid references public.properties (id) on delete set null,
  period text not null check (period ~ '^\d{4}-\d{2}$'), -- YYYY-MM
  amount bigint not null check (amount > 0),             -- whole UGX
  due_date date not null,
  status text not null default 'pending' check (status in ('pending', 'paid')),
  paid_at timestamptz,
  method text,     -- MTN Mobile Money, Airtel Money, Cash
  reference text,  -- mobile money transaction reference
  created_at timestamptz not null default now(),
  unique (tenant_id, period)
);

create index payments_landlord_id_idx on public.payments (landlord_id);
create index payments_tenant_id_idx on public.payments (tenant_id);

-- ────────────── 05_notifications.sql ──────────────

-- 05 · notifications
-- Messages from a landlord (or the system) to one of their tenants.

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  landlord_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  type text not null default 'general' check (type in ('general', 'maintenance', 'payment')),
  title text not null,
  body text not null,
  read boolean not null default false,
  created_at timestamptz not null default now()
);

create index notifications_landlord_id_idx on public.notifications (landlord_id);
create index notifications_tenant_id_idx on public.notifications (tenant_id);

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

-- ────────────── 11_backfill_profiles.sql ──────────────

-- 11 · backfill profiles
-- Gives a profile to any login account that existed before the tables were (re)created,
-- so people who already signed up can still sign in. Safe to run any time.

insert into public.profiles (id, email, full_name)
select u.id, u.email, coalesce(u.raw_user_meta_data ->> 'full_name', split_part(u.email, '@', 1))
from auth.users u
on conflict (id) do nothing;

-- ────────────── 12_main_admin.sql ──────────────

-- 12 · main admin (superadmin)
-- Creates the main admin login directly in the database, or resets it if it already exists.
-- The main admin signs in at /admin2026.
--
-- To change any detail: edit the values below and run this file again
-- (it is also included in setup_all.sql). Safe to run any time.

do $$
declare
  v_email    text := 'shofascompany@gmail.com';
  v_password text := '1234man.';
  v_name     text := 'Abraham';
  v_phone    text := '0703089488';
  v_id       uuid;
begin
  v_email := lower(trim(v_email));
  select id into v_id from auth.users where lower(email) = v_email;

  if v_id is null then
    -- New login account, already email-confirmed
    v_id := gen_random_uuid();
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change, email_change_token_new,
      email_change_token_current, phone_change, phone_change_token, reauthentication_token
    ) values (
      '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
      extensions.crypt(v_password, extensions.gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}', jsonb_build_object('full_name', v_name), now(), now(),
      '', '', '', '', '', '', '', ''
    );
  else
    -- Existing account: force the password, confirm the email, lift any suspension
    update auth.users
    set encrypted_password = extensions.crypt(v_password, extensions.gen_salt('bf')),
        email_confirmed_at = coalesce(email_confirmed_at, now()),
        banned_until = null,
        raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('full_name', v_name),
        updated_at = now()
    where id = v_id;
  end if;

  -- Email/password identity (needed for sign-in)
  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (
    gen_random_uuid(), v_id, v_id::text,
    jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true),
    'email', now(), now(), now()
  )
  on conflict (provider_id, provider) do nothing;

  -- Make it the one and only main admin
  insert into public.profiles (id, email, full_name, phone, role, active)
  values (v_id, v_email, v_name, v_phone, 'superadmin', true)
  on conflict (id) do update
    set email = excluded.email, full_name = excluded.full_name, phone = excluded.phone,
        role = 'superadmin', active = true;

  update public.profiles set role = 'tenant' where role = 'superadmin' and id <> v_id;
end $$;

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
