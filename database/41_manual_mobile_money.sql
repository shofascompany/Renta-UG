-- 41 · mobile money sent straight to the landlord + rent cycles + error reports + health checks
--
--  Mobile money (no payment company in between)
--   • Each landlord adds the numbers they receive money on (MTN, Airtel) with the
--     registered name the network shows: landlord_pay_accounts.
--   • Every tenant gets their own one-word payment reason (tenants.pay_code, e.g. JOHN427). They type
--     it as the "reason" when they send money, so the landlord can match the payment.
--   • The tenant sends the money with their phone, then taps "I've paid". That creates a payment
--     WAITING FOR THE LANDLORD (cash_payments, method = 'mobile_money'). The tenant is told it is
--     being reviewed. When the landlord confirms, it counts exactly like cash: unpaid rent first,
--     then months ahead, saved as "Mobile money".
--   • A landlord can also record mobile money for a tenant without a smartphone: it counts at once.
--
--  Rent cycles
--   • The landlord chooses the date of the FIRST payment: the tenant's first month starts that day.
--   • After that, each month runs on from the day the last one ended. Days after the end that are not
--     paid for are "debt days": they are taken from the next month (the next month still ends one
--     month after the old end), and the tenant is told so when the payment is confirmed.
--
--  Error reports + health checks (main admin)
--   • error_reports: errors from any page or the server, grouped (same error = one row + a count).
--   • health_checks: the server checks every part of the system every 20 minutes and keeps the result.
--
-- Safe to run more than once. No data is deleted.

-- ── Landlord receiving numbers ──
create table if not exists public.landlord_pay_accounts (
  id uuid primary key default gen_random_uuid(),
  landlord_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  network text not null,
  phone text not null,
  account_name text not null,
  dial_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (landlord_id, network)
);
alter table public.landlord_pay_accounts enable row level security;

-- Only MTN and Airtel (Lycamobile was removed; drops any Lyca number saved by an earlier version)
delete from public.landlord_pay_accounts where network not in ('mtn', 'airtel');
alter table public.landlord_pay_accounts drop constraint if exists landlord_pay_accounts_network_check;
alter table public.landlord_pay_accounts add constraint landlord_pay_accounts_network_check check (network in ('mtn', 'airtel'));

drop policy if exists "pay accounts landlord" on public.landlord_pay_accounts;
drop policy if exists "pay accounts tenant read" on public.landlord_pay_accounts;
drop policy if exists "pay accounts admin read" on public.landlord_pay_accounts;
create policy "pay accounts landlord" on public.landlord_pay_accounts for all to authenticated
  using (public.is_landlord() and landlord_id = auth.uid())
  with check (public.is_landlord() and landlord_id = auth.uid());
create policy "pay accounts tenant read" on public.landlord_pay_accounts for select to authenticated
  using (landlord_id = public.my_landlord_id());
create policy "pay accounts admin read" on public.landlord_pay_accounts for select to authenticated
  using (public.is_superadmin());

revoke all on public.landlord_pay_accounts from anon;
grant select, insert, update, delete on public.landlord_pay_accounts to authenticated;
grant all on public.landlord_pay_accounts to service_role;

do $$ begin
  alter publication supabase_realtime add table public.landlord_pay_accounts;
exception when duplicate_object then null; end $$;

-- ── One payment word per tenant ──
alter table public.tenants add column if not exists pay_code text;
create unique index if not exists tenants_pay_code_key on public.tenants (pay_code) where pay_code is not null;

create or replace function public.new_pay_code(p_name text) returns text
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_base text := upper(left(regexp_replace(split_part(trim(coalesce(p_name, '')), ' ', 1), '[^A-Za-z]', '', 'g'), 6));
  v_code text;
begin
  if length(v_base) < 2 then v_base := 'RENT'; end if;
  loop
    v_code := v_base || (100 + floor(random() * 900))::int;
    exit when not exists (select 1 from public.tenants where pay_code = v_code);
  end loop;
  return v_code;
end $$;
revoke execute on function public.new_pay_code(text) from public, anon, authenticated;

create or replace function public.set_tenant_pay_code() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.pay_code is null then new.pay_code := public.new_pay_code(new.full_name); end if;
  return new;
end $$;
drop trigger if exists tenants_pay_code on public.tenants;
create trigger tenants_pay_code before insert on public.tenants
  for each row execute function public.set_tenant_pay_code();

-- Existing tenants: one at a time, so every word stays unique
do $$
declare r record;
begin
  for r in select id, full_name from public.tenants where pay_code is null loop
    update public.tenants set pay_code = public.new_pay_code(r.full_name) where id = r.id;
  end loop;
end $$;

-- ── Payments waiting for the landlord: cash OR mobile money ──
alter table public.cash_payments add column if not exists method text not null default 'cash';
alter table public.cash_payments add column if not exists network text;
do $$ begin
  alter table public.cash_payments add constraint cash_payments_method_check check (method in ('cash', 'mobile_money'));
exception when duplicate_object then null; end $$;

