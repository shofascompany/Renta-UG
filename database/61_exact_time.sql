-- 61 · rent and subscriptions are counted to the exact time (safe to run again; no data is deleted)
--
--  A day is 24 complete hours from the moment the time started, not a calendar day.
--    • Subscription: starts the moment Renta UG confirms the payment. 30 days later at that same time it ends.
--    • Rent: starts the moment the first payment is confirmed (recorded by the landlord with an earlier date: that
--      date, at the time it was recorded). Months run on from each other, so the time of day never changes.
--  The dates stay as they are; only the time of day is kept beside them, and it is never shown to anyone:
--    tenants.rent_clock            lease_end + rent_clock                     = the moment the rent ends
--    profiles.subscription_clock   subscription_until + 1 day + that clock    = the moment the subscription ends
--  Only the triggers below write these columns.

create or replace function public.rent_ends_at(p_end date, p_clock time) returns timestamptz
language sql immutable set search_path = '' as $$
  select (p_end + coalesce(p_clock, time '24:00')) at time zone 'Africa/Kampala';
$$;
create or replace function public.subscription_ends_at(p_until date, p_clock time) returns timestamptz
language sql immutable set search_path = '' as $$
  select (p_until + 1 + coalesce(p_clock, time '00:00')) at time zone 'Africa/Kampala';
$$;
revoke execute on function public.rent_ends_at(date, time) from public, anon;
revoke execute on function public.subscription_ends_at(date, time) from public, anon;
grant execute on function public.rent_ends_at(date, time) to authenticated, service_role;
grant execute on function public.subscription_ends_at(date, time) to authenticated, service_role;

-- ── The columns. What is already running gets the time its first payment was confirmed, once ──
do $$
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'tenants' and column_name = 'rent_clock') then
    alter table public.tenants add column rent_clock time;
    update public.tenants t
    set rent_clock = date_trunc('second', coalesce(
      (select min(c.reviewed_at) from public.cash_payments c where c.tenant_id = t.id and c.status = 'confirmed'),
      t.created_at) at time zone 'Africa/Kampala')::time
    where t.lease_end is not null;
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'profiles' and column_name = 'subscription_clock') then
    alter table public.profiles add column subscription_clock time;
    update public.profiles p
    set subscription_clock = coalesce(
      -- the payment that started the running subscription (the ones after it were added on top)
      (select date_trunc('second', s.reviewed_at at time zone 'Africa/Kampala')::time
       from public.subscription_payments s
       where s.landlord_id = p.id and s.status = 'confirmed' and s.period_start = (s.reviewed_at at time zone 'Africa/Kampala')::date
       order by s.reviewed_at desc limit 1),
      time '00:00')
    where p.subscription_until is not null;
  end if;
end $$;

-- ── Rent: the time of day is set once, when the rental time starts ──
create or replace function public.keep_rent_clock() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.lease_end is null then
    new.rent_clock := null;
  elsif tg_op = 'INSERT' then
    new.rent_clock := date_trunc('second', now() at time zone 'Africa/Kampala')::time;
  elsif old.lease_end is null then
    new.rent_clock := date_trunc('second', now() at time zone 'Africa/Kampala')::time;
  else
    new.rent_clock := old.rent_clock;
  end if;
  return new;
end $$;
drop trigger if exists tenants_rent_clock on public.tenants;
create trigger tenants_rent_clock before insert or update on public.tenants
  for each row execute function public.keep_rent_clock();

-- ── Subscription: set when it starts (first payment, or the first after it ended). Renewed in time: it runs on ──
create or replace function public.keep_subscription_clock() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.subscription_until is null then
    new.subscription_clock := null;
  elsif tg_op = 'INSERT' then
    new.subscription_clock := date_trunc('second', now() at time zone 'Africa/Kampala')::time;
  elsif new.subscription_until is distinct from old.subscription_until
    and (old.subscription_until is null or public.subscription_ends_at(old.subscription_until, old.subscription_clock) <= now()) then
    new.subscription_clock := date_trunc('second', now() at time zone 'Africa/Kampala')::time;
  else
    new.subscription_clock := old.subscription_clock;
  end if;
  return new;
end $$;
drop trigger if exists profiles_zz_subscription_clock on public.profiles;
create trigger profiles_zz_subscription_clock before insert or update on public.profiles
  for each row execute function public.keep_subscription_clock();

