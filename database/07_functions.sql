-- 07 · helper functions and triggers
-- Requires tables 01–05. Safe to run again (replaces the functions, recreates the trigger).

-- Current user's role checks (security definer so RLS policies don't recurse)
create or replace function public.is_superadmin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'superadmin');
$$;

create or replace function public.is_landlord() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'landlord' and active);
$$;

-- The tenant record belonging to the current user, if any.
create or replace function public.my_tenant_id() returns uuid
language sql stable security definer set search_path = '' as $$
  select id from public.tenants where user_id = auth.uid();
$$;

-- New sign-up → create a profile. Everyone starts as a tenant; landlords are promoted
-- by the server when the main admin registers them, the main admin by 12_main_admin.sql.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Landlord: create a fresh 6-character connection code for one of their tenants, valid 20 minutes.
-- Returns {"code": "...", "expires_at": "..."}.
create or replace function public.new_connect_code(p_tenant_id uuid) returns json
language plpgsql volatile security definer set search_path = '' as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- no 0/O/1/I
  c text;
  expires timestamptz := now() + interval '20 minutes';
begin
  if not public.is_landlord() then
    raise exception 'Only landlords can create connection codes.';
  end if;

  loop
    c := '';
    for i in 1..6 loop
      c := c || substr(alphabet, 1 + get_byte(extensions.gen_random_bytes(1), 0) % 32, 1);
    end loop;
    exit when not exists (select 1 from public.tenants where connect_code = c);
  end loop;

  update public.tenants
  set connect_code = c, connect_code_expires_at = expires
  where id = p_tenant_id and landlord_id = auth.uid() and user_id is null;

  if not found then
    raise exception 'Tenant not found, or already connected to an account.';
  end if;

  return json_build_object('code', c, 'expires_at', expires);
end $$;

-- Tenant: enter a code to connect your account to the landlord who issued it.
create or replace function public.redeem_connect_code(p_code text) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  t_id uuid;
  me uuid := auth.uid();
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

  select id into t_id
  from public.tenants
  where connect_code = upper(trim(p_code))
    and connect_code_expires_at > now()
    and user_id is null
  for update;

  if t_id is null then
    raise exception 'This code is invalid or has expired. Ask your landlord for a new one.';
  end if;

  -- Detach any former-tenant record so user_id stays unique
  update public.tenants set user_id = null where user_id = me;

  update public.tenants
  set user_id = me,
      email = coalesce(email, (select email from auth.users where id = me)),
      connect_code = null,
      connect_code_expires_at = null
  where id = t_id;

  return t_id;
end $$;

revoke execute on function public.new_connect_code(uuid) from public, anon;
revoke execute on function public.redeem_connect_code(text) from public, anon;
grant execute on function public.new_connect_code(uuid) to authenticated;
grant execute on function public.redeem_connect_code(text) to authenticated;
