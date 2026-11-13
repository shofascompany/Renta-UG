-- 17 · cash payments, receipts and staff inbox
--   • payments can be paid in parts: amount_paid tracks how much of each rent charge is paid
--   • payment_receipts: every amount received (cash or mobile money), kept for the records
--   • record_cash_payment(): landlord records cash; it's applied to the oldest unpaid rent first.
--     The tenant gets a confirmation only when a month's rent is fully paid
--   • staff_notifications: inbox for landlords and the main admin (e.g. "payment received")
-- Safe to run more than once. No data is deleted.

-- ── Part payments ──
alter table public.payments add column if not exists amount_paid bigint not null default 0;
update public.payments set amount_paid = amount where status = 'paid' and amount_paid = 0;

-- ── Receipts ──
create table if not exists public.payment_receipts (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.payments (id) on delete cascade,
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  landlord_id uuid not null references auth.users (id) on delete cascade,
  amount bigint not null check (amount > 0),
  method text not null,             -- Cash, MTN Mobile Money, Airtel Money, Bank transfer
  reference text,
  note text,
  received_at timestamptz not null default now(),
  recorded_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists payment_receipts_payment_id_idx on public.payment_receipts (payment_id);
create index if not exists payment_receipts_landlord_id_idx on public.payment_receipts (landlord_id);
alter table public.payment_receipts enable row level security;

drop policy if exists "receipts landlord read" on public.payment_receipts;
drop policy if exists "receipts tenant read" on public.payment_receipts;
drop policy if exists "receipts superadmin read" on public.payment_receipts;
create policy "receipts landlord read" on public.payment_receipts for select to authenticated
  using (public.is_landlord() and landlord_id = auth.uid());
create policy "receipts tenant read" on public.payment_receipts for select to authenticated
  using (tenant_id = public.my_tenant_id());
create policy "receipts superadmin read" on public.payment_receipts for select to authenticated
  using (public.is_superadmin());

-- ── Staff inbox (landlords + main admin) ──
create table if not exists public.staff_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  type text not null default 'payment',
  title text not null,
  body text not null,
  url text,
  read boolean not null default false,
  pushed_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists staff_notifications_user_id_idx on public.staff_notifications (user_id);
alter table public.staff_notifications enable row level security;

drop policy if exists "staff inbox read own" on public.staff_notifications;
drop policy if exists "staff inbox mark read" on public.staff_notifications;
create policy "staff inbox read own" on public.staff_notifications for select to authenticated using (user_id = auth.uid());
create policy "staff inbox mark read" on public.staff_notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Table access: read only for signed-in users (writes go through the functions / the server)
revoke all on public.payment_receipts, public.staff_notifications from anon, authenticated;
grant select on public.payment_receipts, public.staff_notifications to authenticated;
grant update (read) on public.staff_notifications to authenticated;
grant all on public.payment_receipts, public.staff_notifications to service_role;

do $$ begin
  alter publication supabase_realtime add table public.staff_notifications;
exception when duplicate_object then null; end $$;

-- ── Record a cash payment ──
-- Applies the amount to the tenant's unpaid rent, oldest first. Returns what happened.
create or replace function public.record_cash_payment(
  p_tenant_id uuid,
  p_amount bigint,
  p_received_at timestamptz default now(),
  p_note text default null
) returns json
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_landlord uuid := auth.uid();
  v_outstanding bigint;
  v_left bigint := p_amount;
  v_take bigint;
  v_completed text[] := '{}';
  v_parts json[] := '{}';
  v_balance_after bigint;
  v_house text;
  c record;
begin
  if not public.is_landlord() then
    raise exception 'Only landlords can record payments.';
  end if;
  if not exists (select 1 from public.tenants where id = p_tenant_id and landlord_id = v_landlord) then
    raise exception 'Tenant not found.';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Enter an amount greater than zero.';
  end if;

  select coalesce(sum(amount - amount_paid), 0) into v_outstanding
  from public.payments where tenant_id = p_tenant_id and status = 'pending';

  if v_outstanding = 0 then
    raise exception 'This tenant has no unpaid rent. Create a rent charge first.';
  end if;
  if p_amount > v_outstanding then
    raise exception 'That is more than the balance of UGX %.', to_char(v_outstanding, 'FM999,999,999,999');
  end if;

  for c in
    select * from public.payments
    where tenant_id = p_tenant_id and status = 'pending'
    order by due_date, period
    for update
  loop
    exit when v_left <= 0;
    v_take := least(v_left, c.amount - c.amount_paid);
    v_left := v_left - v_take;

    insert into public.payment_receipts (payment_id, tenant_id, landlord_id, amount, method, note, received_at, recorded_by)
    values (c.id, p_tenant_id, v_landlord, v_take, 'Cash', nullif(trim(p_note), ''), coalesce(p_received_at, now()), v_landlord);

    update public.payments
    set amount_paid = amount_paid + v_take,
        status = case when amount_paid + v_take >= amount then 'paid' else 'pending' end,
        paid_at = case when amount_paid + v_take >= amount then coalesce(p_received_at, now()) else paid_at end,
        method = 'Cash'
    where id = c.id;

    if c.amount_paid + v_take >= c.amount then
      v_completed := v_completed || to_char(to_date(c.period || '-01', 'YYYY-MM-DD'), 'FMMonth YYYY');
    end if;
    v_parts := v_parts || json_build_object('period', c.period, 'applied', v_take, 'paid_in_full', c.amount_paid + v_take >= c.amount);
  end loop;

  select coalesce(sum(amount - amount_paid), 0) into v_balance_after
  from public.payments where tenant_id = p_tenant_id and status = 'pending';

  -- Confirmation only for rent that is now fully paid
  if array_length(v_completed, 1) > 0 then
    select p.name into v_house from public.tenants t left join public.properties p on p.id = t.property_id where t.id = p_tenant_id;
    insert into public.notifications (landlord_id, tenant_id, type, title, body)
    values (
      v_landlord, p_tenant_id, 'payment',
      'Payment confirmation', -- sender line; the notification title is always "Renta UG"
      format('Your cash payment for %s%s has been received and recorded. Rent for this period is paid in full. %s',
        array_to_string(v_completed, ', '),
        coalesce(' at ' || v_house, ''),
        case when v_balance_after = 0 then 'You have no outstanding balance. Thank you.'
             else format('Outstanding balance: UGX %s.', to_char(v_balance_after, 'FM999,999,999,999')) end)
    );
  end if;

  return json_build_object('applied', p_amount, 'balance_after', v_balance_after, 'parts', array_to_json(v_parts));
end $$;

revoke execute on function public.record_cash_payment(uuid, bigint, timestamptz, text) from public, anon;
grant execute on function public.record_cash_payment(uuid, bigint, timestamptz, text) to authenticated;