-- ── Is this landlord's subscription running right now? ──
create or replace function public.landlord_subscribed(p_user uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select p.role <> 'landlord' or p.subscription_exempt
            or coalesce(public.subscription_ends_at(p.subscription_until, p.subscription_clock) > now(), false)
     from public.profiles p where p.id = p_user),
    true);
$$;

-- ── Confirming a subscription: the same rules, and the date told is the day it really ends ──
create or replace function public.admin_confirm_subscription_payment(p_id uuid) returns json
language plpgsql volatile security definer set search_path = '' as $$
declare
  r public.subscription_payments;
  p record;
  v_start date;
  v_end date;
begin
  perform public.admin_require();
  select * into r from public.subscription_payments where id = p_id for update;
  if not found then raise exception 'Payment not found.'; end if;
  if r.status <> 'pending' then raise exception 'This payment has already been %.', r.status; end if;
  select * into p from public.profiles where id = r.landlord_id for update;

  v_start := case when p.subscription_until >= public.kampala_today() then p.subscription_until + 1 else public.kampala_today() end;
  v_end := v_start + public.subscription_days(r.months) - 1;

  update public.profiles set subscription_until = v_end, subscription_plan = r.plan, subscription_tier = r.tier where id = r.landlord_id;
  update public.subscription_payments
  set status = 'confirmed', period_start = v_start, period_end = v_end, reviewed_by = auth.uid(), reviewed_at = now()
  where id = r.id;

  insert into public.staff_notifications (user_id, type, title, body, url)
  values (r.landlord_id, 'subscription', 'Subscription renewed',
    format('Thank you! Your %s scale %s payment of %s was received. Your Renta UG subscription now runs until %s (%s days).',
      initcap(r.tier), r.plan, public.ugx(r.amount), to_char(v_end + 1, 'FMDD Mon YYYY'), public.subscription_days(r.months)),
    '/landlord/subscription');
  perform public.admin_log('subscription.confirm', 'landlord', r.landlord_id,
    format('Confirmed %s %s scale %s subscription from %s, now runs to %s', public.ugx(r.amount), r.tier, r.plan,
      coalesce(nullif(p.full_name, ''), p.email), to_char(v_end + 1, 'FMDD Mon YYYY')));
  return json_build_object('until', v_end + 1, 'start', v_start);
end $$;

create or replace function public.admin_record_subscription_cash(
  p_landlord uuid, p_tier text, p_plan text, p_paid_on date default null, p_note text default null
) returns json
language plpgsql volatile security definer set search_path = '' as $$
declare
  s public.billing_settings;
  p record;
  v_paid_on date := coalesce(p_paid_on, public.kampala_today());
  v_note text := nullif(left(trim(coalesce(p_note, '')), 200), '');
  v_units int;
  v_amount bigint;
  v_months int;
  v_start date;
  v_end date;
  v_id uuid;
begin
  perform public.admin_require();
  select * into p from public.profiles where id = p_landlord and role = 'landlord' for update;
  if not found then raise exception 'Landlord not found.'; end if;
  if p.subscription_exempt then raise exception 'This is the permanent free account: there is nothing to pay.'; end if;
  if p_tier not in ('small', 'big') then raise exception 'Choose Small scale or Big scale.'; end if;
  if p_plan not in ('monthly', 'yearly') then raise exception 'Choose monthly or yearly.'; end if;
  if v_paid_on > public.kampala_today() then raise exception 'The payment date cannot be in the future.'; end if;
  if v_paid_on < public.kampala_today() - 366 then raise exception 'The payment date is more than a year ago.'; end if;

  select * into s from public.billing_settings where id = 1;
  v_units := public.landlord_unit_count(p_landlord);
  if p_tier = 'small' and v_units > s.small_max_units then
    raise exception 'This landlord has % houses and rooms. Small scale covers up to %, so choose Big scale.', v_units, s.small_max_units;
  end if;

  v_amount := case
    when p_tier = 'big' and p_plan = 'yearly' then s.big_yearly
    when p_tier = 'big' then s.big_monthly
    when p_plan = 'yearly' then s.small_yearly
    else s.small_monthly end;
  v_months := case p_plan when 'yearly' then 12 else 1 end;

  v_start := case when p.subscription_until >= public.kampala_today() then p.subscription_until + 1 else public.kampala_today() end;
  v_end := v_start + public.subscription_days(v_months) - 1;

  insert into public.subscription_payments (
    landlord_id, tier, plan, months, amount, network, sender_phone, sender_name, reference, paid_on,
    status, period_start, period_end, reviewed_by, reviewed_at, note
  ) values (
    p_landlord, p_tier, p_plan, v_months, v_amount, 'cash', null, 'CASH', null, v_paid_on,
    'confirmed', v_start, v_end, auth.uid(), now(), v_note
  ) returning id into v_id;

  update public.profiles set subscription_until = v_end, subscription_plan = p_plan, subscription_tier = p_tier where id = p_landlord;

  insert into public.staff_notifications (user_id, type, title, body, url)
  values (p_landlord, 'subscription', 'Subscription paid in cash',
    format('Thank you! Renta UG received your cash payment of %s for %s scale, %s. Your subscription now runs until %s (%s days).',
      public.ugx(v_amount), initcap(p_tier), p_plan, to_char(v_end + 1, 'FMDD Mon YYYY'), public.subscription_days(v_months)),
    '/landlord/subscription');
  perform public.admin_log('subscription.cash', 'landlord', p_landlord,
    format('Recorded %s cash for %s scale %s subscription from %s, now runs to %s%s', public.ugx(v_amount), p_tier, p_plan,
      coalesce(nullif(p.full_name, ''), p.email), to_char(v_end + 1, 'FMDD Mon YYYY'), coalesce(' (' || v_note || ')', '')));

  return json_build_object('id', v_id, 'amount', v_amount, 'start', v_start, 'until', v_end + 1);
