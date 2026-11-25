-- 58 · website visits, web app downloads and star ratings (safe to run again; no data is deleted)
--
--  All of it is for the main admin only. Browsers never touch the tables: they call the functions below.
--   • register_web_install()  a device that installed the app from the website, counted once
--   • record_visit()          a visit to the website: one per person until they have been away for a while
--   • rating_state() / submit_rating() / rating_later()   stars, asked after 7 days of use, filled in once
--   • site_stats() / admin_ratings()                      what the main admin sees

-- ── Tables ──
create table if not exists public.web_installs (
  device_id text primary key, -- a random code, nothing personal
  platform text not null check (platform in ('android', 'ios', 'windows', 'mac', 'other')),
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now()
);
create index if not exists web_installs_first_seen_idx on public.web_installs (first_seen);

create table if not exists public.site_visitors (
  visitor text primary key, -- a random code, nothing personal
  first_visit timestamptz not null default now(),
  last_visit timestamptz not null default now(),
  visits integer not null default 1
);
create index if not exists site_visitors_last_visit_idx on public.site_visitors (last_visit);

create table if not exists public.site_visit_days (
  day date primary key,
  visits integer not null default 0,
  visitors integer not null default 0
);

-- One rating per account. A deleted account's stars stay in the average, without the person.
create table if not exists public.app_ratings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique references auth.users (id) on delete set null,
  role text not null check (role in ('landlord', 'tenant')),
  stars smallint not null check (stars between 1 and 5),
  created_at timestamptz not null default now()
);
-- When each account started using the app, and when it may be asked
create table if not exists public.app_rating_asks (
  user_id uuid primary key references auth.users (id) on delete cascade,
  first_used timestamptz not null default now(),
  ask_after timestamptz
);

