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
