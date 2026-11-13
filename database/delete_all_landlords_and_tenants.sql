-- ============================================================================
-- ⚠ DELETE ALL LANDLORD AND TENANT ACCOUNTS. THIS CANNOT BE UNDONE.
--
-- Removes every landlord and tenant login, and with them all of the landlords'
-- properties, tenant records, payments, notifications and alerts.
-- The main admin account (role = superadmin) is kept.
-- The tables, security rules and functions are kept, so the app keeps working.
--
-- Paste into Supabase → SQL Editor → Run. Not included in setup_all.sql.
-- ============================================================================

do $$
declare
  n_landlords int;
  n_tenants   int;
begin
  select count(*) filter (where role = 'landlord'),
         count(*) filter (where role = 'tenant')
    into n_landlords, n_tenants
  from public.profiles;

  -- Deleting a login cascades to its profile; deleting a landlord's login cascades to
  -- everything with their landlord_id (properties, tenants, payments, notifications, alerts).
  delete from auth.users
  where id in (select id from public.profiles where role in ('landlord', 'tenant'));

  raise notice 'Deleted % landlord account(s) and % tenant account(s). Main admin kept.', n_landlords, n_tenants;
end $$;

-- Check what's left (should show only the main admin, and zeros for the rest)
select
  (select count(*) from public.profiles)      as accounts_left,
  (select count(*) from public.properties)    as properties_left,
  (select count(*) from public.tenants)       as tenants_left,
  (select count(*) from public.payments)      as payments_left,
  (select count(*) from public.notifications) as notifications_left,
  (select count(*) from public.alerts)        as alerts_left;
