-- 31 · calm, truthful notifications
-- Fewer messages, each one needed at that moment and true to the data:
--   • Sign-in alert: only when the account is used on a device it hasn't used in the last 60 days.
--   • No "rent status" on every sign-in / app open. Opening the app only sends ONE message, once ever:
--     "your rental time hasn't started, it starts the day you pay" for a new tenant who hasn't paid.
--     (The old status could wrongly say "Your rent is fully paid" to a tenant who had paid nothing.)
--   • Rental time ending: 3 days before, the day before and on the day only (was every day for a week).
--   • Overdue / rental time ended: once when it happens, then every 3 days (was every 5 hours), 08:00–20:00.
--   • "New month started" notices are switched off: rental time now runs from the day of payment,
--     so calendar-month messages no longer matched the truth.
--   • Welcome message says when the rental time starts.
-- Same function names and arguments as before, so the app needs no changes. Safe to run more than once.

-- ── Rent status (internal): only the "not started yet" note, once per tenant ──
create or replace function public.send_rent_status(p_tenant_id uuid, p_force boolean) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  t record;
begin
  select tn.*, p.name as house, p.rent into t
  from public.tenants tn join public.properties p on p.id = tn.property_id
  where tn.id = p_tenant_id and tn.property_id is not null;
  if not found then return; end if;

  -- Paid at least once → their rental time is running; reminders come from the daily jobs below
  if t.lease_end is not null or exists (select 1 from public.payments where tenant_id = t.id and amount_paid > 0) then
    return;
  end if;

  insert into public.notifications (landlord_id, tenant_id, type, title, body, dedupe_key)
  values (t.landlord_id, t.id, 'status', 'Rental time',
    format('Your rental time for %s has not started yet. It starts on the day you pay your first rent%s, and runs one month for every month you pay.',
      t.house, coalesce(' of ' || public.ugx(nullif(t.rent, 0)), '')),
    format('not_started:%s', t.id))
  on conflict (dedupe_key) do nothing;
end $$;
revoke execute on function public.send_rent_status(uuid, boolean) from public, anon, authenticated;

create or replace function public.check_rent_status() returns void
language plpgsql volatile security definer set search_path = '' as $$
declare v_tenant uuid;
begin
  select id into v_tenant from public.tenants where user_id = auth.uid() and property_id is not null;
  if v_tenant is not null then perform public.send_rent_status(v_tenant, false); end if;
end $$;
revoke execute on function public.check_rent_status() from public, anon;
grant execute on function public.check_rent_status() to authenticated;

-- ── Sign-in alert: only for a device not used in the last 60 days ──
create or replace function public.notify_sign_in(p_device text) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  v_role text;
  v_device text := left(coalesce(nullif(trim(p_device), ''), 'an unknown device'), 80);
  v_when text := to_char(now() at time zone 'Africa/Kampala', 'FMHH12:MI AM "on" FMDD Mon YYYY');
  v_needle text;
  v_body text;
  t record;
begin
  if me is null then return; end if;
  select role into v_role from public.profiles where id = me;
  v_needle := format('detected on %s at', v_device);
  v_body := format('A new sign-in to your account was detected on %s at %s (EAT). If this was not you, change your password now under Settings > Change password.', v_device, v_when);

  if v_role in ('landlord', 'superadmin') then
    if exists (select 1 from public.staff_notifications
               where user_id = me and type = 'security' and created_at > now() - interval '60 days'
                 and position(v_needle in body) > 0) then
      return; -- a device they already use
    end if;
    insert into public.staff_notifications (user_id, type, title, body, url)
    values (me, 'security', 'Account security', v_body, case when v_role = 'landlord' then '/landlord/inbox' else '/admin2026/inbox' end);
    return;
  end if;

  select id, landlord_id, property_id into t from public.tenants where user_id = me;
  if not found then return; end if;

  if not exists (select 1 from public.notifications
                 where tenant_id = t.id and type = 'security' and created_at > now() - interval '60 days'
                   and position(v_needle in body) > 0) then
    insert into public.notifications (landlord_id, tenant_id, type, title, body)
    values (t.landlord_id, t.id, 'security', 'Account security', v_body);
  end if;

  if t.property_id is not null then perform public.send_rent_status(t.id, false); end if;
end $$;
revoke execute on function public.notify_sign_in(text) from public, anon;
grant execute on function public.notify_sign_in(text) to authenticated;

-- ── Rental time ending: 3 days before, the day before, and on the day ──
create or replace function public.send_lease_reminders() returns integer
language plpgsql volatile security definer set search_path = '' as $$
declare
  today date := public.kampala_today();
  n integer;
