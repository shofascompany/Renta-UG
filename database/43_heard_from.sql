-- 43 · "Where did you hear about Renta UG?"
-- Asked once in the welcome tour (landlords and tenants). One answer per account.
-- The main admin sees the totals on the Statistics page. Safe to run again.

create table if not exists public.signup_sources (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  role       text,
  source     text not null check (char_length(source) between 1 and 40),
  detail     text check (detail is null or char_length(detail) <= 120),
  created_at timestamptz not null default now()
);

alter table public.signup_sources enable row level security;

-- The role always comes from the account itself, never from the browser
create or replace function public.signup_source_role() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.role := (select role from public.profiles where id = new.user_id);
  new.detail := nullif(trim(new.detail), '');
  return new;
end $$;

drop trigger if exists signup_source_role on public.signup_sources;
create trigger signup_source_role before insert or update on public.signup_sources
  for each row execute function public.signup_source_role();

drop policy if exists "signup_sources own insert" on public.signup_sources;
create policy "signup_sources own insert" on public.signup_sources
  for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "signup_sources read" on public.signup_sources;
create policy "signup_sources read" on public.signup_sources
  for select to authenticated using (user_id = auth.uid() or public.is_superadmin());

drop policy if exists "signup_sources admin delete" on public.signup_sources;
create policy "signup_sources admin delete" on public.signup_sources
  for delete to authenticated using (public.is_superadmin());

grant select, insert on public.signup_sources to authenticated;
grant delete on public.signup_sources to authenticated;
