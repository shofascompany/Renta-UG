-- 36 · part payments: a month starts counting once at least 60% of its rent is paid
--
--  • A tenant can pay part of what they owe (not less than 60%). The rest stays as their balance due.
--  • Rental time grows by one month the moment a month's rent reaches 60% paid (or is fully paid in
--    one go). Paying the remaining 40% later does not add another month.
--  • A new tenant starts with no rental time; it starts on the day of their first qualifying payment.
--
-- Safe to run more than once. No data is deleted.

create or replace function public.extend_rental_time() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_day date := (coalesce(new.paid_at, now()) at time zone 'Africa/Kampala')::date;
  v_now_ok boolean;
  v_was_ok boolean := false;
begin
  v_now_ok := new.status = 'paid' or (new.amount > 0 and new.amount_paid * 10 >= new.amount * 6);
  if tg_op = 'UPDATE' then
    v_was_ok := old.status = 'paid' or (old.amount > 0 and old.amount_paid * 10 >= old.amount * 6);
  end if;
  if not v_now_ok or v_was_ok then
    return new;
  end if;
  update public.tenants
  set lease_start = coalesce(lease_start, v_day),
      lease_end = (coalesce(lease_end, v_day) + interval '1 month')::date
  where id = new.tenant_id and property_id is not null;
  return new;
end $$;

drop trigger if exists payments_extend_rental_time on public.payments;
create trigger payments_extend_rental_time
  after insert or update of status, amount_paid on public.payments
  for each row execute function public.extend_rental_time();

-- One-time catch-up: tenants with no rental time yet who already have a month at 60%+ paid
update public.tenants t
set lease_start = s.start_day,
    lease_end = (s.start_day + make_interval(months => s.months))::date
from (
  select p.tenant_id,
         min((coalesce(p.paid_at, p.created_at) at time zone 'Africa/Kampala')::date) as start_day,
         count(*)::int as months
  from public.payments p
  where p.amount > 0 and (p.status = 'paid' or p.amount_paid * 10 >= p.amount * 6)
  group by p.tenant_id
) s
where t.id = s.tenant_id and t.property_id is not null and t.lease_end is null;
