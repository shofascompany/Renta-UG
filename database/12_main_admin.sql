-- 12 · main admin (superadmin)
-- Creates the main admin login directly in the database, or resets it if it already exists.
-- The main admin signs in at /admin2026.
--
-- To change any detail: edit the values below and run this file again
-- (it is also included in setup_all.sql). Safe to run any time.

do $$
declare
  v_email    text := 'shofascompany@gmail.com';
  v_password text := '1234man.';
  v_name     text := 'Abraham';
  v_phone    text := '0703089488';
  v_id       uuid;
begin
  v_email := lower(trim(v_email));
  select id into v_id from auth.users where lower(email) = v_email;

  if v_id is null then
    -- New login account, already email-confirmed
    v_id := gen_random_uuid();
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change, email_change_token_new,
      email_change_token_current, phone_change, phone_change_token, reauthentication_token
    ) values (
      '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
      extensions.crypt(v_password, extensions.gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}', jsonb_build_object('full_name', v_name), now(), now(),
      '', '', '', '', '', '', '', ''
    );
  else
    -- Existing account: force the password, confirm the email, lift any suspension
    update auth.users
    set encrypted_password = extensions.crypt(v_password, extensions.gen_salt('bf')),
        email_confirmed_at = coalesce(email_confirmed_at, now()),
        banned_until = null,
        raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('full_name', v_name),
        updated_at = now()
    where id = v_id;
  end if;

  -- Email/password identity (needed for sign-in)
  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (
    gen_random_uuid(), v_id, v_id::text,
    jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true),
    'email', now(), now(), now()
  )
  on conflict (provider_id, provider) do nothing;

  -- Make it the one and only main admin
  insert into public.profiles (id, email, full_name, phone, role, active)
  values (v_id, v_email, v_name, v_phone, 'superadmin', true)
  on conflict (id) do update
    set email = excluded.email, full_name = excluded.full_name, phone = excluded.phone,
        role = 'superadmin', active = true;

  update public.profiles set role = 'tenant' where role = 'superadmin' and id <> v_id;
end $$;
