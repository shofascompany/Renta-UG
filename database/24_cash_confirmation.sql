-- 24 · cash payments with confirmation + tenants managed by their landlord
--
--  Tenants without a smartphone
--   • tenants.managed_by_landlord: the landlord registered this tenant and manages them (no app account).
--     Shown only to the tenant's landlord and the main admin. Notices, charges and payments are still
--     recorded for them as usual.
--
--  Cash payments ("I paid my landlord in cash")
--   • Anyone can REPORT cash: the tenant in the app, or the landlord for any of their tenants.
--   • It waits in cash_payments as 'pending' until it is CONFIRMED (amount can be corrected) or REJECTED:
--       reported by the tenant   → confirmed by their landlord OR the main admin
--       recorded by the landlord → confirmed by the main admin (nobody confirms their own entry)
--   • On confirmation the amount is credited to the tenant's oldest unpaid rent first, a receipt is
--     kept, and the tenant is notified. Landlord and main admin get a note in their inbox.
--   • Landlords can no longer credit cash directly (record_cash_payment is switched off for the app).
-- Safe to run more than once. No data is deleted.

-- ── Tenants managed by the landlord ──
alter table public.tenants add column if not exists managed_by_landlord boolean not null default false;

-- ── Cash payments queue ──
create table if not exists public.cash_payments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  landlord_id uuid not null references auth.users (id) on delete cascade,
  amount bigint not null check (amount > 0),              -- amount reported
  paid_on date not null,                                  -- day the cash was handed over
  note text,
  submitted_by uuid references auth.users (id) on delete set null,
  submitted_role text not null check (submitted_role in ('tenant', 'landlord')),
  status text not null default 'pending' check (status in ('pending', 'confirmed', 'rejected')),
  confirmed_amount bigint,                                -- amount actually credited
  reviewed_by uuid references auth.users (id) on delete set null,
  reviewed_role text check (reviewed_role in ('landlord', 'superadmin')),
  reviewed_at timestamptz,
  reject_reason text,
  created_at timestamptz not null default now()
);
create index if not exists cash_payments_tenant_id_idx on public.cash_payments (tenant_id);
create index if not exists cash_payments_landlord_id_idx on public.cash_payments (landlord_id);
create index if not exists cash_payments_pending_idx on public.cash_payments (status) where status = 'pending';
alter table public.cash_payments enable row level security;

drop policy if exists "cash tenant read" on public.cash_payments;
drop policy if exists "cash landlord read" on public.cash_payments;
drop policy if exists "cash superadmin read" on public.cash_payments;
create policy "cash tenant read" on public.cash_payments for select to authenticated using (tenant_id = public.my_tenant_id());
create policy "cash landlord read" on public.cash_payments for select to authenticated
  using (public.is_landlord() and landlord_id = auth.uid());
create policy "cash superadmin read" on public.cash_payments for select to authenticated using (public.is_superadmin());

-- Read only for signed-in users; every change goes through the functions below
revoke all on public.cash_payments from anon, authenticated;
grant select on public.cash_payments to authenticated;
grant all on public.cash_payments to service_role;

do $$ begin
  alter publication supabase_realtime add table public.cash_payments;
exception when duplicate_object then null; end $$;

-- ── Helpers ──
create or replace function public.tenant_outstanding(p_tenant_id uuid) returns bigint
language sql stable security definer set search_path = '' as $$
  select coalesce(sum(amount - amount_paid), 0) from public.payments where tenant_id = p_tenant_id and status = 'pending';
$$;
revoke execute on function public.tenant_outstanding(uuid) from public, anon, authenticated;

-- Inbox note for every main admin
create or replace function public.notify_admins(p_type text, p_title text, p_body text) returns void
language sql volatile security definer set search_path = '' as $$
  insert into public.staff_notifications (user_id, type, title, body, url)
  select id, p_type, p_title, p_body, '/admin2026/cash' from public.profiles where role = 'superadmin';
$$;
revoke execute on function public.notify_admins(text, text, text) from public, anon, authenticated;

-- ── Report / record cash ──
-- Tenant: p_tenant_id may be null (their own record is used). Landlord: one of their tenants.
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

  v_outstanding := public.tenant_outstanding(v_tenant.id);
  select coalesce(sum(amount), 0) into v_pending from public.cash_payments where tenant_id = v_tenant.id and status = 'pending';
  if v_outstanding = 0 then
    raise exception 'There is no unpaid rent to pay. Ask the landlord to create a rent charge first.';
  end if;
  if p_amount + v_pending > v_outstanding then
    raise exception '%', format('That is more than the unpaid rent of %s%s.',
      public.ugx(v_outstanding),
      case when v_pending > 0 then format(' (%s is already waiting for confirmation)', public.ugx(v_pending)) else '' end);
  end if;

  insert into public.cash_payments (tenant_id, landlord_id, amount, paid_on, note, submitted_by, submitted_role)
  values (v_tenant.id, v_tenant.landlord_id, p_amount, v_paid_on, nullif(trim(p_note), ''), me, v_role)
  returning id into v_id;

  select name into v_house from public.properties where id = v_tenant.property_id;
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

