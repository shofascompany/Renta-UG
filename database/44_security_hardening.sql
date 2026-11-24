-- 44 · security hardening (safe to run again)
--
-- 1. setup_codes: a one-time code is now needed for a FIRST sign-in (a landlord registered by the
--    main admin, or a tenant given app access by their landlord). Before, an email or phone number
--    alone was enough, and those are not secret. Only a hash of the code is stored. Server only.
-- 2. login_failures: wrong-password counter per account for sign-in through the server (phone
--    sign-in), so passwords can't be guessed endlessly. Server only.
-- 3. tenants.user_id can only be set by the connection-code flow or the server, never by a landlord
--    writing the row directly (that would attach someone else's account to their tenant record).

create table if not exists public.setup_codes (
  user_id uuid primary key references auth.users (id) on delete cascade,
  code_hash text not null,
  expires_at timestamptz not null,
  attempts int not null default 0,
  created_at timestamptz not null default now()
);
alter table public.setup_codes enable row level security;
revoke all on public.setup_codes from public, anon, authenticated;
grant all on public.setup_codes to service_role;

create table if not exists public.login_failures (
  key text primary key,          -- 'phone:772123456'
  fails int not null default 0,
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.login_failures enable row level security;
revoke all on public.login_failures from public, anon, authenticated;
grant all on public.login_failures to service_role;

-- Direct writes from the app run as the "authenticated" role; the connection-code function
-- (security definer) and the server (service_role) run as other roles and are allowed.
create or replace function public.guard_tenant_user_id() returns trigger
language plpgsql set search_path = '' as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' and new.user_id is not null then
      raise exception 'A tenant account can only be linked with a connection code.';
    end if;
    if tg_op = 'UPDATE' and new.user_id is distinct from old.user_id and new.user_id is not null then
      raise exception 'A tenant account can only be linked with a connection code.';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists tenants_guard_user_id on public.tenants;
create trigger tenants_guard_user_id
  before insert or update of user_id on public.tenants
  for each row execute function public.guard_tenant_user_id();