do $$
declare t text;
begin
  foreach t in array array['web_installs', 'site_visitors', 'site_visit_days', 'app_ratings', 'app_rating_asks'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant all on public.%I to service_role', t);
  end loop;
  -- The main admin may read these (it also makes the numbers update live)
  foreach t in array array['web_installs', 'site_visit_days', 'app_ratings'] loop
    execute format('drop policy if exists "main admin reads" on public.%I', t);
    execute format('create policy "main admin reads" on public.%I for select to authenticated using (public.is_superadmin())', t);
    execute format('grant select on public.%I to authenticated', t);
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

-- ── Web app downloads ──
create or replace function public.register_web_install(p_device text, p_platform text) returns void
language plpgsql volatile security definer set search_path = '' as $$
begin
  if p_device is null or p_device !~ '^[A-Za-z0-9]{16,64}$'
    or p_platform is null or p_platform not in ('android', 'ios', 'windows', 'mac', 'other') then
    return;
  end if;
  update public.web_installs set last_seen = now() where device_id = p_device;
  if found then return; end if;
  -- A limit, so nobody can fill the table with invented devices
  if (select count(*) from public.web_installs where first_seen > now() - interval '1 day') >= 5000 then return; end if;
  insert into public.web_installs (device_id, platform) values (p_device, p_platform) on conflict do nothing;
end $$;

-- ── Website visits ──
create or replace function public.record_visit(p_visitor text) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_today date := public.kampala_today();
  v_last timestamptz;
  v_new_today boolean;
begin
  if p_visitor is null or p_visitor !~ '^[A-Za-z0-9]{16,64}$' or public.is_superadmin() then
    return;
  end if;
  select last_visit into v_last from public.site_visitors where visitor = p_visitor for update;
  if found then
    if v_last > now() - interval '25 minutes' then return; end if; -- still the same visit
    update public.site_visitors set last_visit = now(), visits = visits + 1 where visitor = p_visitor;
    v_new_today := (v_last at time zone 'Africa/Kampala')::date < v_today;
  else
    if coalesce((select visitors from public.site_visit_days where day = v_today), 0) >= 50000 then return; end if;
    insert into public.site_visitors (visitor) values (p_visitor) on conflict do nothing;
    if not found then return; end if; -- counted by another tab at the same moment
    v_new_today := true;
  end if;
  insert into public.site_visit_days as d (day, visits, visitors) values (v_today, 1, v_new_today::int)
  on conflict (day) do update set visits = d.visits + 1, visitors = d.visitors + excluded.visitors;
end $$;

-- ── Star ratings ──
-- 'ask' = show the stars now · 'wait' = not yet · 'done' = already rated
create or replace function public.rating_state() returns text
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  v_ask public.app_rating_asks%rowtype;
begin
  if me is null or not exists (
    select 1 from public.profiles
    where id = me and role in ('landlord', 'tenant') and coalesce(active, true) and not coalesce(must_change_password, false)
  ) then
    return 'wait';
  end if;
  if exists (select 1 from public.app_ratings where user_id = me) then return 'done'; end if;
  -- First time seen here: an account already in use counts from its last sign-in
  insert into public.app_rating_asks (user_id, first_used)
  values (me, least(now(), coalesce((select u.last_sign_in_at from auth.users u where u.id = me), now())))
  on conflict do nothing;
  select * into v_ask from public.app_rating_asks where user_id = me;
  return case
    when v_ask.first_used <= now() - interval '7 days' and (v_ask.ask_after is null or v_ask.ask_after <= now()) then 'ask'
    else 'wait'
  end;
end $$;

-- "Not now": asked again a week later
create or replace function public.rating_later() returns void
language sql volatile security definer set search_path = '' as $$
  update public.app_rating_asks set ask_after = now() + interval '7 days' where user_id = auth.uid();
$$;

-- Once only: a second rating changes nothing
create or replace function public.submit_rating(p_stars integer) returns boolean
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  v_role text;
begin
  select role into v_role from public.profiles
  where id = me and role in ('landlord', 'tenant') and coalesce(active, true) and not coalesce(must_change_password, false);
  if v_role is null then raise exception 'Only landlords and tenants can rate Renta UG.'; end if;
  if p_stars is null or p_stars not between 1 and 5 then raise exception 'Choose 1 to 5 stars.'; end if;
  if not exists (select 1 from public.app_rating_asks where user_id = me and first_used <= now() - interval '7 days') then
    raise exception 'You can rate Renta UG after using it for 7 days.';
  end if;
  insert into public.app_ratings (user_id, role, stars) values (me, v_role, p_stars) on conflict (user_id) do nothing;
  return found;
end $$;

-- ── Main admin ──
create or replace function public.site_stats() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_today date := public.kampala_today();
begin
  if not public.is_superadmin() then raise exception 'Only the main admin can see this.'; end if;
  return jsonb_build_object(
    'visits', (select coalesce(sum(visits), 0) from public.site_visit_days),
    'visitors', (select count(*) from public.site_visitors),
    'today', (select coalesce(sum(visits), 0) from public.site_visit_days where day = v_today),
    'todayVisitors', (select coalesce(sum(visitors), 0) from public.site_visit_days where day = v_today),
    'week', (select coalesce(sum(visits), 0) from public.site_visit_days where day > v_today - 7),
    'weekVisitors', (select count(*) from public.site_visitors where (last_visit at time zone 'Africa/Kampala')::date > v_today - 7),
    'month', (select coalesce(sum(visits), 0) from public.site_visit_days where day > v_today - 30),
    'monthVisitors', (select count(*) from public.site_visitors where (last_visit at time zone 'Africa/Kampala')::date > v_today - 30),
    'day', v_today,
    'days', coalesce((select jsonb_agg(jsonb_build_object('day', day, 'visits', visits, 'visitors', visitors) order by day)
                      from public.site_visit_days where day > v_today - 14), '[]'),
    'web', (select count(*) from public.web_installs),
    'webActive', (select count(*) from public.web_installs where last_seen > now() - interval '30 days'),
    'webToday', (select count(*) from public.web_installs where (first_seen at time zone 'Africa/Kampala')::date = v_today),
    'webPlatforms', coalesce((select jsonb_object_agg(platform, n) from (select platform, count(*) n from public.web_installs group by platform) x), '{}'),
    'store', (select count(*) from public.app_installs),
    'ratings', (select count(*) from public.app_ratings),
    'average', (select round(avg(stars), 1) from public.app_ratings)
  );
end $$;

create or replace function public.admin_ratings() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_superadmin() then raise exception 'Only the main admin can see this.'; end if;
  return jsonb_build_object(
    'total', (select count(*) from public.app_ratings),
    'average', (select round(avg(stars), 1) from public.app_ratings),
    'counts', coalesce((select jsonb_object_agg(stars, n) from (select stars, count(*) n from public.app_ratings group by stars) x), '{}'),
    'list', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'userId', r.user_id, 'role', r.role, 'stars', r.stars, 'createdAt', r.created_at,
        'name', p.full_name, 'phone', p.phone,
        'email', case when p.email like '%@phone-signin.example.com' then null else p.email end,
        'tenantId', (select t.id from public.tenants t where t.user_id = r.user_id order by t.property_id is null limit 1)
      ) order by r.created_at desc)
      from (select * from public.app_ratings order by created_at desc limit 1000) r
      left join public.profiles p on p.id = r.user_id
    ), '[]')
  );
end $$;

-- ── Who may call what ──
revoke execute on function public.register_web_install(text, text), public.record_visit(text) from public;
grant execute on function public.register_web_install(text, text), public.record_visit(text) to anon, authenticated;
revoke execute on function public.rating_state(), public.rating_later(), public.submit_rating(integer), public.site_stats(), public.admin_ratings() from public, anon;
grant execute on function public.rating_state(), public.rating_later(), public.submit_rating(integer), public.site_stats(), public.admin_ratings() to authenticated;
