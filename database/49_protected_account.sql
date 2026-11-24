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
