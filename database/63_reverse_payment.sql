-- 63 · reverse a payment · money paid with debt days pays those days first (safe to run again)
--
--  REVERSE A PAYMENT (the tenant's landlord, or the main admin). "A payment" is everything one confirmation saved:
--  its receipts, one per rent month it paid, all written together (same tenant, same moment, same date received),
--  and the cash / mobile money record it came from. Reversing it undoes exactly what it did:
--    • every rent month it paid has that money taken off again: amount_paid, status, paid_at and the days it gave
--      (the same rules as 52 and 55). A month ahead that this payment created, and nothing else paid, is removed.
--    • the tenant's rental time goes back by the days it gave. Their only payment → no paid time, as before it.
--    • the cash / mobile money record stays, marked 'reversed' (when, and by whom)
--    • the tenant gets a notification (and the landlord too, when the main admin did it)
--  Its receipts are deleted, so Transactions, totals and reports no longer count it. Browsers still cannot write
--  payments themselves (54); only this function can.
--
--  DEBT DAYS FIRST. A tenant whose paid time has run out has debt days. Money they pay covers those days first and
--  only the rest is added (52 already counts it so: the new time runs on from the old end). The confirmation now
--  says it plainly: "Your 9 debt days have been paid for first, so the remaining 21 days were added to your rental
--  time." The payment itself stays one payment of the amount paid.

-- ── A reversed payment keeps its record ──
alter table public.cash_payments add column if not exists reversed_at timestamptz;
alter table public.cash_payments add column if not exists reversed_by uuid references auth.users (id) on delete set null;
alter table public.cash_payments add column if not exists reversed_role text;
do $$
declare c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'public.cash_payments'::regclass and contype = 'c'
      and pg_get_constraintdef(oid) ~ '\mstatus\M' and pg_get_constraintdef(oid) !~ 'reversed'
  loop
    execute format('alter table public.cash_payments drop constraint %I', c.conname);
  end loop;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.cash_payments'::regclass and contype = 'c' and pg_get_constraintdef(oid) ~ 'reversed'
  ) then
    alter table public.cash_payments add constraint cash_payments_status_check
      check (status in ('pending', 'confirmed', 'rejected', 'reversed'));
  end if;
end $$;

-- ── Reverse one payment. p_receipt_id: any one of its receipts ──
create or replace function public.reverse_payment(p_receipt_id uuid) returns json
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  v_role text;
  r0 public.payment_receipts%rowtype;
  t public.tenants%rowtype;
  rc public.payment_receipts%rowtype;
  p public.payments%rowtype;
  c public.cash_payments%rowtype;
  v_paid bigint;
  v_full boolean;
  v_mc boolean;
  v_old_days int;
  v_new_days int;
  v_back int := 0;
  v_total bigint := 0;
  v_periods text[] := '{}';
  v_removed int := 0;
  v_end date;
  v_method text;
  v_months text;
  v_day text;
