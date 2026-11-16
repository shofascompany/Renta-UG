-- ============================================================================
-- ⚠ DELETE ALL LANDLORD AND TENANT ACCOUNTS. THIS CANNOT BE UNDONE.
--
-- Removes every landlord and tenant login, and everything they entered: rental businesses,
-- properties, tenant records, rent months, payments, receipts, cash, mobile money attempts,
-- requests to leave, notifications, inbox messages and registered phones.
--
-- KEPT: the main admin account (role = superadmin), the activity log, and the archives.
--       If 34_archive_and_clear.sql has been run, a full copy of everything is saved to the
--       archive FIRST, so the main admin can still view it under Health & settings → Archives.
-- The tables, security rules and functions are kept, so the app keeps working.
--
-- Same as the "Delete all users" button in the main admin console.
-- Paste into Supabase → SQL Editor → Run. Not included in setup_all.sql.
-- ============================================================================

do $$
declare
  v_admin     uuid;
  v_users     uuid[];
  n_landlords int;
  n_tenants   int;
  v_archived  boolean := false;
  t           text;
begin
  select id into v_admin from public.profiles where role = 'superadmin' order by created_at limit 1;
  if v_admin is null then
    raise exception 'No main admin account found. Run 12_main_admin.sql first so you are not locked out.';
  end if;

  select count(*) filter (where role = 'landlord'), count(*) filter (where role = 'tenant')
    into n_landlords, n_tenants
  from public.profiles;

  -- Every login that isn't a main admin (including any login whose profile is missing)
  select coalesce(array_agg(u.id), '{}') into v_users
  from auth.users u
  where not exists (select 1 from public.profiles p where p.id = u.id and p.role = 'superadmin');

  -- 1. Save a full copy first (needs 34_archive_and_clear.sql)
  if to_regprocedure('public.admin_archive_and_clear(uuid, text)') is not null then
    perform public.admin_archive_and_clear(v_admin, 'Cleared from the SQL Editor');
    v_archived := true;
  end if;

  -- 2. Clear everything they entered (children first; tables that don't exist are skipped)
  foreach t in array array[
    'notifications', 'payment_receipts', 'cash_payments', 'momo_attempts', 'move_out_requests',
    'payments', 'tenants', 'properties', 'rentals', 'email_verifications'
  ] loop
    if to_regclass('public.' || t) is not null then
      execute format('delete from public.%I where true', t);
    end if;
  end loop;
  delete from public.staff_notifications where user_id = any (v_users);
  if to_regclass('public.push_subscriptions') is not null then
    delete from public.push_subscriptions where user_id = any (v_users);
  end if;
  delete from public.profiles where id = any (v_users);

  -- 3. Remove the logins themselves (their sessions and identities go with them)
  delete from auth.users where id = any (v_users);

  if to_regclass('public.admin_audit') is not null and not v_archived then
    insert into public.admin_audit (actor, action, target_type, summary)
    values (v_admin, 'platform.clear', 'sql', format('Deleted all landlords (%s) and tenant accounts (%s) from the SQL Editor', n_landlords, n_tenants));
  end if;

  raise notice 'Deleted % landlord account(s) and % tenant account(s). Main admin kept.%',
    n_landlords, n_tenants, case when v_archived then ' A full copy was saved to Archives.' else ' (No archive: run 34_archive_and_clear.sql to keep copies next time.)' end;
end $$;

-- Check what's left: 1 account (the main admin) and zeros for the rest
select
  (select count(*) from public.profiles)                                      as accounts_left,
  (select count(*) from auth.users)                                           as logins_left,
  (select count(*) from public.properties)                                    as properties_left,
  (select count(*) from public.tenants)                                       as tenants_left,
  (select count(*) from public.payments)                                      as rent_months_left,
  (select count(*) from public.payment_receipts)                              as payments_left,
  (select count(*) from public.notifications)                                 as notifications_left;
