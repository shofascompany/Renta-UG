-- 33 · landlord issues stay with the landlord
-- The main admin oversees the platform; day-to-day matters between a landlord and their tenants
-- are handled by the landlord alone:
--   • Cash the LANDLORD records counts straight away (they received it). No waiting for Renta UG.
--   • Cash a TENANT reports is confirmed or rejected by their landlord only.
--   • Requests to leave are approved or declined by the landlord only.
--   • The main admin is no longer sent cash or request-to-leave notifications. They can still SEE
--     everything (Activity, Transactions) and step in from the admin console if ever needed
--     (e.g. end a tenancy).
-- Safe to run more than once. No data is deleted.

-- ── Main admin is not notified about landlords' cash ──
create or replace function public.notify_admins(p_type text, p_title text, p_body text) returns void
language sql volatile security definer set search_path = '' as $$ select; $$;

-- ── Only the landlord reviews cash (including any old entries still waiting for Renta UG) ──
create or replace function public.can_review_cash(c public.cash_payments) returns text
language plpgsql stable security definer set search_path = '' as $$
begin
  if public.is_landlord() and c.landlord_id = auth.uid() then return 'landlord'; end if;
  raise exception 'Only the tenant''s landlord can confirm this payment.';
end $$;
revoke execute on function public.can_review_cash(public.cash_payments) from public, anon, authenticated;

-- ── Report / record cash ──
-- Landlord records cash → confirmed immediately (added to the tenant's rent, tenant told once).
-- Tenant reports cash  → their landlord is asked to confirm it.
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
  v_outstanding bigint;
  v_pending bigint;
  v_paid_on date := coalesce(p_paid_on, public.kampala_today());
  v_id uuid;
begin
  select role into v_role from public.profiles where id = me;

  if v_role = 'tenant' then
    select * into v_tenant from public.tenants where id = coalesce(p_tenant_id, public.my_tenant_id()) and user_id = me;
    if not found or v_tenant.property_id is null then raise exception 'You are not connected to a house.'; end if;
  elsif public.is_landlord() then
    select * into v_tenant from public.tenants where id = p_tenant_id and landlord_id = me;
    if not found then raise exception 'Tenant not found.'; end if;
    if v_tenant.property_id is null then raise exception 'This tenant no longer rents from you.'; end if;
    v_role := 'landlord';
  else
    raise exception 'Only tenants and landlords can record cash payments.';
  end if;

  if p_amount is null or p_amount <= 0 then raise exception 'Enter an amount greater than zero.'; end if;
  if v_paid_on > public.kampala_today() then raise exception 'The payment date cannot be in the future.'; end if;

  select name, rent into v_house, v_rent from public.properties where id = v_tenant.property_id;
  v_outstanding := public.tenant_outstanding(v_tenant.id);
  select coalesce(sum(amount), 0) into v_pending from public.cash_payments where tenant_id = v_tenant.id and status = 'pending';

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

  if v_role = 'tenant' then
    insert into public.staff_notifications (user_id, type, title, body, url)
    values (v_tenant.landlord_id, 'cash', 'Cash payment to confirm',
      format('%s says they paid you %s in cash on %s%s. Please confirm the amount you received.',
        v_tenant.full_name, public.ugx(p_amount), to_char(v_paid_on, 'FMDD Mon YYYY'), coalesce(' for ' || v_house, '')),
      '/landlord/payments');
  else
    perform public.confirm_cash_payment(v_id, null); -- the landlord received it: it counts now
  end if;

  return v_id;
end $$;

-- ── Tenant asks to leave: only their landlord is asked ──
create or replace function public.request_move_out(p_rating int, p_review text, p_reason text, p_details text default null)
returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  t record;
  v_house text;
  v_id uuid;
begin
  select * into t from public.tenants where user_id = me and property_id is not null;
  if not found then raise exception 'You are not renting a room right now.'; end if;
  if exists (select 1 from public.move_out_requests where tenant_id = t.id and status = 'pending') then
    raise exception 'You already have a request waiting for approval.';
  end if;
  if nullif(trim(p_reason), '') is null then raise exception 'Tell us why you are leaving.'; end if;
  if p_rating is not null and (p_rating < 1 or p_rating > 5) then raise exception 'Choose a rating from 1 to 5.'; end if;

  insert into public.move_out_requests (tenant_id, landlord_id, property_id, user_id, rating, review, reason, details)
  values (t.id, t.landlord_id, t.property_id, me, p_rating, nullif(trim(p_review), ''), trim(p_reason), nullif(trim(p_details), ''))
  returning id into v_id;

  select name into v_house from public.properties where id = t.property_id;
  insert into public.staff_notifications (user_id, type, title, body, url)
  values (t.landlord_id, 'move_out', 'Request to leave',
    format('%s has asked to leave %s. Reason: %s. Please review and approve or decline.', t.full_name, coalesce(v_house, 'their room'), trim(p_reason)),
    '/landlord/move-outs');
  return v_id;
end $$;

-- ── Landlord approves or declines (their own tenants only) ──
create or replace function public.decide_move_out(p_id uuid, p_approve boolean, p_note text default null) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  r public.move_out_requests;
  t record;
  v_house text;
begin
  select * into r from public.move_out_requests where id = p_id for update;
  if not found then raise exception 'Request not found.'; end if;
  if r.status <> 'pending' then raise exception 'This request has already been %.', r.status; end if;
  if not (public.is_landlord() and r.landlord_id = auth.uid()) then
    raise exception 'Only the tenant''s landlord can decide on this request.';
  end if;

  select * into t from public.tenants where id = r.tenant_id;
  select name into v_house from public.properties where id = coalesce(t.property_id, r.property_id);

  update public.move_out_requests
  set status = case when p_approve then 'approved' else 'declined' end,
      decided_by = auth.uid(), decided_role = 'landlord', decided_at = now(), decision_note = nullif(trim(p_note), '')
  where id = r.id;

  if p_approve then
    if t.property_id is not null then
      update public.tenants
      set last_property_id = property_id, property_id = null, ended_at = now(), connect_code = null, connect_code_expires_at = null
      where id = t.id;
    end if;
    insert into public.notifications (landlord_id, tenant_id, type, title, body)
    values (r.landlord_id, r.tenant_id, 'general', 'Move-out approved',
      format('Your request to leave %s has been approved. Thank you for staying with us. Your payment history is kept safely.', coalesce(v_house, 'your room')));
  else
    insert into public.notifications (landlord_id, tenant_id, type, title, body)
    values (r.landlord_id, r.tenant_id, 'general', 'Move-out request declined',
      format('Your request to leave %s was not approved%s. Please talk to your landlord.', coalesce(v_house, 'your room'), coalesce(': ' || nullif(trim(p_note), ''), '')));
  end if;
end $$;

-- Old main-admin inbox items about landlords' cash and requests to leave: mark as read
update public.staff_notifications s set read = true
from public.profiles p
where p.id = s.user_id and p.role = 'superadmin' and s.type in ('cash', 'move_out') and not s.read;

revoke execute on function public.submit_cash_payment(uuid, bigint, date, text) from public, anon;
revoke execute on function public.request_move_out(int, text, text, text) from public, anon;
revoke execute on function public.decide_move_out(uuid, boolean, text) from public, anon;
grant execute on function public.submit_cash_payment(uuid, bigint, date, text) to authenticated;
grant execute on function public.request_move_out(int, text, text, text) to authenticated;
grant execute on function public.decide_move_out(uuid, boolean, text) to authenticated;