end $$;

create or replace function public.admin_grant_subscription(p_landlord uuid, p_days int, p_note text default null) returns date
language plpgsql volatile security definer set search_path = '' as $$
declare
  p record;
  v_end date;
begin
  perform public.admin_require();
  if p_days is null or p_days < 1 or p_days > 730 then raise exception 'Choose between 1 and 730 days.'; end if;
  select * into p from public.profiles where id = p_landlord and role = 'landlord' for update;
  if not found then raise exception 'Landlord not found.'; end if;
  v_end := greatest(coalesce(p.subscription_until, public.kampala_today() - 1), public.kampala_today() - 1) + p_days;
  update public.profiles set subscription_until = v_end where id = p_landlord;
  insert into public.staff_notifications (user_id, type, title, body, url)
  values (p_landlord, 'subscription', 'Subscription extended',
    format('Renta UG added %s day%s to your subscription%s. It now runs until %s.',
      p_days, case when p_days = 1 then '' else 's' end, coalesce(': ' || nullif(trim(p_note), ''), ''), to_char(v_end + 1, 'FMDD Mon YYYY')),
    '/landlord/subscription');
  perform public.admin_log('subscription.grant', 'landlord', p_landlord,
    format('Added %s days to %s''s subscription (now to %s)%s', p_days, coalesce(nullif(p.full_name, ''), p.email),
      to_char(v_end + 1, 'FMDD Mon YYYY'), coalesce(': ' || nullif(trim(p_note), ''), '')));
  return v_end + 1;
end $$;

create or replace function public.send_subscription_reminders() returns integer
language plpgsql volatile security definer set search_path = '' as $$
declare
  today date := public.kampala_today();
  n integer;
begin
  insert into public.staff_notifications (user_id, type, title, body, url)
  select p.id, 'subscription',
    case when d.ended then 'Subscription ended' else 'Subscription ending soon' end,
    case
      when d.ended then format('Your Renta UG subscription ended on %s. Your account is locked until you renew and Renta UG confirms the payment.',
        to_char(p.subscription_until + 1, 'FMDD Mon YYYY'))
      when d.left_days = 0 then 'Your Renta UG subscription ends today. Renew now to keep managing your properties without a break.'
      else format('Your Renta UG subscription ends in %s day%s, on %s. Renew any time: the new period is added on top.',
        d.left_days, case when d.left_days = 1 then '' else 's' end, to_char(p.subscription_until + 1, 'FMDD Mon YYYY'))
    end,
    '/landlord/subscription'
  from public.profiles p
  cross join lateral (select p.subscription_until + 1 - today as left_days, public.subscription_ends_at(p.subscription_until, p.subscription_clock) <= now() as ended) d
  where p.role = 'landlord' and p.active and not p.subscription_exempt and p.subscription_until is not null
    and (d.left_days in (7, 3, 1, 0) or (d.ended and d.left_days = -1))
    and not exists (
      select 1 from public.staff_notifications x
      where x.user_id = p.id and x.type = 'subscription' and x.title in ('Subscription ending soon', 'Subscription ended')
        and x.created_at > now() - interval '20 hours'
    );
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.send_subscription_reminders() from public, anon, authenticated;

