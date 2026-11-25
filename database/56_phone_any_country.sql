-- 56 · phone numbers from any country (safe to run again; no data is deleted)
--
--  Numbers are saved as +<country code><number> (e.g. +254712345678). Older Ugandan numbers saved as
--  0772 123 456 still work. Two numbers are the same person's when their phone_key is the same, so a Kenyan
--  +254 712 345 678 and a Ugandan +256 712 345 678 are never mixed up (matching on the last 9 digits would).
--  phone_key() gives the same answer as phoneKey() in src/lib/phone.js.

create or replace function public.phone_key(p text) returns text
language sql immutable set search_path = '' as $$
  with x as (
    select btrim(coalesce(p, '')) as raw, regexp_replace(coalesce(p, ''), '\D', '', 'g') as d
  )
  select case
    when raw like '+%' then case when length(d) between 9 and 15 then d else '' end
    when d like '00%' then case when length(substr(d, 3)) between 9 and 15 then substr(d, 3) else '' end
    when d ~ '^7[0-9]{8}$' then '256' || d
    when d ~ '^07[0-9]{8}$' then '256' || substr(d, 2)
    when d ~ '^2567[0-9]{8}$' then d
    when length(d) >= 9 then d
    else ''
  end
  from x;
$$;

-- Sign-in page: what kind of account is this phone number?
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
     where public.phone_key(p_phone) <> ''
       and public.phone_key(p.phone) = public.phone_key(p_phone)
     order by p.created_at desc nulls last
     limit 1),
    'not_found');
$$;

revoke execute on function public.login_phone_status(text) from public;
grant execute on function public.login_phone_status(text) to anon, authenticated;

-- Connecting with a code: the code works for the account with the phone number the landlord typed
-- (any country), or for an account that has no phone number yet
create or replace function public.redeem_connect_code(p_code text) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  t record;
  me uuid := auth.uid();
  v_email text;
  v_key text;
  v_phone text;
  v_name text;
  t_key text;
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

  select lower(coalesce(u.email, '')), nullif(trim(coalesce(p.phone, u.phone, '')), ''), nullif(trim(p.full_name), '')
    into v_email, v_phone, v_name
  from auth.users u left join public.profiles p on p.id = u.id
  where u.id = me;
  v_key := public.phone_key(v_phone);
  t_key := public.phone_key(t.phone);

  -- The landlord gave an email or phone: only that person's account may connect
  if (t.email is not null or t_key <> '') and not (
    (t.email is not null and lower(t.email) = v_email)
    or (t_key <> '' and (t_key = v_key or (t.email is null and v_key = '')))
  ) then
    raise exception 'This code is for a different account. Sign in with the email or phone number your landlord registered for you, or ask them to check your details.';
  end if;

  -- Detach any former-tenant record so user_id stays unique
  update public.tenants set user_id = null where user_id = me;

  -- The tenant's own details replace what the landlord typed
  update public.tenants
  set user_id = me,
      full_name = coalesce(v_name, full_name),
      email = case when v_email = '' or v_email like '%@phone-signin.example.com' then email else v_email end,
      phone = coalesce(v_phone, phone),
      connect_code = null,
      connect_code_expires_at = null
  where id = t.id;

  return t.id;
end $$;

revoke execute on function public.redeem_connect_code(text) from public, anon;
grant execute on function public.redeem_connect_code(text) to authenticated;
