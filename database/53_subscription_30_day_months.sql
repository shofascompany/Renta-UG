-- 53 · landlord subscriptions: a month is 30 days (safe to run again; no data is deleted)
--
--  Monthly subscription = exactly 30 days (never 28, 29 or 31), like rent months (database/52).
--  Yearly subscription  = 365 days.
--  Periods already confirmed keep their dates; this applies to payments confirmed from now on, whether
--  confirmed from mobile money (admin_confirm_subscription_payment) or recorded as cash
--  (admin_record_subscription_cash).

create or replace function public.subscription_days(p_months int) returns int
language sql immutable set search_path = '' as $$
  select case when p_months >= 12 then 365 * (p_months / 12) + 30 * (p_months % 12) else 30 * greatest(p_months, 1) end;
$$;
revoke execute on function public.subscription_days(int) from public, anon;
grant execute on function public.subscription_days(int) to authenticated, service_role;

-- ── Main admin: confirm a mobile money payment → on top of any time left ──
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
      initcap(r.tier), r.plan, public.ugx(r.amount), to_char(v_end, 'FMDD Mon YYYY'), public.subscription_days(r.months)),
    '/landlord/subscription');
  perform public.admin_log('subscription.confirm', 'landlord', r.landlord_id,
    format('Confirmed %s %s scale %s subscription from %s, now runs to %s', public.ugx(r.amount), r.tier, r.plan,
      coalesce(nullif(p.full_name, ''), p.email), to_char(v_end, 'FMDD Mon YYYY')));
  return json_build_object('until', v_end, 'start', v_start);
end $$;

-- ── Main admin: a subscription paid in cash → recorded as paid, extended at once ──
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
      public.ugx(v_amount), initcap(p_tier), p_plan, to_char(v_end, 'FMDD Mon YYYY'), public.subscription_days(v_months)),
    '/landlord/subscription');
  perform public.admin_log('subscription.cash', 'landlord', p_landlord,
    format('Recorded %s cash for %s scale %s subscription from %s, now runs to %s%s', public.ugx(v_amount), p_tier, p_plan,
      coalesce(nullif(p.full_name, ''), p.email), to_char(v_end, 'FMDD Mon YYYY'), coalesce(' (' || v_note || ')', '')));

  return json_build_object('id', v_id, 'amount', v_amount, 'start', v_start, 'until', v_end);
end $$;
revoke execute on function public.admin_record_subscription_cash(uuid, text, text, date, text) from public, anon;
grant execute on function public.admin_record_subscription_cash(uuid, text, text, date, text) to authenticated;
