-- 13 · first-login password
-- Landlords get a temporary password from the main admin. On their first sign-in they must
-- choose their own password; after that they go straight to their dashboard.
-- Safe to run on its own on an existing database (no data is deleted).

alter table public.profiles
  add column if not exists must_change_password boolean not null default false;

-- Called by the app right after the user has set their new password.
create or replace function public.complete_password_setup() returns void
language sql volatile security definer set search_path = '' as $$
  update public.profiles set must_change_password = false where id = auth.uid();
$$;

revoke execute on function public.complete_password_setup() from public, anon;
grant execute on function public.complete_password_setup() to authenticated;
