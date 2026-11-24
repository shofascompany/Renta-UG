-- 51 · business size at first sign-in + subscriptions paid in cash (safe to run again; no data is deleted)
--
--  Business size
--   • Right after a new landlord creates their password, they say how many houses and rooms they will
--     register (profiles.planned_units). Renta UG recommends the package that fits it, and Small scale
--     can't be chosen when the number is above its limit.
--   • The main admin sees the number on the landlord's page.
--
--  Cash
--   • The main admin can record a subscription the landlord paid in cash: choose the landlord, the package
--     (Small / Big) and monthly / yearly. It is saved as a confirmed payment (network 'cash') and the
--     subscription is extended at once, on top of any time left, exactly like a confirmed mobile money payment.

-- ── Business size ──
alter table public.profiles add column if not exists planned_units int;
do $$ begin
  alter table public.profiles add constraint profiles_planned_units_check check (planned_units is null or planned_units between 1 and 100000);
exception when duplicate_object then null; end $$;

create or replace function public.set_planned_units(p_units int) returns void
language plpgsql volatile security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role = 'landlord') then
    raise exception 'Only landlords can set this.';
  end if;
  if p_units is null or p_units < 1 or p_units > 100000 then
    raise exception 'Enter how many houses and rooms you will register (at least 1).';
  end if;
  update public.profiles set planned_units = p_units where id = auth.uid();
end $$;
revoke execute on function public.set_planned_units(int) from public, anon;
grant execute on function public.set_planned_units(int) to authenticated;

-- ── Cash: a payment can also be 'cash' (recorded by the main admin) ──
alter table public.subscription_payments drop constraint if exists subscription_payments_network_check;
alter table public.subscription_payments add constraint subscription_payments_network_check check (network in ('mtn', 'airtel', 'cash'));
alter table public.subscription_payments add column if not exists note text;

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

  -- On top of any time left, otherwise from today
  v_start := case when p.subscription_until >= public.kampala_today() then p.subscription_until + 1 else public.kampala_today() end;
  v_end := (v_start + make_interval(months => v_months) - interval '1 day')::date;

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
    format('Thank you! Renta UG received your cash payment of %s for %s scale, %s. Your subscription now runs until %s.',
      public.ugx(v_amount), initcap(p_tier), p_plan, to_char(v_end, 'FMDD Mon YYYY')),
    '/landlord/subscription');
  perform public.admin_log('subscription.cash', 'landlord', p_landlord,
    format('Recorded %s cash for %s scale %s subscription from %s, now runs to %s%s', public.ugx(v_amount), p_tier, p_plan,
      coalesce(nullif(p.full_name, ''), p.email), to_char(v_end, 'FMDD Mon YYYY'), coalesce(' (' || v_note || ')', '')));

  return json_build_object('id', v_id, 'amount', v_amount, 'start', v_start, 'until', v_end);
end $$;
revoke execute on function public.admin_record_subscription_cash(uuid, text, text, date, text) from public, anon;
grant execute on function public.admin_record_subscription_cash(uuid, text, text, date, text) to authenticated;
