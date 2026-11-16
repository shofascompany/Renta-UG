-- 40 · live app install counts (replaces the typed-in downloads of 38)
-- Each phone that opens the Google Play app or the App Store app registers itself ONCE (a random device code, no personal details). The main admin's
-- Downloads page counts these rows live, so nobody types numbers in any more.
-- Run once in Supabase → SQL Editor. Safe to run more than once.

create table if not exists public.app_installs (
  device_id text primary key,
  platform text not null check (platform in ('android', 'ios')),
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now()
);
create index if not exists app_installs_platform_idx on public.app_installs (platform);

alter table public.app_installs enable row level security;
drop policy if exists "installs superadmin read" on public.app_installs;
create policy "installs superadmin read" on public.app_installs for select to authenticated using (public.is_superadmin());

-- Nobody writes to the table directly; phones call register_install below
revoke all on public.app_installs from public, anon, authenticated;
grant select on public.app_installs to authenticated;
grant all on public.app_installs to service_role;

create or replace function public.register_install(p_device text, p_platform text) returns void
language plpgsql volatile security definer set search_path = '' as $$
begin
  if p_platform not in ('android', 'ios') or p_device is null or length(p_device) not between 16 and 64 then
    return;
  end if;
  insert into public.app_installs (device_id, platform) values (p_device, p_platform)
  on conflict (device_id) do update set last_seen = now();
end $$;

revoke execute on function public.register_install(text, text) from public;
grant execute on function public.register_install(text, text) to anon, authenticated;

do $$ begin
  alter publication supabase_realtime add table public.app_installs;
exception when duplicate_object then null; end $$;

-- Home-screen (web) installs are not counted any more
delete from public.app_installs where platform = 'web';

-- The old typed-in table is no longer used
drop table if exists public.app_downloads;
