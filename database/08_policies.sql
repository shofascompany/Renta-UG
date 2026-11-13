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