-- ── Confirming rent ──
create or replace function public.confirm_cash_payment(p_id uuid, p_amount bigint default null) returns json
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  c public.cash_payments;
  v_reviewer text;
  v_amount bigint;
  v_left bigint;
  v_take bigint;
  v_completed text[] := '{}';
  v_ahead int := 0;
  v_balance_after bigint;
  v_tenant record;
  v_rent bigint;
  v_period text;
  v_charge uuid;
  v_label text;
  v_paid_at timestamptz;
  v_old_end date;
  v_new_end date;
  v_debt int := 0;
  v_days int;
  v_day date;
  v_ends timestamptz;
  r record;
begin
  select * into c from public.cash_payments where id = p_id for update;
  if not found then raise exception 'Payment not found.'; end if;
  if c.status <> 'pending' then raise exception 'This payment has already been %.', c.status; end if;
  v_reviewer := public.can_review_cash(c);

  v_amount := coalesce(p_amount, c.amount);
  if v_amount <= 0 then raise exception 'Enter an amount greater than zero.'; end if;
  -- Saved on the receipt and the rent month: "MTN Mobile Money", "Airtel Money" or "Cash"
  v_label := case when c.method = 'mobile_money'
    then case c.network when 'mtn' then 'MTN Mobile Money' when 'airtel' then 'Airtel Money' else 'Mobile money' end
    else 'Cash' end;
  v_paid_at := c.paid_on::timestamptz + interval '12 hours';

  select * into v_tenant from public.tenants where id = c.tenant_id;
  select rent into v_rent from public.properties where id = v_tenant.property_id;
  if v_amount > public.tenant_outstanding(c.tenant_id) then
    if v_tenant.property_id is null or coalesce(v_rent, 0) <= 0 then
      raise exception 'That is more than the unpaid rent of %, and there is no monthly rent to pay ahead.', public.ugx(public.tenant_outstanding(c.tenant_id));
    end if;
    if v_amount - public.tenant_outstanding(c.tenant_id) > v_rent * 24 then
      raise exception 'That pays more than 2 years ahead.';
    end if;
  end if;

  -- First payment. Sent by the tenant: their time starts the moment it is confirmed. Recorded by the landlord: on
  -- the day they chose. The time of day is kept by tenants_rent_clock (below).
  v_old_end := v_tenant.lease_end;
  v_day := case when v_old_end is null and c.submitted_role = 'tenant' then public.kampala_today() else c.paid_on end;
  v_ends := public.rent_ends_at(v_tenant.lease_end, v_tenant.rent_clock);
  if v_old_end is null and v_tenant.property_id is not null then
    update public.tenants set lease_start = v_day where id = c.tenant_id;
  end if;

  v_left := v_amount;

  -- 1. Unpaid rent, oldest first
  for r in
    select * from public.payments
    where tenant_id = c.tenant_id and status = 'pending'
    order by due_date, period
    for update
  loop
    exit when v_left <= 0;
    v_take := least(v_left, r.amount - r.amount_paid);
    v_left := v_left - v_take;

    insert into public.payment_receipts (payment_id, tenant_id, landlord_id, amount, method, note, received_at, recorded_by)
    values (r.id, c.tenant_id, c.landlord_id, v_take, v_label, c.note, v_paid_at, me);

    update public.payments
    set amount_paid = amount_paid + v_take,
        status = case when amount_paid + v_take >= amount then 'paid' else 'pending' end,
        paid_at = case when amount_paid + v_take >= amount then v_paid_at else paid_at end,
        method = v_label
    where id = r.id;

    if r.amount_paid + v_take >= r.amount then
      v_completed := v_completed || to_char(to_date(r.period || '-01', 'YYYY-MM-DD'), 'FMMonth YYYY');
    end if;
  end loop;

  -- 2. Whatever is left pays the next months ahead
  while v_left > 0 loop
    v_period := public.next_rent_period(c.tenant_id);
    v_take := least(v_left, v_rent);

    insert into public.payments (landlord_id, tenant_id, property_id, period, amount, amount_paid, due_date, status, paid_at, method)
    values (
      c.landlord_id, c.tenant_id, v_tenant.property_id, v_period, v_rent, v_take,
      to_date(v_period || '-05', 'YYYY-MM-DD'),
      case when v_take >= v_rent then 'paid' else 'pending' end,
      case when v_take >= v_rent then v_paid_at end,
      v_label)
    returning id into v_charge;

    insert into public.payment_receipts (payment_id, tenant_id, landlord_id, amount, method, note, received_at, recorded_by)
    values (v_charge, c.tenant_id, c.landlord_id, v_take, v_label, c.note, v_paid_at, me);

    if v_take >= v_rent then
      v_completed := v_completed || to_char(to_date(v_period || '-01', 'YYYY-MM-DD'), 'FMMonth YYYY');
    end if;
    v_left := v_left - v_take;
  end loop;

  update public.cash_payments
  set status = 'confirmed', confirmed_amount = v_amount, reviewed_by = me, reviewed_role = v_reviewer, reviewed_at = now()
  where id = c.id;

  v_balance_after := public.tenant_outstanding(c.tenant_id);
  select lease_end into v_new_end from public.tenants where id = c.tenant_id;
  -- Debt days: whole 24 hours since the exact end
  if v_ends is not null then
    v_debt := greatest(0, floor(extract(epoch from (
      case when c.paid_on >= public.kampala_today() then now()
           else (c.paid_on + coalesce(v_tenant.rent_clock, time '24:00')) at time zone 'Africa/Kampala' end - v_ends)) / 86400)::int);
  end if;
  if v_new_end is not null then
    v_days := v_new_end - greatest(v_day, coalesce(v_old_end, v_day));
    -- Whole months paid beyond the month running today (from the real rent cycle, not calendar months)
    if v_new_end is distinct from v_old_end then
      select (extract(year from a) * 12 + extract(month from a))::int into v_ahead
      from (select age(v_new_end, public.kampala_today()) as a) x;
      v_ahead := greatest(0, v_ahead);
    end if;
  end if;

  -- Tenant (also sent by SMS when SMS is switched on)
  insert into public.notifications (landlord_id, tenant_id, type, title, body)
  values (c.landlord_id, c.tenant_id, 'payment', 'Payment confirmation',
    format('Your %s payment of %s made on %s has been successfully received and confirmed by %s%s.%s%s%s %s',
      case when c.method = 'mobile_money' then 'mobile money' else 'cash' end,
      public.ugx(v_amount),
      to_char(c.paid_on, 'FMDD Mon YYYY'),
      case when v_reviewer = 'superadmin' then 'Renta UG' else 'your landlord' end,
      case when v_amount <> c.amount then format(' (you reported %s)', public.ugx(c.amount)) else '' end,
      case when v_debt > 0 and v_new_end is distinct from v_old_end then format(' You paid %s day%s late: those debt days were taken from your new month.',
        v_debt, case when v_debt = 1 then '' else 's' end) else '' end,
      case when v_new_end is not null and v_new_end is distinct from v_old_end
        then format(' Your rent now runs to %s.', to_char(v_new_end, 'FMDD Mon YYYY')) else '' end,
      case when v_ahead > 0 then format(' That includes %s month%s paid ahead.', v_ahead, case when v_ahead = 1 then '' else 's' end) else '' end,
      case when v_balance_after = 0 then 'You have no outstanding balance. Thank you.'
           else format('Outstanding balance: %s.', public.ugx(v_balance_after)) end));

  return json_build_object(
    'applied', v_amount, 'balance_after', v_balance_after, 'completed', array_to_json(v_completed),
    'months_ahead', v_ahead, 'debt_days', v_debt, 'paid_to', v_new_end, 'days', v_days);
