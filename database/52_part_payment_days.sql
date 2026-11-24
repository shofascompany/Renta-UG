-- 52 · part payments buy DAYS (safe to run again; no data is deleted)
--
--  A tenant can pay any part of a month's rent. The money buys rental time in proportion:
--    days = amount paid on that month ÷ the month's rent × 30   (rounded down)
--  e.g. half the rent → 15 days. Paying the rest later ("Complete payment") tops the same month up:
--  once the month is paid in full it counts as one whole rent month. A rent month is ALWAYS 30 days
--  (not 28, 29 or 31). The days already given are part of it, never counted twice.
--  Replaces the old rule (a whole month as soon as 60% was paid). Months that already got their whole
--  month under the old rule keep it (month_credited = true), so nobody loses time.
--
--  payments.credited_days   days of rental time this rent month has given so far (part payments)
--  payments.month_credited  true once the month has given its whole month

-- New columns; the months that already counted (paid, or 60%+ under the old rule) are marked ONCE,
-- only when the columns are first added.
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'payments' and column_name = 'month_credited'
  ) then
    alter table public.payments add column credited_days int not null default 0;
    alter table public.payments add column month_credited boolean not null default false;
    update public.payments
    set month_credited = true
    where amount > 0 and (status = 'paid' or amount_paid * 10 >= amount * 6);
  end if;
end $$;
alter table public.payments add column if not exists credited_days int not null default 0;

-- Rental time grows as money comes in (runs BEFORE the row is saved, so it can record what it gave)
create or replace function public.extend_rental_time() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_day date := (coalesce(new.paid_at, now()) at time zone 'Africa/Kampala')::date;
  v_days int;
  v_add interval;
begin
  if new.amount is null or new.amount <= 0 or new.month_credited then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.amount_paid <= coalesce(old.amount_paid, 0) and new.status is not distinct from old.status then
    return new;
  end if;

  if new.status = 'paid' or new.amount_paid >= new.amount then
    -- Paid in full: one rent month = 30 days (never 28 or 31), less the days already given for it
    v_add := make_interval(days => 30 - coalesce(new.credited_days, 0));
    new.month_credited := true;
  else
    v_days := floor(new.amount_paid::numeric * 30 / new.amount)::int;
    if v_days <= coalesce(new.credited_days, 0) then
      return new;
    end if;
    v_add := make_interval(days => v_days - coalesce(new.credited_days, 0));
    new.credited_days := v_days;
  end if;

  -- New tenant: from their start date (the confirmation sets it to the day paid). Otherwise straight on
  -- from the old end, so late (debt) days are not given back.
  update public.tenants
  set lease_start = coalesce(lease_start, v_day),
      lease_end = (coalesce(lease_end, lease_start, v_day) + v_add)::date
  where id = new.tenant_id and property_id is not null;
  return new;
end $$;

drop trigger if exists payments_extend_rental_time on public.payments;
create trigger payments_extend_rental_time
  before insert or update of status, amount_paid on public.payments
  for each row execute function public.extend_rental_time();