-- ── Rental time: the first month starts on the date the landlord chose ──
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
  -- New tenant: from their start date (chosen by the landlord). Otherwise straight on from the old end,
  -- so late (debt) days are not given back.
  update public.tenants
  set lease_start = coalesce(lease_start, v_day),
      lease_end = (coalesce(lease_end, lease_start, v_day) + interval '1 month')::date
  where id = new.tenant_id and property_id is not null;
  return new;
end $$;

-- ── Report / record a payment (cash or mobile money) ──
-- Tenant: reports it → their landlord confirms. Landlord: records it → it counts straight away.
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
  values (v_tenant.id, v_tenant.landlord_id, p_amount, v_paid_on, nullif(trim(p_note), ''), me, v_role, v_method, v_network)
  returning id into v_id;

  if v_role = 'tenant' then
    if v_method = 'mobile_money' then
      insert into public.staff_notifications (user_id, type, title, body, url)
      values (v_tenant.landlord_id, 'cash', 'Mobile money to confirm',
        format('%s says they sent you %s on %s with the reason %s%s. Check your phone, then confirm it.',
          v_tenant.full_name, public.ugx(p_amount), coalesce(v_net_label, 'mobile money'), coalesce(v_tenant.pay_code, '—'),
          coalesce(' (' || v_house || ')', '')),
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

-- Older app versions call this name: cash only
create or replace function public.submit_cash_payment(
  p_tenant_id uuid,
  p_amount bigint,
  p_paid_on date default null,
  p_note text default null
) returns uuid
language sql volatile security definer set search_path = '' as $$
  select public.submit_payment(p_tenant_id, p_amount, p_paid_on, p_note, 'cash', null);
$$;

-- ── Confirm: unpaid rent first, then months ahead. Tells the tenant about debt days. ──
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

  -- First payment: the tenant's first month starts on the day it was paid (chosen by the landlord)
  v_old_end := v_tenant.lease_end;
  if v_old_end is null and v_tenant.property_id is not null then
    update public.tenants set lease_start = c.paid_on where id = c.tenant_id;
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
  if v_old_end is not null and c.paid_on > v_old_end then
    v_debt := c.paid_on - v_old_end;
  end if;
  if v_new_end is not null then
    v_days := v_new_end - greatest(c.paid_on, coalesce(v_old_end, c.paid_on));
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

-- ── Reject ──
create or replace function public.reject_cash_payment(p_id uuid, p_reason text default null) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  c public.cash_payments;
  v_reviewer text;
  v_reason text := nullif(trim(p_reason), '');
begin
  select * into c from public.cash_payments where id = p_id for update;
  if not found then raise exception 'Payment not found.'; end if;
  if c.status <> 'pending' then raise exception 'This payment has already been %.', c.status; end if;
  v_reviewer := public.can_review_cash(c);

  update public.cash_payments
  set status = 'rejected', reject_reason = v_reason, reviewed_by = me, reviewed_role = v_reviewer, reviewed_at = now()
  where id = c.id;

  insert into public.notifications (landlord_id, tenant_id, type, title, body)
  values (c.landlord_id, c.tenant_id, 'payment', 'Payment not confirmed',
    format('Your %s payment of %s from %s could not be confirmed by your landlord%s. Please contact them.',
      case when c.method = 'mobile_money' then 'mobile money' else 'cash' end,
      public.ugx(c.amount), to_char(c.paid_on, 'FMDD Mon YYYY'), coalesce(': ' || v_reason, '')));
end $$;

revoke execute on function public.submit_payment(uuid, bigint, date, text, text, text) from public, anon;
revoke execute on function public.submit_cash_payment(uuid, bigint, date, text) from public, anon;
revoke execute on function public.confirm_cash_payment(uuid, bigint) from public, anon;
revoke execute on function public.reject_cash_payment(uuid, text) from public, anon;
grant execute on function public.submit_payment(uuid, bigint, date, text, text, text) to authenticated;
grant execute on function public.submit_cash_payment(uuid, bigint, date, text) to authenticated;
grant execute on function public.confirm_cash_payment(uuid, bigint) to authenticated;
grant execute on function public.reject_cash_payment(uuid, text) to authenticated;

-- ── Overdue reminder: same timing as 31 (once, then every 3 days, 08:00–20:00), wording about debt days ──
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
             p.name, to_char(t.lease_end, 'FMDD Mon YYYY'), today - t.lease_end,
             case when today - t.lease_end = 1 then '' else 's' end, to_char(t.lease_end, 'FMDD Mon')) end
  from public.tenants t
  join public.properties p on p.id = t.property_id
  cross join lateral (
    select coalesce(sum(amount - amount_paid), 0) as amount, min(due_date) as since
    from public.payments where tenant_id = t.id and status = 'pending' and due_date < today
  ) o
  where t.property_id is not null
    and t.user_id is not null
    and (o.amount > 0 or (t.lease_end is not null and t.lease_end < today))
    and not exists (
      select 1 from public.notifications x
      where x.tenant_id = t.id and x.type = 'rent_due' and x.created_at > now() - interval '71 hours'
    );
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.send_overdue_reminders() from public, anon, authenticated;