-- ── Who may review a cash entry ──
create or replace function public.can_review_cash(c public.cash_payments) returns text
language plpgsql stable security definer set search_path = '' as $$
begin
  if public.is_superadmin() then return 'superadmin'; end if;
  if public.is_landlord() and c.landlord_id = auth.uid() then
    if c.submitted_role = 'landlord' then
      raise exception 'Cash you recorded is confirmed by Renta UG (the main admin).';
    end if;
    return 'landlord';
  end if;
  raise exception 'You cannot review this payment.';
end $$;
revoke execute on function public.can_review_cash(public.cash_payments) from public, anon, authenticated;

-- ── Confirm: credit the (possibly corrected) amount to the tenant, oldest rent first ──
create or replace function public.confirm_cash_payment(p_id uuid, p_amount bigint default null) returns json
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  c public.cash_payments;
  v_reviewer text;
  v_amount bigint;
  v_outstanding bigint;
  v_left bigint;
  v_take bigint;
  v_completed text[] := '{}';
  v_balance_after bigint;
  v_tenant record;
  v_house text;
  v_landlord_name text;
  r record;
begin
  select * into c from public.cash_payments where id = p_id for update;
  if not found then raise exception 'Payment not found.'; end if;
  if c.status <> 'pending' then raise exception 'This payment has already been %.', c.status; end if;
  v_reviewer := public.can_review_cash(c);

  v_amount := coalesce(p_amount, c.amount);
  if v_amount <= 0 then raise exception 'Enter an amount greater than zero.'; end if;
  v_outstanding := public.tenant_outstanding(c.tenant_id);
  if v_amount > v_outstanding then
    raise exception 'That is more than the unpaid rent of %.', public.ugx(v_outstanding);
  end if;

  v_left := v_amount;
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

  update public.cash_payments
  set status = 'confirmed', confirmed_amount = v_amount, reviewed_by = me, reviewed_role = v_reviewer, reviewed_at = now()
  where id = c.id;

  v_balance_after := public.tenant_outstanding(c.tenant_id);
  select * into v_tenant from public.tenants where id = c.tenant_id;
  select name into v_house from public.properties where id = coalesce(v_tenant.property_id, v_tenant.last_property_id);
  select nullif(full_name, '') into v_landlord_name from public.profiles where id = c.landlord_id;

  -- Tenant
  insert into public.notifications (landlord_id, tenant_id, type, title, body)
  values (c.landlord_id, c.tenant_id, 'payment', 'Payment confirmation',
    format('Your cash payment of %s made on %s has been confirmed by %s%s.%s %s',
      public.ugx(v_amount),
      to_char(c.paid_on, 'FMDD Mon YYYY'),
      case when v_reviewer = 'superadmin' then 'Renta UG' else 'your landlord' end,
      case when v_amount <> c.amount then format(' (you reported %s)', public.ugx(c.amount)) else '' end,
      case when array_length(v_completed, 1) > 0
        then format(' Rent for %s is now paid in full.', array_to_string(v_completed, ', ')) else '' end,
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

  return json_build_object('applied', v_amount, 'balance_after', v_balance_after, 'completed', array_to_json(v_completed));
end $$;

-- ── Reject ──
create or replace function public.reject_cash_payment(p_id uuid, p_reason text default null) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  c public.cash_payments;
  v_reviewer text;
  v_reason text := nullif(trim(p_reason), '');
  v_tenant_name text;
begin
  select * into c from public.cash_payments where id = p_id for update;
  if not found then raise exception 'Payment not found.'; end if;
  if c.status <> 'pending' then raise exception 'This payment has already been %.', c.status; end if;
  v_reviewer := public.can_review_cash(c);

  update public.cash_payments
  set status = 'rejected', reject_reason = v_reason, reviewed_by = me, reviewed_role = v_reviewer, reviewed_at = now()
  where id = c.id;

  insert into public.notifications (landlord_id, tenant_id, type, title, body)
  values (c.landlord_id, c.tenant_id, 'payment', 'Cash payment not confirmed',
    format('The cash payment of %s recorded for %s could not be confirmed%s. Please contact your landlord.',
      public.ugx(c.amount), to_char(c.paid_on, 'FMDD Mon YYYY'), coalesce(': ' || v_reason, '')));

  if v_reviewer = 'superadmin' and c.submitted_role = 'landlord' then
    select full_name into v_tenant_name from public.tenants where id = c.tenant_id;
    insert into public.staff_notifications (user_id, type, title, body, url)
    values (c.landlord_id, 'cash', 'Cash payment not confirmed',
      format('Renta UG did not confirm the %s cash you recorded from %s%s.',
        public.ugx(c.amount), v_tenant_name, coalesce(': ' || v_reason, '')),
      '/landlord/payments');
  end if;
end $$;

revoke execute on function public.submit_cash_payment(uuid, bigint, date, text) from public, anon;
revoke execute on function public.confirm_cash_payment(uuid, bigint) from public, anon;
revoke execute on function public.reject_cash_payment(uuid, text) from public, anon;
grant execute on function public.submit_cash_payment(uuid, bigint, date, text) to authenticated;
grant execute on function public.confirm_cash_payment(uuid, bigint) to authenticated;
grant execute on function public.reject_cash_payment(uuid, text) to authenticated;

-- Cash now always goes through confirmation
do $$ begin
  revoke execute on function public.record_cash_payment(uuid, bigint, timestamptz, text) from authenticated;
exception when undefined_function then null; end $$;