begin
  select * into r0 from public.payment_receipts where id = p_receipt_id;
  if not found then
    raise exception 'This payment was not found. It may have been reversed already.';
  end if;
  if public.is_superadmin() then
    v_role := 'superadmin';
  elsif public.is_landlord() and r0.landlord_id = me then
    v_role := 'landlord';
  else
    raise exception 'This payment was not found. It may have been reversed already.';
  end if;

  select * into t from public.tenants where id = r0.tenant_id for update;
  v_end := t.lease_end;
  v_day := to_char((r0.received_at at time zone 'Africa/Kampala')::date, 'FMDD Mon YYYY');

  -- The cash / mobile money record it came from: confirmed in that same moment
  select * into c from public.cash_payments
  where tenant_id = r0.tenant_id and status = 'confirmed' and reviewed_at = r0.created_at
  order by created_at
  limit 1
  for update;

  -- Every receipt of this payment (one per rent month it paid): each month goes back to what it was without it
  for rc in
    select * from public.payment_receipts
    where tenant_id = r0.tenant_id and created_at = r0.created_at and received_at = r0.received_at
    order by id
    for update
  loop
    select * into p from public.payments where id = rc.payment_id for update;
    v_total := v_total + rc.amount;
    v_periods := v_periods || p.period;

    -- Days the month gave with this money, and without it (the same rules as 52 and 55)
    v_old_days := case when p.month_credited then 30 else coalesce(p.credited_days, 0) end;
    v_paid := greatest(0, p.amount_paid - rc.amount);
    v_full := p.amount > 0 and v_paid >= p.amount;
    if v_full then
      v_new_days := 30; v_mc := true;
    elsif p.month_credited and p.amount > 0 and p.amount_paid < p.amount and v_paid * 10 >= p.amount * 6 then
      v_new_days := 30; v_mc := true; -- counted under the old 60% rule and never paid in full: it keeps its month
    elsif p.amount > 0 then
      v_new_days := floor(v_paid::numeric * 30 / p.amount)::int; v_mc := false;
    else
      v_new_days := v_old_days; v_mc := p.month_credited;
    end if;
    v_back := v_back + greatest(0, v_old_days - v_new_days);

    delete from public.payment_receipts where id = rc.id;

    if v_paid = 0
       and not exists (select 1 from public.payment_receipts where payment_id = p.id)
       and (p.created_at = rc.created_at
            or exists (select 1 from public.cash_payments x
                       where x.tenant_id = p.tenant_id and x.status = 'reversed' and x.reviewed_at = p.created_at)) then
      -- A month that this payment created (or one reversed before it), and nothing else pays: it goes with it.
      -- Months are only ever created by payments (28, 41, 61); older unpaid months are kept.
      delete from public.payments where id = p.id;
      v_removed := v_removed + 1;
    else
      v_method := null;
      select method into v_method from public.payment_receipts
      where payment_id = p.id order by received_at desc, created_at desc limit 1;
      -- The days are set in the same update, so the rental-time trigger (52) has nothing to add
      update public.payments
      set amount_paid = v_paid,
          status = case when v_full then 'paid' else 'pending' end,
          credited_days = case when v_mc then p.credited_days else v_new_days end,
          month_credited = v_mc,
          paid_at = case when v_full then (select max(received_at) from public.payment_receipts where payment_id = p.id) else null end,
          method = coalesce(v_method, p.method)
      where id = p.id;
    end if;
  end loop;

  -- Rental time goes back by the days this payment gave
  if t.property_id is not null and t.lease_end is not null and v_back > 0 then
    v_end := t.lease_end - v_back;
    if not exists (select 1 from public.payment_receipts where tenant_id = t.id)
       and (t.lease_start is null or v_end <= t.lease_start) then
      v_end := null; -- it was their only payment: no paid time, as before it
    elsif t.lease_start is not null and v_end < t.lease_start then
      v_end := t.lease_start;
    end if;
    update public.tenants set lease_end = v_end where id = t.id;
  end if;

  -- The cash / mobile money record stays, marked reversed
  if c.id is not null then
    update public.cash_payments
    set status = 'reversed', reversed_at = now(), reversed_by = me, reversed_role = v_role
    where id = c.id;
  end if;

  select string_agg(to_char(to_date(x || '-01', 'YYYY-MM-DD'), 'FMMonth YYYY'), ', ' order by x)
  into v_months from unnest(v_periods) x;

  insert into public.notifications (landlord_id, tenant_id, type, title, body)
  values (r0.landlord_id, r0.tenant_id, 'payment', 'Payment reversed',
    format('Your payment of %s made on %s has been reversed by %s. It no longer pays the rent of %s.%s',
      public.ugx(v_total),
      v_day,
      case when v_role = 'superadmin' then 'Renta UG' else 'your landlord' end,
      v_months,
      case
        when t.property_id is null or t.lease_end is null or v_back = 0 then ''
        when v_end is null then ' You have no paid rental time now.'
        else format(' Your rent now runs to %s.', to_char(v_end, 'FMDD Mon YYYY'))
      end));

  -- The main admin did it: the landlord is told, and it is in the activity log
  if v_role = 'superadmin' then
    insert into public.staff_notifications (user_id, type, title, body, url)
    values (r0.landlord_id, 'payment', 'Payment reversed',
      format('Renta UG reversed a payment of %s from %s, made on %s.', public.ugx(v_total), t.full_name, v_day),
      '/landlord/payments');
    perform public.admin_log('reverse_payment', 'payment', r0.id, format('Reversed a payment of %s from %s', public.ugx(v_total), t.full_name));
  end if;

  return json_build_object(
    'reversed', v_total,
    'months', (select coalesce(json_agg(x order by x), '[]'::json) from unnest(v_periods) x),
    'removed_months', v_removed,
    'days_back', v_back,
    'paid_to', v_end,
    'cash_payment', c.id);
end $$;

revoke execute on function public.reverse_payment(uuid) from public, anon;
grant execute on function public.reverse_payment(uuid) to authenticated;

-- ── Confirming rent (as in 61). The tenant is told which debt days were paid and how many days were added ──
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
  v_given int := 0;
  v_added int := 0;
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
  -- the day they chose. The time of day is kept by tenants_rent_clock (61).
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
  -- Every day this payment gave runs on from the old end: the debt days first, then what is left is added
  if v_old_end is not null and v_new_end is not null then
    v_given := v_new_end - v_old_end;
    v_added := greatest(0, v_given - v_debt);
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
      case when v_debt > 0 and v_new_end is distinct from v_old_end then
        case when v_given >= v_debt then
          format(' Your %s debt day%s %s been paid for first, so %s.',
            v_debt, case when v_debt = 1 then '' else 's' end, case when v_debt = 1 then 'has' else 'have' end,
            case when v_added = 0 then 'no more days were added to your rental time'
                 else format('the remaining %s day%s %s added to your rental time',
                   v_added, case when v_added = 1 then '' else 's' end, case when v_added = 1 then 'was' else 'were' end) end)
        else format(' It paid %s of your %s debt days, so you are still %s day%s behind.',
          v_given, v_debt, v_debt - v_given, case when v_debt - v_given = 1 then '' else 's' end)
        end
      else '' end,
      case when v_new_end is not null and v_new_end is distinct from v_old_end
        then format(' Your rent now runs to %s.', to_char(v_new_end, 'FMDD Mon YYYY')) else '' end,
      case when v_ahead > 0 then format(' That includes %s month%s paid ahead.', v_ahead, case when v_ahead = 1 then '' else 's' end) else '' end,
      case when v_balance_after = 0 then 'You have no outstanding balance. Thank you.'
           else format('Outstanding balance: %s.', public.ugx(v_balance_after)) end));

  return json_build_object(
    'applied', v_amount, 'balance_after', v_balance_after, 'completed', array_to_json(v_completed),
    'months_ahead', v_ahead, 'debt_days', v_debt, 'days_given', v_given, 'days_added', v_added,
    'paid_to', v_new_end, 'days', v_days);
end $$;
