-- 42 · landlords add a tenant with just an EMAIL or PHONE NUMBER + the room; the tenant brings their own details
--
--  • Added by email: the code only works for the account with that email.
--  • Added by phone: the code works for the account with that phone number, or for an account that has no
--    phone number yet (e.g. signed up with email); that account then gets the phone the landlord typed.
--    An account with a DIFFERENT phone number is refused.
--  • A record with neither (older data) works for any tenant account that enters the code in its 20 minutes.
--  • When the tenant connects, their OWN name, email and phone (from their account) are saved on the
--    tenant record, replacing whatever the landlord typed.
-- Safe to run more than once.

create or replace function public.redeem_connect_code(p_code text) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  t record;
  me uuid := auth.uid();
  v_email text;
  v_phone9 text;
  v_phone text;
  v_name text;
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

  select lower(coalesce(u.email, '')), nullif(trim(coalesce(p.phone, u.phone, '')), ''), nullif(trim(p.full_name), '')
    into v_email, v_phone, v_name
  from auth.users u left join public.profiles p on p.id = u.id
  where u.id = me;
  v_phone9 := right(regexp_replace(coalesce(v_phone, ''), '\D', '', 'g'), 9);
  digits9 := right(regexp_replace(coalesce(t.phone, ''), '\D', '', 'g'), 9);

  -- The landlord gave an email or phone: only that person's account may connect
  if (t.email is not null or length(digits9) = 9) and not (
    (t.email is not null and lower(t.email) = v_email)
    or (length(digits9) = 9 and (digits9 = v_phone9 or (t.email is null and length(v_phone9) < 9)))
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
