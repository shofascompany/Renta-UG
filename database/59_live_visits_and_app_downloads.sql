-- 59 · visits and downloads, live and with their details (safe to run again; no data is deleted)
--
--  What counts (builds on 58):
--   • VISIT     someone opens the website, on any system. Signing in on the website is part of that visit: it is
--               still a visit, never a download. iPhone, Windows and Mac are always visits.
--   • DOWNLOAD  an account signs in inside the Android app. One phone is one download, however many accounts use it.
--   • INSTALLED Android says the app was installed, but nobody has signed in there yet.
--  Each one keeps its proof (when, which device, who), so every number on the main admin's page can be checked.

-- ── Downloads: accounts signed in inside the Android app ──
create table if not exists public.app_devices (
  id uuid primary key default gen_random_uuid(),
  device_id text not null, -- a random code for the phone
  user_id uuid references auth.users (id) on delete set null,
  role text not null check (role in ('landlord', 'tenant')),
  source text not null check (source in ('website', 'play')),
  device text not null default '', -- e.g. "Samsung SM-A515F (Android) · Chrome"
  first_at timestamptz not null default now(),
  last_at timestamptz not null default now(),
  unique (device_id, user_id)
);
create index if not exists app_devices_first_idx on public.app_devices (first_at desc);

-- ── Visits, one row each (kept 90 days; the totals in site_visit_days are kept for good) ──
create table if not exists public.site_visits (
  id bigint generated always as identity primary key,
  visitor text not null,
  at timestamptz not null default now(),
  system text not null check (system in ('android', 'ios', 'windows', 'mac', 'other')),
  device text not null default '',
  user_id uuid references auth.users (id) on delete set null,
  role text,
  signed_in_at timestamptz -- signed in on the website during this visit
);
create index if not exists site_visits_at_idx on public.site_visits (at desc);
create index if not exists site_visits_visitor_idx on public.site_visits (visitor, at desc);

do $$
declare t text;
begin
  foreach t in array array['app_devices', 'site_visits'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant all on public.%I to service_role', t);
    execute format('drop policy if exists "main admin reads" on public.%I', t);
    execute format('create policy "main admin reads" on public.%I for select to authenticated using (public.is_superadmin())', t);
    execute format('grant select on public.%I to authenticated', t);
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

-- ── A visit ──
-- p_new = the browser says this is a new visit (away for half an hour); otherwise it only signs this visit in
drop function if exists public.record_visit(text);
create or replace function public.record_visit(p_visitor text, p_system text, p_device text, p_new boolean) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_today date := public.kampala_today();
  v_device text := left(coalesce(p_device, ''), 80);
  v_user uuid := auth.uid();
  v_role text;
  v_last timestamptz;
  v_new_today boolean;
begin
  if p_visitor is null or p_visitor !~ '^[A-Za-z0-9]{16,64}$'
    or p_system is null or p_system not in ('android', 'ios', 'windows', 'mac', 'other') then
    return;
  end if;
  if v_user is not null then
    select role into v_role from public.profiles where id = v_user;
    if v_role = 'superadmin' then return; end if; -- the main admin's own pages are not visits
  end if;

  select last_visit into v_last from public.site_visitors where visitor = p_visitor for update;
  if found then
    -- Still the same visit: only note who signed in
    if p_new is not true and v_last > now() - interval '12 hours' or v_last > now() - interval '25 minutes' then
      if v_user is not null then
        update public.site_visits set user_id = v_user, role = v_role, signed_in_at = now()
        where id = (select id from public.site_visits where visitor = p_visitor order by at desc, id desc limit 1)
          and user_id is distinct from v_user;
      end if;
      return;
    end if;
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
  insert into public.site_visits (visitor, system, device, user_id, role, signed_in_at)
  values (p_visitor, p_system, v_device, v_user, v_role, case when v_user is not null then now() end);
  delete from public.site_visits where at < now() - interval '90 days';
end $$;

-- ── A download: an account signed in inside the Android app ──
create or replace function public.register_app_sign_in(p_device text, p_source text, p_name text) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  v_role text;
begin
  if p_device is null or p_device !~ '^[A-Za-z0-9]{16,64}$' or p_source is null or p_source not in ('website', 'play') then
    return;
  end if;
  select role into v_role from public.profiles where id = me and role in ('landlord', 'tenant') and coalesce(active, true);
  if v_role is null then return; end if; -- signed out, suspended, or the main admin
  update public.app_devices set last_at = now(), device = left(coalesce(nullif(p_name, ''), device), 80)
  where device_id = p_device and user_id = me;
  if found then return; end if;
  -- A limit, so one account cannot invent downloads
  if (select count(*) from public.app_devices where user_id = me) >= 20 then return; end if;
  insert into public.app_devices (device_id, user_id, role, source, device)
  values (p_device, me, v_role, p_source, left(coalesce(p_name, ''), 80))
  on conflict do nothing;
end $$;

-- ── Main admin: the numbers ──
create or replace function public.site_stats() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_today date := public.kampala_today();
  v_start timestamptz := (v_today::timestamp at time zone 'Africa/Kampala');
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
    'now', (select count(distinct visitor) from public.site_visits where greatest(at, signed_in_at) > now() - interval '5 minutes'),
    'day', v_today,
    'days', coalesce((select jsonb_agg(jsonb_build_object('day', day, 'visits', visits, 'visitors', visitors) order by day)
                      from public.site_visit_days where day > v_today - 14), '[]'),
    -- the last 30 days, from the visits themselves
    'systems', coalesce((select jsonb_object_agg(system, n) from (
                  select system, count(*) n from public.site_visits where at > now() - interval '30 days' group by system) x), '{}'),
    'signedIn', (select count(*) from public.site_visits where at > now() - interval '30 days' and signed_in_at is not null),
    'signedInToday', (select count(*) from public.site_visits where signed_in_at >= v_start),
    -- downloads = phones where an account signed in inside the Android app
    'downloads', (select count(distinct device_id) from public.app_devices),
    'downloadsToday', (select count(*) from (select device_id from public.app_devices group by device_id having min(first_at) >= v_start) x),
    'downloadsActive', (select count(distinct device_id) from public.app_devices where last_at > now() - interval '30 days'),
    'downloadsWebsite', (select count(distinct device_id) from public.app_devices where source = 'website'),
    'downloadsPlay', (select count(distinct device_id) from public.app_devices where source = 'play'),
    'downloadsLandlords', (select count(distinct device_id) from public.app_devices where role = 'landlord'),
    'downloadsTenants', (select count(distinct device_id) from public.app_devices where role = 'tenant'),
    -- Android said "installed", nobody has signed in on that phone yet
    'installedOnly', (select count(*) from public.web_installs w where w.platform = 'android'
                      and not exists (select 1 from public.app_devices d where d.device_id = w.device_id)),
    'ratings', (select count(*) from public.app_ratings),
    'average', (select round(avg(stars), 1) from public.app_ratings)
  );