end $$;

-- ── Overdue reminder: from the first complete debt day ──
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
             public.ugx(o.amount::bigint), p.name, to_char(o.since, 'FMDD Mon YYYY'))
      else format('Your rent month for %s ended on %s. You now have %s debt day%s: they will be taken from your next month, which still runs from %s. Please pay soon.',
             p.name, to_char(t.lease_end, 'FMDD Mon YYYY'), d.debt,
             case when d.debt = 1 then '' else 's' end, to_char(t.lease_end, 'FMDD Mon')) end
  from public.tenants t
  join public.properties p on p.id = t.property_id
  cross join lateral (
    select coalesce(sum(amount - amount_paid), 0) as amount, min(due_date) as since
    from public.payments where tenant_id = t.id and status = 'pending' and due_date < today
  ) o
  cross join lateral (
    select floor(extract(epoch from now() - public.rent_ends_at(t.lease_end, t.rent_clock)) / 86400)::int as debt
  ) d
  where t.property_id is not null
    and t.user_id is not null
    and (o.amount > 0 or d.debt >= 1)
    and not exists (
      select 1 from public.notifications x
      where x.tenant_id = t.id and x.type = 'rent_due' and x.created_at > now() - interval '71 hours'
    );
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.send_overdue_reminders() from public, anon, authenticated;
