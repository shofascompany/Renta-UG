-- 22 · new paid month notices
-- When a month the tenant has ALREADY paid for begins (e.g. recharged in advance), they get a
-- notification: "Your December rent is already paid… runs 1 Dec – 31 Dec… paid up to …".
-- Runs every morning; each tenant gets it once per month (dedupe_key), only if that month's
-- rent was fully paid before the month started.
-- Safe to run more than once.

create or replace function public.send_month_start_notices() returns integer
language plpgsql volatile security definer set search_path = '' as $$
declare
  today date := (now() at time zone 'Africa/Kampala')::date;
  v_period text := to_char(today, 'YYYY-MM');
  v_start date := date_trunc('month', today)::date;
  v_end date := (date_trunc('month', today) + interval '1 month - 1 day')::date;
  n integer;
begin
  insert into public.notifications (landlord_id, tenant_id, type, title, body, dedupe_key)
  select
    t.landlord_id,
    t.id,
    'reminder',
    'New month started', -- sender line; the notification title is always "Renta UG"
    format('Your %s rent for %s is already paid. This month runs from %s to %s (%s days).%s',
      to_char(v_start, 'FMMonth YYYY'),
      pr.name,
      to_char(v_start, 'FMDD Mon'),
      to_char(v_end, 'FMDD Mon YYYY'),
      v_end - v_start + 1,
      case when ahead.until is not null and ahead.until > v_period
        then format(' You are paid up to the end of %s.', to_char(to_date(ahead.until || '-01', 'YYYY-MM-DD'), 'FMMonth YYYY'))
        else ' Remember to recharge before the month ends.' end),
    format('month_start:%s:%s', t.id, v_period)
  from public.tenants t
  join public.properties pr on pr.id = t.property_id
  join public.payments p on p.tenant_id = t.id and p.period = v_period and p.status = 'paid'
  cross join lateral (
    -- latest month paid from this one onwards
    select max(x.period) as until
    from public.payments x
    where x.tenant_id = t.id and x.status = 'paid' and x.period >= v_period
  ) ahead
  where t.property_id is not null
    and t.user_id is not null
    and p.paid_at is not null
    and (p.paid_at at time zone 'Africa/Kampala')::date < v_start + 1 -- paid before (or on) the 1st
    and today - v_start <= 2 -- only in the first days of the month
  on conflict (dedupe_key) do nothing;

  get diagnostics n = row_count;
  return n;
end $$;

revoke execute on function public.send_month_start_notices() from public, anon, authenticated;

-- Every day at 05:00 UTC = 08:00 in Kampala
create extension if not exists pg_cron;
select cron.schedule('renta-month-start-notices', '0 5 * * *', 'select public.send_month_start_notices()');
