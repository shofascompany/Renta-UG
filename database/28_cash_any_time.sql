-- 28 · cash at any time
-- Cash can be recorded for any current tenant, whether rent is due or not.
-- When it's confirmed it pays unpaid rent first (oldest first); anything left pays the NEXT months
-- ahead at the house's monthly rent (rent charges are created for those months, like a recharge).
-- Up to 24 months ahead. Replaces submit_cash_payment / confirm_cash_payment from 24.
-- Safe to run more than once. No data is deleted.

-- Next rent month for a tenant: the month after their latest charge, or this month if that's later
create or replace function public.next_rent_period(p_tenant_id uuid) returns text
language sql stable security definer set search_path = '' as $$
  select greatest(
    coalesce(to_char((to_date(max(period) || '-01', 'YYYY-MM-DD') + interval '1 month'), 'YYYY-MM'), '0000-00'),
    to_char(public.kampala_today(), 'YYYY-MM'))
  from public.payments where tenant_id = p_tenant_id;
$$;
revoke execute on function public.next_rent_period(uuid) from public, anon, authenticated;

-- ── Report / record cash ──
create or replace function public.submit_cash_payment(
  p_tenant_id uuid,
  p_amount bigint,
  p_paid_on date default null,
  p_note text default null
) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  v_role text;
  v_tenant record;
  v_house text;
  v_rent bigint;
  v_landlord_name text;
  v_outstanding bigint;
  v_pending bigint;
  v_paid_on date := coalesce(p_paid_on, public.kampala_today());
  v_id uuid;
begin
  select role into v_role from public.profiles where id = me;

  if v_role = 'tenant' then
    select * into v_tenant from public.tenants where id = coalesce(p_tenant_id, public.my_tenant_id()) and user_id = me;
    if not found or v_tenant.property_id is null then
      raise exception 'You are not connected to a house.';
    end if;
  elsif public.is_landlord() then
    select * into v_tenant from public.tenants where id = p_tenant_id and landlord_id = me;
    if not found then raise exception 'Tenant not found.'; end if;
    if v_tenant.property_id is null then raise exception 'This tenant no longer rents from you.'; end if;
    v_role := 'landlord';
  else
    raise exception 'Only tenants and landlords can record cash payments.';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Enter an amount greater than zero.';
  end if;
  if v_paid_on > public.kampala_today() then
    raise exception 'The payment date cannot be in the future.';
  end if;

  select name, rent into v_house, v_rent from public.properties where id = v_tenant.property_id;
  v_outstanding := public.tenant_outstanding(v_tenant.id);
  select coalesce(sum(amount), 0) into v_pending from public.cash_payments where tenant_id = v_tenant.id and status = 'pending';

  -- Beyond what's owed, the rest pays months ahead: needs a monthly rent, at most 24 months
  if p_amount + v_pending > v_outstanding then
    if coalesce(v_rent, 0) <= 0 then
      raise exception 'This house has no monthly rent set, so cash beyond what is owed cannot be recorded.';
    end if;
    if p_amount + v_pending - v_outstanding > v_rent * 24 then
      raise exception '%', format('That pays more than 2 years ahead (rent is %s a month).', public.ugx(v_rent));
    end if;
  end if;

  insert into public.cash_payments (tenant_id, landlord_id, amount, paid_on, note, submitted_by, submitted_role)
  values (v_tenant.id, v_tenant.landlord_id, p_amount, v_paid_on, nullif(trim(p_note), ''), me, v_role)
  returning id into v_id;

  select nullif(full_name, '') into v_landlord_name from public.profiles where id = v_tenant.landlord_id;

  if v_role = 'tenant' then
    insert into public.staff_notifications (user_id, type, title, body, url)
    values (v_tenant.landlord_id, 'cash', 'Cash payment to confirm',
      format('%s says they paid you %s in cash on %s%s. Please confirm the amount you received.',
        v_tenant.full_name, public.ugx(p_amount), to_char(v_paid_on, 'FMDD Mon YYYY'), coalesce(' for ' || v_house, '')),
      '/landlord/payments');
    perform public.notify_admins('cash', 'Cash payment reported',
      format('%s (%s) reported paying %s in cash on %s. Waiting for confirmation.',
        v_tenant.full_name, coalesce(v_house, 'no house'), public.ugx(p_amount), to_char(v_paid_on, 'FMDD Mon YYYY')));
  else
    perform public.notify_admins('cash', 'Cash payment to confirm',
      format('%s recorded %s in cash from %s (%s) on %s. Please confirm.',
        coalesce(v_landlord_name, 'A landlord'), public.ugx(p_amount), v_tenant.full_name, coalesce(v_house, 'no house'),
        to_char(v_paid_on, 'FMDD Mon YYYY')));
    insert into public.notifications (landlord_id, tenant_id, type, title, body)
    values (v_tenant.landlord_id, v_tenant.id, 'payment', 'Cash payment received',
      format('Your landlord recorded a cash payment of %s from you on %s. It will be added to your rent as soon as Renta UG confirms it.',
        public.ugx(p_amount), to_char(v_paid_on, 'FMDD Mon YYYY')));
  end if;

  return v_id;
