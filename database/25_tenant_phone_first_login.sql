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