end $$;

-- ── Main admin: the proof behind the numbers ──
create or replace function public.site_details() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_superadmin() then raise exception 'Only the main admin can see this.'; end if;
  return jsonb_build_object(
    'downloads', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id, 'userId', d.user_id, 'role', d.role, 'source', d.source, 'device', d.device, 'phoneCode', left(d.device_id, 8),
        'firstAt', d.first_at, 'lastAt', d.last_at, 'name', p.full_name, 'phone', p.phone,
        'email', case when p.email like '%@phone-signin.example.com' then null else p.email end,
        'tenantId', (select t.id from public.tenants t where t.user_id = d.user_id order by t.property_id is null limit 1)
      ) order by d.first_at desc)
      from (select * from public.app_devices order by first_at desc limit 200) d
      left join public.profiles p on p.id = d.user_id
    ), '[]'),
    'visits', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', v.id, 'at', v.at, 'signedInAt', v.signed_in_at, 'system', v.system, 'device', v.device,
        'userId', v.user_id, 'role', v.role, 'name', p.full_name,
        'tenantId', (select t.id from public.tenants t where t.user_id = v.user_id order by t.property_id is null limit 1)
      ) order by v.at desc, v.id desc)
      from (select * from public.site_visits order by at desc, id desc limit 200) v
      left join public.profiles p on p.id = v.user_id
    ), '[]'),
    'installed', coalesce((
      select jsonb_agg(jsonb_build_object('code', left(w.device_id, 8), 'at', w.first_seen, 'lastAt', w.last_seen) order by w.first_seen desc)
      from (select * from public.web_installs w where w.platform = 'android'
            and not exists (select 1 from public.app_devices d where d.device_id = w.device_id)
            order by first_seen desc limit 100) w
    ), '[]')
  );
end $$;

revoke execute on function public.record_visit(text, text, text, boolean) from public;
grant execute on function public.record_visit(text, text, text, boolean) to anon, authenticated;
revoke execute on function public.register_app_sign_in(text, text, text), public.site_stats(), public.site_details() from public, anon;
grant execute on function public.register_app_sign_in(text, text, text), public.site_stats(), public.site_details() to authenticated;
