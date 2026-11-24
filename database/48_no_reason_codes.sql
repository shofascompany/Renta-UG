-- 48 · no payment reason codes (safe to run again; no data is deleted)
--
--  Payments are matched by the FULL NAMES registered on the line the money was sent from, not by a
--  reason / reference code typed on the phone.
--  • Landlord subscriptions: the landlord only enters the names registered on the line they paid from.
--    The phone number is optional (older app versions still send it).
--  • Tenants: the landlord is told the names; no more "pay word".
--  • New tenants and landlords no longer get a code. Old codes stay in the database, unused.

-- ── Stop creating codes ──
drop trigger if exists tenants_pay_code on public.tenants;
drop trigger if exists profiles_landlord_billing on public.profiles;

-- ── Subscription payments: phone and reference are optional now ──
alter table public.subscription_payments alter column sender_phone drop not null;
alter table public.subscription_payments alter column reference drop not null;

create or replace function public.submit_subscription_payment(
  p_tier text, p_plan text, p_network text, p_sender_phone text, p_sender_name text, p_paid_on date default null
) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  s public.billing_settings;
  p record;
  v_paid_on date := coalesce(p_paid_on, public.kampala_today());
  v_phone text := nullif(regexp_replace(coalesce(p_sender_phone, ''), '[^0-9+]', '', 'g'), '');
  v_name text := upper(left(regexp_replace(trim(coalesce(p_sender_name, '')), '\s+', ' ', 'g'), 80));
  v_units int;
  v_amount bigint;
  v_id uuid;
begin
  select * into p from public.profiles where id = me;
  if p.role is distinct from 'landlord' then raise exception 'Only landlords have a subscription.'; end if;
  if p.subscription_exempt then raise exception 'Your account is free for life: there is nothing to pay.'; end if;
  if not p.active then raise exception 'This account is suspended. Please contact Renta UG.'; end if;
  if p_tier not in ('small', 'big') then raise exception 'Choose Small scale or Big scale.'; end if;
  if p_plan not in ('monthly', 'yearly') then raise exception 'Choose monthly or yearly.'; end if;
  if p_network not in ('mtn', 'airtel') then raise exception 'Choose MTN or Airtel.'; end if;

  select * into s from public.billing_settings where id = 1;
  v_units := public.landlord_unit_count(me);
  if p_tier = 'small' and v_units > s.small_max_units then
    raise exception 'You have % houses and rooms. Small scale covers up to %, so please choose Big scale.', v_units, s.small_max_units;
  end if;
  if (p_network = 'mtn' and s.mtn_phone is null) or (p_network = 'airtel' and s.airtel_phone is null) then
    raise exception 'Renta UG has not added a number for this network yet.';
  end if;
  if length(v_name) < 5 or v_name !~ '\S+\s+\S+' then
    raise exception 'Enter the full names registered on the line you paid from (at least two names).';
  end if;
  if v_paid_on > public.kampala_today() then raise exception 'The payment date cannot be in the future.'; end if;
  if v_paid_on < public.kampala_today() - 30 then raise exception 'That payment date is more than 30 days ago. Contact Renta UG.'; end if;
  if exists (select 1 from public.subscription_payments where landlord_id = me and status = 'pending') then
    raise exception 'You already have a payment waiting to be confirmed.';
  end if;

  v_amount := case
    when p_tier = 'big' and p_plan = 'yearly' then s.big_yearly
    when p_tier = 'big' then s.big_monthly
    when p_plan = 'yearly' then s.small_yearly
    else s.small_monthly end;

  insert into public.subscription_payments (landlord_id, tier, plan, months, amount, network, sender_phone, sender_name, reference, paid_on)
  values (me, p_tier, p_plan, case p_plan when 'yearly' then 12 else 1 end, v_amount, p_network, v_phone, v_name, null, v_paid_on)
  returning id into v_id;

  insert into public.staff_notifications (user_id, type, title, body, url)
  select id, 'subscription', 'Subscription payment to confirm',
    format('%s says they sent %s to your %s line for %s scale, %s, from a line registered to %s. Check the money, then confirm it.',
      coalesce(nullif(p.full_name, ''), p.email), public.ugx(v_amount),
      case p_network when 'mtn' then 'MTN' else 'Airtel' end, initcap(p_tier), p_plan, v_name),
    '/admin2026/subscriptions'
  from public.profiles where role = 'superadmin';

  return v_id;
end $$;
revoke execute on function public.submit_subscription_payment(text, text, text, text, text, date) from public, anon;
grant execute on function public.submit_subscription_payment(text, text, text, text, text, date) to authenticated;

-- ── Tenants: the landlord's message names the sender, no pay word ──
create or replace function public.submit_payment(
  p_tenant_id uuid,
  p_amount bigint,
  p_paid_on date default null,
  p_note text default null,
  p_method text default 'cash',
  p_network text default null
) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  v_role text;
  v_tenant record;
  v_house text;
  v_rent bigint;
  v_outstanding bigint;
  v_pending bigint;
  v_paid_on date := coalesce(p_paid_on, public.kampala_today());
  v_method text := coalesce(nullif(p_method, ''), 'cash');
  v_network text := nullif(lower(p_network), '');
  v_net_label text;
  v_note text := nullif(trim(p_note), '');
  v_id uuid;
