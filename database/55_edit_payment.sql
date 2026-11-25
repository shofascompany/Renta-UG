-- 55 · edit a payment of a tenant without a smartphone (safe to run again; no data is deleted)
--
--  A landlord who runs a tenant's account (managed_by_landlord) can correct a payment they recorded:
--  the amount, the date it was received, the method and the note. Everything that follows from it is
--  recalculated here, in the database, so every page and receipt agrees:
--   • the rent month's amount_paid / status / paid_at
--   • the rental time that month gave (part payments give days, a full month gives 30 days: see 52)
--     → the tenant's lease_end moves by the difference
--   • if it was the tenant's FIRST payment and the date changes, their rental period moves with it
--  Browsers still cannot write payments directly (54); only this function can.

create or replace function public.edit_receipt(
  p_receipt_id uuid,
  p_amount bigint,
  p_received_at timestamptz,
  p_method text,
  p_note text default null
) returns json
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_landlord uuid := auth.uid();
  r public.payment_receipts%rowtype;
  p public.payments%rowtype;
  t public.tenants%rowtype;
  v_method text := nullif(trim(p_method), '');
  v_note text := nullif(trim(p_note), '');
  v_paid bigint;
  v_full boolean;
  v_mc boolean;
  v_old_days int;
  v_new_days int;
  v_old_day date;
  v_new_day date;
  v_first boolean;
begin
  if not public.is_landlord() then
    raise exception 'Only landlords can edit payments.';
  end if;

  select * into r from public.payment_receipts where id = p_receipt_id for update;
  if not found or r.landlord_id <> v_landlord then
    raise exception 'Payment not found.';
  end if;
  select * into t from public.tenants where id = r.tenant_id for update;
  if not found or t.managed_by_landlord is not true then
    raise exception 'Only payments of tenants without a smartphone can be edited.';
  end if;
  -- Once the tenant has set up their own account, their payments are no longer the landlord's to rewrite
  if t.user_id is not null and exists (select 1 from public.profiles where id = t.user_id and not must_change_password) then
    raise exception 'This tenant uses the app now, so their payments can no longer be edited.';
  end if;
  select * into p from public.payments where id = r.payment_id for update;
  if not found then
    raise exception 'Rent month not found.';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Enter an amount greater than zero.';
  end if;
  if p_received_at is null or (p_received_at at time zone 'Africa/Kampala')::date > public.kampala_today() then
    raise exception 'The payment date cannot be in the future.';
  end if;
  if v_method is null then v_method := r.method; end if;
  if char_length(v_method) > 40 then
    raise exception 'The method is too long.';
  end if;
  if v_note is not null and char_length(v_note) > 300 then
    raise exception 'The note is too long (300 characters at most).';
  end if;

  -- What the month has been paid after the change must stay within its rent
  v_paid := p.amount_paid - r.amount + p_amount;
  if v_paid > p.amount then
    raise exception 'That is more than the rent for this month. The most you can enter is UGX %.',
      to_char(p.amount - (p.amount_paid - r.amount), 'FM999,999,999,999');
  end if;

  -- Rental time this month gave before, and what it should give now
  v_old_days := case when p.month_credited then 30 else coalesce(p.credited_days, 0) end;
  v_full := v_paid >= p.amount;
  if v_full then
    v_new_days := 30; v_mc := true;
  elsif p.month_credited and p.amount > 0 and p.amount_paid < p.amount and v_paid * 10 >= p.amount * 6 then
    -- Counted under the old 60% rule and never paid in full: it keeps its whole month.
    -- (A month that WAS paid in full follows today's rule when its payment is reduced.)
    v_new_days := 30; v_mc := true;
  elsif p.amount > 0 then
    v_new_days := floor(v_paid::numeric * 30 / p.amount)::int; v_mc := false;
  else
    v_new_days := v_old_days; v_mc := p.month_credited;
  end if;

  v_old_day := (r.received_at at time zone 'Africa/Kampala')::date;
  v_new_day := (p_received_at at time zone 'Africa/Kampala')::date;
  v_first := not exists (
    select 1 from public.payment_receipts
    where tenant_id = r.tenant_id and id <> r.id and received_at < r.received_at
  );

  -- A cash payment record that matches this receipt exactly is kept in step (amount and date)
  if (select count(*) from public.cash_payments
      where tenant_id = r.tenant_id and status = 'confirmed' and paid_on = v_old_day
        and coalesce(confirmed_amount, amount) = r.amount) = 1 then
    update public.cash_payments
    set amount = p_amount, confirmed_amount = p_amount, paid_on = v_new_day
    where tenant_id = r.tenant_id and status = 'confirmed' and paid_on = v_old_day
      and coalesce(confirmed_amount, amount) = r.amount;
  end if;

  update public.payment_receipts
  set amount = p_amount, received_at = p_received_at, method = v_method, note = v_note
  where id = r.id;

  -- Credited days are set in the same update, so the rental-time trigger (52) has nothing left to add
  update public.payments
  set amount_paid = v_paid,
      status = case when v_full then 'paid' else 'pending' end,
      credited_days = case when v_mc then p.credited_days else v_new_days end,
      month_credited = v_mc,
      paid_at = case when v_full then (select max(received_at) from public.payment_receipts where payment_id = p.id) else null end,
      method = (select method from public.payment_receipts where payment_id = p.id order by received_at desc, created_at desc limit 1)
  where id = p.id;

  -- Rental time follows: the difference in days, and the start moves with a corrected first payment date
  if t.property_id is not null and t.lease_end is not null then
    update public.tenants
    set lease_end = (lease_end + (v_new_days - v_old_days) + case when v_first and lease_start = v_old_day then v_new_day - v_old_day else 0 end)::date,
        lease_start = case when v_first and lease_start = v_old_day then v_new_day else lease_start end
    where id = t.id;
    -- never end before it started
    update public.tenants set lease_end = lease_start where id = t.id and lease_start is not null and lease_end < lease_start;
  end if;

  return json_build_object(
    'ok', true,
    'days_before', v_old_days,
    'days_after', v_new_days,
    'amount_paid', v_paid,
    'paid_in_full', v_full
  );
end $$;

revoke execute on function public.edit_receipt(uuid, bigint, timestamptz, text, text) from public, anon;
grant execute on function public.edit_receipt(uuid, bigint, timestamptz, text, text) to authenticated;
