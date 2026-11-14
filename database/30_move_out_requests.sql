-- 30 · move-out requests
-- A tenant asks to leave their room: they rate the place, write a review and say why they're leaving.
-- The request waits for their landlord OR the main admin. Approved → the tenancy ends (the tenant moves
-- to Records with all history kept, the room becomes vacant) and the tenant's app signs them out.
-- Declined → the tenant is told why and keeps using the app as before.
-- Safe to run more than once. No data is deleted.

create table if not exists public.move_out_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  landlord_id uuid not null references auth.users (id) on delete cascade,
  property_id uuid references public.properties (id) on delete set null,
  user_id uuid references auth.users (id) on delete set null,
  rating int check (rating between 1 and 5),
  review text,
  reason text not null,
  details text,
  status text not null default 'pending' check (status in ('pending', 'approved', 'declined', 'cancelled')),
  decided_by uuid references auth.users (id) on delete set null,
  decided_role text check (decided_role in ('landlord', 'superadmin')),
  decided_at timestamptz,
  decision_note text,
  created_at timestamptz not null default now()
);
create index if not exists move_out_requests_tenant_idx on public.move_out_requests (tenant_id);
create index if not exists move_out_requests_landlord_idx on public.move_out_requests (landlord_id);
create unique index if not exists move_out_requests_one_pending on public.move_out_requests (tenant_id) where status = 'pending';

alter table public.move_out_requests enable row level security;
drop policy if exists "move out tenant read" on public.move_out_requests;
drop policy if exists "move out landlord read" on public.move_out_requests;
drop policy if exists "move out superadmin read" on public.move_out_requests;
create policy "move out tenant read" on public.move_out_requests for select to authenticated using (user_id = auth.uid());
create policy "move out landlord read" on public.move_out_requests for select to authenticated
  using (public.is_landlord() and landlord_id = auth.uid());
create policy "move out superadmin read" on public.move_out_requests for select to authenticated using (public.is_superadmin());

-- Read only; every change goes through the functions below
revoke all on public.move_out_requests from anon, authenticated;
grant select on public.move_out_requests to authenticated;
grant all on public.move_out_requests to service_role;

do $$ begin
  alter publication supabase_realtime add table public.move_out_requests;
exception when duplicate_object then null; end $$;

-- ── Tenant: ask to leave ──
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
  insert into public.staff_notifications (user_id, type, title, body, url)
  select id, 'move_out', 'Request to leave',
    format('%s (%s) has asked to leave. Reason: %s.', t.full_name, coalesce(v_house, 'no house'), trim(p_reason)),
    '/admin2026/move-outs'
  from public.profiles where role = 'superadmin';
  return v_id;
end $$;

-- ── Tenant: changed their mind ──
create or replace function public.cancel_move_out() returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  r record;
begin
  update public.move_out_requests set status = 'cancelled', decided_at = now()
  where user_id = auth.uid() and status = 'pending'
  returning * into r;
  if r.id is null then raise exception 'There is no request to cancel.'; end if;
  insert into public.staff_notifications (user_id, type, title, body, url)
  select r.landlord_id, 'move_out', 'Request to leave cancelled',
    format('%s has cancelled their request to leave.', full_name), '/landlord/move-outs'
  from public.tenants where id = r.tenant_id;
end $$;

-- ── Landlord (own tenants) or main admin: approve or decline ──
create or replace function public.decide_move_out(p_id uuid, p_approve boolean, p_note text default null) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  r public.move_out_requests;
  v_role text;
  t record;
  v_house text;
begin
  select * into r from public.move_out_requests where id = p_id for update;
  if not found then raise exception 'Request not found.'; end if;
  if r.status <> 'pending' then raise exception 'This request has already been %.', r.status; end if;
  if public.is_superadmin() then v_role := 'superadmin';
  elsif public.is_landlord() and r.landlord_id = auth.uid() then v_role := 'landlord';
  else raise exception 'You cannot decide on this request.';
  end if;

  select * into t from public.tenants where id = r.tenant_id;
  select name into v_house from public.properties where id = coalesce(t.property_id, r.property_id);

  update public.move_out_requests
  set status = case when p_approve then 'approved' else 'declined' end,
      decided_by = auth.uid(), decided_role = v_role, decided_at = now(), decision_note = nullif(trim(p_note), '')
  where id = r.id;

  if p_approve then
    -- End the tenancy: history stays, the room becomes vacant
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

  -- Tell the other side
  if v_role = 'superadmin' then
    insert into public.staff_notifications (user_id, type, title, body, url)
    values (r.landlord_id, 'move_out', case when p_approve then 'Tenant moved out' else 'Move-out declined' end,
      format('Renta UG %s the request from %s to leave %s.', case when p_approve then 'approved' else 'declined' end, t.full_name, coalesce(v_house, 'their room')),
      '/landlord/move-outs');
  else
    insert into public.staff_notifications (user_id, type, title, body, url)
    select id, 'move_out', case when p_approve then 'Tenant moved out' else 'Move-out declined' end,
      format('A landlord %s the request from %s to leave %s.', case when p_approve then 'approved' else 'declined' end, t.full_name, coalesce(v_house, 'their room')),
      '/admin2026/move-outs'
    from public.profiles where role = 'superadmin';
  end if;
end $$;

-- ── Tenant saw the goodbye and signed out: free the account ──
-- Unlinks the app account from the old stay (the landlord keeps the tenant, payments and request in
-- Records). Next sign-in the account is fresh: no old data, and it can connect to a new landlord with
-- a new code the normal way.
create or replace function public.finish_move_out() returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
begin
  if me is null then return; end if;
  -- Only once the move-out was approved and the tenancy has really ended
  if not exists (
    select 1 from public.move_out_requests r join public.tenants t on t.id = r.tenant_id
    where r.user_id = me and r.status = 'approved' and t.property_id is null
  ) then
    return;
  end if;
  update public.tenants set user_id = null where user_id = me and property_id is null;
  update public.move_out_requests set user_id = null where user_id = me and status <> 'pending';
end $$;

revoke execute on function public.finish_move_out() from public, anon;
grant execute on function public.finish_move_out() to authenticated;

revoke execute on function public.request_move_out(int, text, text, text) from public, anon;
revoke execute on function public.cancel_move_out() from public, anon;
revoke execute on function public.decide_move_out(uuid, boolean, text) from public, anon;
grant execute on function public.request_move_out(int, text, text, text) to authenticated;
grant execute on function public.cancel_move_out() to authenticated;
grant execute on function public.decide_move_out(uuid, boolean, text) to authenticated;
