-- 29 · rental time comes from payments + connection codes only work for the right person
--
--  Rental time (tenants.lease_start / lease_end = "paid from" / "paid up to")
--   • Nobody types dates any more. Each time one month's rent becomes fully paid (mobile money,
--     recharge or confirmed cash), the tenant's rental time grows by exactly one month:
--       – new tenant (no rental time yet)     → starts on the day they pay, ends one month later
--       – tenant already in the room          → continues from where their paid time ended, even if
--                                               they pay late (the late days are not given back)
--   • Existing tenants are recalculated once from what they have already paid.
--
--  Connection codes
--   • A code only connects an account whose email OR phone number matches the tenant's record.
--
-- Safe to run more than once.

-- ── Rental time grows with every fully paid month ──
create or replace function public.extend_rental_time() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_day date := (coalesce(new.paid_at, now()) at time zone 'Africa/Kampala')::date;
begin
  if new.status <> 'paid' or (tg_op = 'UPDATE' and old.status = 'paid') then
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
  after insert or update of status on public.payments
  for each row execute function public.extend_rental_time();

-- ── One-time recalculation for current tenants: paid up to = start + months fully paid ──
update public.tenants t
set lease_start = s.start_day,
    lease_end = case when s.paid_months > 0 then (s.start_day + make_interval(months => s.paid_months))::date end
from (
  select tn.id,
         coalesce(
           tn.lease_start,
           (select min((p.paid_at at time zone 'Africa/Kampala')::date) from public.payments p where p.tenant_id = tn.id and p.status = 'paid'),
           (tn.created_at at time zone 'Africa/Kampala')::date
         ) as start_day,
         (select count(*)::int from public.payments p where p.tenant_id = tn.id and p.status = 'paid') as paid_months
  from public.tenants tn
  where tn.property_id is not null
) s
where t.id = s.id;

-- New tenants start with no rental time until they pay
update public.tenants set lease_start = null
where property_id is not null and lease_end is null
  and not exists (select 1 from public.payments p where p.tenant_id = tenants.id and p.status = 'paid');

-- ── Connection code: must match the account's email or phone ──
create or replace function public.redeem_connect_code(p_code text) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  t record;
  me uuid := auth.uid();
  v_email text;
  v_phone text;
  digits9 text;
begin
  if me is null then
    raise exception 'Please sign in first.';
  end if;
  if not exists (select 1 from public.profiles where id = me and role = 'tenant') then
    raise exception 'Only tenant accounts can use a connection code.';
  end if;
  if exists (select 1 from public.tenants where user_id = me and property_id is not null) then
    raise exception 'Your account is already connected to a rental.';
  end if;

  select * into t
  from public.tenants
  where connect_code = upper(trim(p_code))
    and connect_code_expires_at > now()
    and user_id is null
  for update;

  if t.id is null then
    raise exception 'This code is invalid or has expired. Ask your landlord for a new one.';
  end if;

  -- The signed-in account must be the person the landlord registered
  select lower(coalesce(u.email, '')), right(regexp_replace(coalesce(p.phone, u.phone, ''), '\D', '', 'g'), 9)
    into v_email, v_phone
  from auth.users u left join public.profiles p on p.id = u.id
  where u.id = me;
  digits9 := right(regexp_replace(coalesce(t.phone, ''), '\D', '', 'g'), 9);

  if not (
    (t.email is not null and lower(t.email) = v_email)
    or (length(digits9) = 9 and digits9 = v_phone)
  ) then
    raise exception 'This code is for a different account. Sign in with the email or phone number your landlord registered for you, or ask them to check your details.';
  end if;

  -- Detach any former-tenant record so user_id stays unique
  update public.tenants set user_id = null where user_id = me;

  update public.tenants
  set user_id = me,
      email = coalesce(email, nullif(v_email, '')),
      connect_code = null,
      connect_code_expires_at = null
  where id = t.id;

  return t.id;
end $$;

revoke execute on function public.redeem_connect_code(text) from public, anon;
grant execute on function public.redeem_connect_code(text) to authenticated;
