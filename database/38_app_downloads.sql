-- App downloads (Google Play + App Store), shown to the main admin under "Downloads".
-- The stores don't send their numbers to us, so the main admin types them in from
-- Google Play Console / App Store Connect. Run once in Supabase → SQL Editor.

create table if not exists public.app_downloads (
  platform text primary key check (platform in ('android', 'ios')),
  downloads integer not null default 0 check (downloads >= 0),
  store_url text,
  note text,
  updated_at timestamptz not null default now()
);

insert into public.app_downloads (platform) values ('android'), ('ios') on conflict do nothing;

alter table public.app_downloads enable row level security;

-- New tables are not opened to signed-in users automatically; the policies below still limit it to the main admin
grant select, update on public.app_downloads to authenticated;
grant all on public.app_downloads to service_role;

drop policy if exists "downloads superadmin read" on public.app_downloads;
create policy "downloads superadmin read" on public.app_downloads for select to authenticated using (public.is_superadmin());

drop policy if exists "downloads superadmin write" on public.app_downloads;
create policy "downloads superadmin write" on public.app_downloads for update to authenticated
  using (public.is_superadmin()) with check (public.is_superadmin());