end $$;

-- ── Confirm: unpaid rent first, then months ahead ──
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
  v_house text;
  v_landlord_name text;
  v_period text;
  v_charge uuid;
  r record;
begin
  select * into c from public.cash_payments where id = p_id for update;
  if not found then raise exception 'Payment not found.'; end if;
  if c.status <> 'pending' then raise exception 'This payment has already been %.', c.status; end if;
  v_reviewer := public.can_review_cash(c);

  v_amount := coalesce(p_amount, c.amount);
  if v_amount <= 0 then raise exception 'Enter an amount greater than zero.'; end if;

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
    values (r.id, c.tenant_id, c.landlord_id, v_take, 'Cash', c.note, c.paid_on::timestamptz + interval '12 hours', me);

    update public.payments
    set amount_paid = amount_paid + v_take,
        status = case when amount_paid + v_take >= amount then 'paid' else 'pending' end,
        paid_at = case when amount_paid + v_take >= amount then now() else paid_at end,
        method = 'Cash'
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
      case when v_take >= v_rent then now() end,
      'Cash')
    returning id into v_charge;

    insert into public.payment_receipts (payment_id, tenant_id, landlord_id, amount, method, note, received_at, recorded_by)
    values (v_charge, c.tenant_id, c.landlord_id, v_take, 'Cash', c.note, c.paid_on::timestamptz + interval '12 hours', me);

    if v_take >= v_rent then
      v_completed := v_completed || to_char(to_date(v_period || '-01', 'YYYY-MM-DD'), 'FMMonth YYYY');
      v_ahead := v_ahead + 1;
    end if;
    v_left := v_left - v_take;
  end loop;

  update public.cash_payments
  set status = 'confirmed', confirmed_amount = v_amount, reviewed_by = me, reviewed_role = v_reviewer, reviewed_at = now()
  where id = c.id;

  v_balance_after := public.tenant_outstanding(c.tenant_id);
  select name into v_house from public.properties where id = coalesce(v_tenant.property_id, v_tenant.last_property_id);
  select nullif(full_name, '') into v_landlord_name from public.profiles where id = c.landlord_id;

  -- Tenant
  insert into public.notifications (landlord_id, tenant_id, type, title, body)
  values (c.landlord_id, c.tenant_id, 'payment', 'Payment confirmation',
    format('Your cash payment of %s made on %s has been confirmed by %s%s.%s%s %s',
      public.ugx(v_amount),
      to_char(c.paid_on, 'FMDD Mon YYYY'),
      case when v_reviewer = 'superadmin' then 'Renta UG' else 'your landlord' end,
      case when v_amount <> c.amount then format(' (you reported %s)', public.ugx(c.amount)) else '' end,
      case when array_length(v_completed, 1) > 0
        then format(' Rent for %s is now paid in full.', array_to_string(v_completed, ', ')) else '' end,
      case when v_ahead > 0 then format(' That includes %s month%s paid ahead.', v_ahead, case when v_ahead = 1 then '' else 's' end) else '' end,
      case when v_balance_after = 0 then 'You have no outstanding balance. Thank you.'
           else format('Outstanding balance: %s.', public.ugx(v_balance_after)) end));

  -- The other side
  if v_reviewer = 'superadmin' then
    insert into public.staff_notifications (user_id, type, title, body, url)
    values (c.landlord_id, 'cash', 'Cash payment confirmed',
      format('Renta UG confirmed %s in cash from %s%s. It has been added to their rent.',
        public.ugx(v_amount), v_tenant.full_name, coalesce(' (' || v_house || ')', '')),
      '/landlord/payments');
  else
    perform public.notify_admins('cash', 'Cash payment confirmed',
      format('%s confirmed %s in cash from %s%s.',
        coalesce(v_landlord_name, 'A landlord'), public.ugx(v_amount), v_tenant.full_name, coalesce(' (' || v_house || ')', '')));
  end if;

  return json_build_object('applied', v_amount, 'balance_after', v_balance_after, 'completed', array_to_json(v_completed), 'months_ahead', v_ahead);
end $$;

revoke execute on function public.submit_cash_payment(uuid, bigint, date, text) from public, anon;
revoke execute on function public.confirm_cash_payment(uuid, bigint) from public, anon;
grant execute on function public.submit_cash_payment(uuid, bigint, date, text) to authenticated;
grant execute on function public.confirm_cash_payment(uuid, bigint) to authenticated;
