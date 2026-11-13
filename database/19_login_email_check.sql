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