-- ── Error reports (any page, the server, the health checks) ──
create table if not exists public.error_reports (
  id uuid primary key default gen_random_uuid(),
  source text not null default 'app' check (source in ('app', 'server', 'health')),
  area text,
  message text not null,
  detail text,
  url text,
  user_id uuid,
  user_role text,
  user_agent text,
  fingerprint text not null,
  count int not null default 1,
  status text not null default 'open' check (status in ('open', 'fixed', 'ignored')),
  auto_fixed boolean not null default false,
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now()
);
create index if not exists error_reports_last_seen_idx on public.error_reports (last_seen desc);
create unique index if not exists error_reports_open_key on public.error_reports (fingerprint) where status = 'open';
alter table public.error_reports enable row level security;

drop policy if exists "errors admin read" on public.error_reports;
drop policy if exists "errors admin update" on public.error_reports;
drop policy if exists "errors admin delete" on public.error_reports;
create policy "errors admin read" on public.error_reports for select to authenticated using (public.is_superadmin());
create policy "errors admin update" on public.error_reports for update to authenticated using (public.is_superadmin()) with check (public.is_superadmin());
create policy "errors admin delete" on public.error_reports for delete to authenticated using (public.is_superadmin());
revoke all on public.error_reports from anon, authenticated;
grant select, update, delete on public.error_reports to authenticated;
grant all on public.error_reports to service_role;

do $$ begin
  alter publication supabase_realtime add table public.error_reports;
exception when duplicate_object then null; end $$;

-- Anyone (even signed out) can report an error; the same error is counted, not repeated.
-- The main admin is told the first time a new error appears.
create or replace function public.report_error(
  p_source text, p_area text, p_message text, p_detail text default null, p_url text default null,
  p_user_agent text default null, p_auto_fixed boolean default false
) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_source text := case when p_source in ('app', 'server', 'health') then p_source else 'app' end;
  v_message text := left(coalesce(nullif(trim(p_message), ''), 'Unknown error'), 500);
  v_area text := left(nullif(trim(p_area), ''), 120);
  v_fp text;
  v_role text;
  v_new boolean := false;
begin
  -- Same error = same message in the same area (numbers and ids removed, so they group together)
  v_fp := md5(v_source || '|' || coalesce(v_area, '') || '|' ||
    regexp_replace(v_message, '[0-9a-f]{8}-[0-9a-f-]{27,}|\d+', '#', 'g'));
  select role into v_role from public.profiles where id = auth.uid();

  update public.error_reports
  set count = count + 1, last_seen = now(), detail = coalesce(left(p_detail, 4000), detail),
      url = coalesce(left(p_url, 300), url), auto_fixed = auto_fixed or coalesce(p_auto_fixed, false)
  where fingerprint = v_fp and status = 'open';

  if not found then
    -- Don't let a flood of different errors fill the table
    if (select count(*) from public.error_reports where first_seen > now() - interval '1 hour') >= 200 then return; end if;
    insert into public.error_reports (source, area, message, detail, url, user_id, user_role, user_agent, fingerprint, auto_fixed)
    values (v_source, v_area, v_message, left(p_detail, 4000), left(p_url, 300), auth.uid(), v_role, left(p_user_agent, 300), v_fp, coalesce(p_auto_fixed, false))
    on conflict do nothing;
    v_new := found;
  end if;

  if v_new and not coalesce(p_auto_fixed, false)
     and (select count(*) from public.staff_notifications where type = 'error' and created_at > now() - interval '1 hour') < 20 then
    insert into public.staff_notifications (user_id, type, title, body, url)
    select id, 'error',
      case v_source when 'health' then 'System check found a problem' when 'server' then 'Server error' else 'Error in the app' end,
      left(coalesce(v_area || ': ', '') || v_message, 300), '/admin2026/system'
    from public.profiles where role = 'superadmin';
  end if;
end $$;
revoke execute on function public.report_error(text, text, text, text, text, text, boolean) from public;
grant execute on function public.report_error(text, text, text, text, text, text, boolean) to anon, authenticated, service_role;

-- ── Health checks (written by the server every 20 minutes) ──
create table if not exists public.health_checks (
  id uuid primary key default gen_random_uuid(),
  run_at timestamptz not null default now(),
  ok boolean not null,
  results jsonb not null default '[]',
  trigger text not null default 'schedule'
);
create index if not exists health_checks_run_at_idx on public.health_checks (run_at desc);
alter table public.health_checks enable row level security;
drop policy if exists "health admin read" on public.health_checks;
create policy "health admin read" on public.health_checks for select to authenticated using (public.is_superadmin());
revoke all on public.health_checks from anon, authenticated;
grant select on public.health_checks to authenticated;
grant all on public.health_checks to service_role;

do $$ begin
  alter publication supabase_realtime add table public.health_checks;
exception when duplicate_object then null; end $$;