begin
  insert into public.notifications (landlord_id, tenant_id, type, title, body, dedupe_key)
  select t.landlord_id, t.id, 'reminder', 'Rental time',
    case d.days_left
      when 0 then format('Your paid rental time for %s ends today. Pay now to continue: your next month runs on from today.', p.name)
      when 1 then format('Your paid rental time for %s ends tomorrow, %s. Pay before then to continue without a gap.', p.name, to_char(t.lease_end, 'FMDD Mon YYYY'))
      else format('Your paid rental time for %s ends in 3 days, on %s. Recharge any time: the new month is added on top.', p.name, to_char(t.lease_end, 'FMDD Mon YYYY'))
    end,
    format('lease_end:%s:%s', t.id, today)
  from public.tenants t
  join public.properties p on p.id = t.property_id
  cross join lateral (select (t.lease_end - today) as days_left) d
  where t.property_id is not null
    and t.user_id is not null
    and t.lease_end is not null
    and d.days_left in (0, 1, 3)
  on conflict (dedupe_key) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.send_lease_reminders() from public, anon, authenticated;

-- ── Overdue / rental time ended: once, then every 3 days, daytime only ──
create or replace function public.send_overdue_reminders() returns integer
language plpgsql volatile security definer set search_path = '' as $$
declare
  today date := public.kampala_today();
  v_hour integer := extract(hour from now() at time zone 'Africa/Kampala');
  n integer;
begin
  if v_hour < 8 or v_hour >= 20 then return 0; end if;

  insert into public.notifications (landlord_id, tenant_id, type, title, body)
  select t.landlord_id, t.id, 'rent_due', 'Rent reminder',
    case when o.amount > 0
      then format('%s for %s has been unpaid since %s. Please pay on the Payments page.',
             public.ugx(o.amount), p.name, to_char(o.since, 'FMDD Mon YYYY'))
      else format('Your paid rental time for %s ended on %s. Pay to continue: the new month runs on from %s.',
             p.name, to_char(t.lease_end, 'FMDD Mon YYYY'), to_char(t.lease_end, 'FMDD Mon')) end
  from public.tenants t
  join public.properties p on p.id = t.property_id
  cross join lateral (
    select coalesce(sum(amount - amount_paid), 0) as amount, min(due_date) as since
    from public.payments where tenant_id = t.id and status = 'pending' and due_date < today
  ) o
  where t.property_id is not null
    and t.user_id is not null
    and (o.amount > 0 or (t.lease_end is not null and t.lease_end < today))
    and not exists (
      select 1 from public.notifications x
      where x.tenant_id = t.id and x.type = 'rent_due' and x.created_at > now() - interval '71 hours'
    );
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.send_overdue_reminders() from public, anon, authenticated;

-- ── Calendar "new month started" notices: off ──
create or replace function public.send_month_start_notices() returns integer
language sql volatile security definer set search_path = '' as $$ select 0; $$;
revoke execute on function public.send_month_start_notices() from public, anon, authenticated;
do $$ begin
  perform cron.unschedule('renta-month-start-notices');
exception when others then null; end $$;

-- ── Welcome: truthful about when the rental time starts ──
create or replace function public.notify_tenant_connected() returns trigger
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_house text;
  v_landlord text;
  v_started boolean;
begin
  if new.user_id is null or new.property_id is null or old.user_id is not distinct from new.user_id then
    return new;
  end if;
  select name into v_house from public.properties where id = new.property_id;
  select nullif(full_name, '') into v_landlord from public.profiles where id = new.landlord_id;
  v_started := new.lease_end is not null;

  insert into public.notifications (landlord_id, tenant_id, type, title, body, dedupe_key)
  values (new.landlord_id, new.id, 'welcome', 'Account connected',
    format('Welcome! Your account is connected to %s%s. %s',
      coalesce(v_house, 'your rental'), coalesce(', managed by ' || v_landlord, ''),
      case when v_started then format('You are paid up to %s.', to_char(new.lease_end, 'FMDD Mon YYYY'))
           else 'Your rental time starts on the day you pay your first rent.' end),
    format('not_started:%s', new.id)) -- also covers the "not started" note, so it isn't sent twice
  on conflict (dedupe_key) do nothing;

  insert into public.staff_notifications (user_id, type, title, body, url)
  values (new.landlord_id, 'tenant', 'Tenant connected',
    format('%s has connected their Renta account for %s.', new.full_name, coalesce(v_house, 'their rental')),
    '/landlord/tenants');
  return new;
end $$;
