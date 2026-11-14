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
