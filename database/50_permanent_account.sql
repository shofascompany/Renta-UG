-- 50 · the permanent landlord account: fixed password, never a first sign-in, data never deleted
--
--  ngumisiriza@gmail.com (see 46 + 49) is permanent:
--  • Its password is fixed. Changing it in the app, by "forgot password" or by an admin reset has no
--    effect: the database keeps it. The password itself is NOT in this file (the code is public). It is
--    set from the private .env with `npm run permanent-account` (scripts/permanent-account.mjs), which
--    calls set_permanent_account() below: the only way to write it, and only with the server key.
--  • It never sees the first-sign-in pages: it is always a ready, active landlord.
--  • Its data (rentals, houses, rooms, tenants, rent, payments, receipts, cash) can only be deleted by
--    the account itself. Admins, the server, "delete all users" and direct database deletes are refused.
--  Safe to run again. No data is deleted.

-- Always a ready landlord: active, free for life, no first-sign-in step, no one-time setup code
update public.profiles
set role = 'landlord', active = true, must_change_password = false, subscription_exempt = true
where lower(email) = 'ngumisiriza@gmail.com'
  and (role <> 'landlord' or not active or must_change_password or not subscription_exempt);
delete from public.setup_codes where user_id in (select id from public.profiles where subscription_exempt);

-- ── Create / repair the login with its fixed password (server key only) ──
create or replace function public.set_permanent_account(p_password text) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_email text := 'ngumisiriza@gmail.com';
  v_id uuid;
begin
  if length(coalesce(p_password, '')) < 6 then raise exception 'The password must be at least 6 characters.'; end if;
  select id into v_id from auth.users where lower(email) = v_email;

  perform set_config('renta.permanent_repair', 'on', true); -- lets the guard below accept this one write
  if v_id is null then
    v_id := gen_random_uuid();
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change, email_change_token_new,
      email_change_token_current, phone_change, phone_change_token, reauthentication_token
    ) values (
      '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
      extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}', '{"full_name":"Ngumisiriza"}', now(), now(),
      '', '', '', '', '', '', '', ''
    );
  else
    update auth.users
    set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
        email_confirmed_at = coalesce(email_confirmed_at, now()),
        banned_until = null,
        updated_at = now()
    where id = v_id;
  end if;
  perform set_config('renta.permanent_repair', 'off', true);

  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), v_id, v_id::text,
    jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true), 'email', now(), now(), now())
  on conflict (provider_id, provider) do nothing;

  insert into public.profiles (id, email, full_name, role, active, must_change_password, subscription_exempt)
  values (v_id, v_email, 'Ngumisiriza', 'landlord', true, false, true)
  on conflict (id) do update
    set email = excluded.email, role = 'landlord', active = true, must_change_password = false, subscription_exempt = true;
  delete from public.setup_codes where user_id = v_id;
  return v_id;
end $$;
revoke execute on function public.set_permanent_account(text) from public, anon, authenticated;
grant execute on function public.set_permanent_account(text) to service_role;

-- ── Login: the password and email never change, and it is never banned ──
create or replace function public.guard_permanent_login() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(current_setting('renta.permanent_repair', true), 'off') = 'on' then return new; end if;
  if exists (select 1 from public.profiles where id = old.id and subscription_exempt) then
    new.encrypted_password := old.encrypted_password;
    new.email := old.email;
    new.banned_until := null;
  end if;
  return new;
end $$;

drop trigger if exists auth_users_permanent_login on auth.users;
create trigger auth_users_permanent_login
  before update on auth.users
  for each row execute function public.guard_permanent_login();

-- ── Profile: never a first sign-in, never suspended or demoted (49 refuses those; this also fixes
--    must_change_password and re-applies the flags if the profile is ever created again) ──
create or replace function public.guard_protected_profile() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    if old.subscription_exempt then
      raise exception 'This is the permanent Renta UG landlord account. It cannot be deleted.';
    end if;
    return old;
  end if;
  if old.subscription_exempt and (not new.subscription_exempt or new.role is distinct from 'landlord' or not new.active) then
    raise exception 'This is the permanent Renta UG landlord account. It cannot be suspended or changed to another kind of account.';
  end if;
  if new.subscription_exempt then new.must_change_password := false; end if;
  return new;
end $$;

create or replace function public.permanent_profile_on_insert() returns trigger
language plpgsql set search_path = '' as $$
begin
  if lower(coalesce(new.email, '')) = 'ngumisiriza@gmail.com' then
    new.role := 'landlord';
    new.active := true;
    new.must_change_password := false;
    new.subscription_exempt := true;
  end if;
  return new;
end $$;

drop trigger if exists profiles_permanent_insert on public.profiles;
create trigger profiles_permanent_insert
  before insert on public.profiles
  for each row execute function public.permanent_profile_on_insert();

-- ── Data: only the account itself can delete its own records ──
-- Admin functions, the server (service role) and "delete all users" are refused.
create or replace function public.guard_permanent_data() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.profiles where id = old.landlord_id and subscription_exempt)
     and auth.uid() is distinct from old.landlord_id then
    raise exception 'This belongs to the permanent Renta UG landlord account and cannot be deleted.';
  end if;
  return old;
end $$;

do $$
declare t text;
begin
  foreach t in array array['rentals', 'properties', 'tenants', 'payments', 'payment_receipts', 'cash_payments'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_guard_permanent', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.guard_permanent_data()', t || '_guard_permanent', t);
  end loop;
end $$;