begin
  if v_method not in ('cash', 'mobile_money') then raise exception 'Choose cash or mobile money.'; end if;
  if v_method = 'mobile_money' and v_network is not null and v_network not in ('mtn', 'airtel') then
    raise exception 'Choose MTN or Airtel.';
  end if;
  v_net_label := case v_network when 'mtn' then 'MTN' when 'airtel' then 'Airtel' end;

  select role into v_role from public.profiles where id = me;
  if v_role = 'tenant' then
    select * into v_tenant from public.tenants where id = coalesce(p_tenant_id, public.my_tenant_id()) and user_id = me;
    if not found or v_tenant.property_id is null then raise exception 'You are not connected to a house.'; end if;
    if (select count(*) from public.cash_payments where tenant_id = v_tenant.id and status = 'pending') >= 3 then
      raise exception 'You already have payments waiting for your landlord. Wait for them to be checked first.';
    end if;
    if v_method = 'mobile_money' and not exists (
      select 1 from public.landlord_pay_accounts where landlord_id = v_tenant.landlord_id and network = v_network
    ) then
      raise exception 'Your landlord has not added a number for this network.';
    end if;
    if v_method = 'mobile_money' and coalesce(length(v_note), 0) < 5 then
      raise exception 'Enter the full names registered on the line you paid from.';
    end if;
  elsif public.is_landlord() then
    select * into v_tenant from public.tenants where id = p_tenant_id and landlord_id = me;
    if not found then raise exception 'Tenant not found.'; end if;
    if v_tenant.property_id is null then raise exception 'This tenant no longer rents from you.'; end if;
    v_role := 'landlord';
  else
    raise exception 'Only tenants and landlords can record payments.';
  end if;

  if p_amount is null or p_amount <= 0 then raise exception 'Enter an amount greater than zero.'; end if;
  if v_paid_on > public.kampala_today() then raise exception 'The payment date cannot be in the future.'; end if;
  if v_paid_on < public.kampala_today() - 366 then raise exception 'The payment date is more than a year ago.'; end if;

  select name, rent into v_house, v_rent from public.properties where id = v_tenant.property_id;
  v_outstanding := public.tenant_outstanding(v_tenant.id);
  select coalesce(sum(amount), 0) into v_pending from public.cash_payments where tenant_id = v_tenant.id and status = 'pending';

  if p_amount + v_pending > v_outstanding then
    if coalesce(v_rent, 0) <= 0 then
      raise exception 'This house has no monthly rent set, so money beyond what is owed cannot be recorded.';
    end if;
    if p_amount + v_pending - v_outstanding > v_rent * 24 then
      raise exception '%', format('That pays more than 2 years ahead (rent is %s a month).', public.ugx(v_rent));
    end if;
  end if;

  insert into public.cash_payments (tenant_id, landlord_id, amount, paid_on, note, submitted_by, submitted_role, method, network)
  values (v_tenant.id, v_tenant.landlord_id, p_amount, v_paid_on, v_note, me, v_role, v_method, v_network)
  returning id into v_id;

  if v_role = 'tenant' then
    if v_method = 'mobile_money' then
      insert into public.staff_notifications (user_id, type, title, body, url)
      values (v_tenant.landlord_id, 'cash', 'Mobile money to confirm',
        format('%s says they sent you %s on %s%s. %s. Check your phone, then confirm it.',
          v_tenant.full_name, public.ugx(p_amount), coalesce(v_net_label, 'mobile money'),
          coalesce(' (' || v_house || ')', ''), coalesce(v_note, 'No sender names given')),
        '/landlord/payments');
      insert into public.notifications (landlord_id, tenant_id, type, title, body)
      values (v_tenant.landlord_id, v_tenant.id, 'payment', 'Payment being reviewed',
        format('We received your %s payment of %s. Your landlord is checking it and your rent will be updated soon.',
          coalesce(v_net_label, 'mobile money'), public.ugx(p_amount)));
    else
      insert into public.staff_notifications (user_id, type, title, body, url)
      values (v_tenant.landlord_id, 'cash', 'Cash payment to confirm',
        format('%s says they paid you %s in cash on %s%s. Please confirm the amount you received.',
          v_tenant.full_name, public.ugx(p_amount), to_char(v_paid_on, 'FMDD Mon YYYY'), coalesce(' for ' || v_house, '')),
        '/landlord/payments');
    end if;
  else
    perform public.confirm_cash_payment(v_id, null); -- the landlord received it: it counts now
  end if;

  return v_id;
end $$;
revoke execute on function public.submit_payment(uuid, bigint, date, text, text, text) from public, anon;
grant execute on function public.submit_payment(uuid, bigint, date, text, text, text) to authenticated;
