-- 32 · main admin console
-- The main admin can now change things across the whole platform, not just read them. Every change
-- goes through a function below that checks the caller is the main admin and writes an entry to the
-- activity log (admin_audit), so there is always a record of who changed what.
--   • admin_update_property(id, name, location, rent)
--   • admin_delete_property(id)                 only an empty property with no history
--   • admin_update_tenant(id, name, phone, email)
--   • admin_end_tenancy(id, reason)             history kept; tenant + landlord are told
--   • admin_broadcast(audience, landlord, message)  announcement to tenants / landlords / everyone
--   • admin_note(action, summary)               log something done elsewhere (e.g. on the server)
-- Safe to run more than once. No data is deleted.

create table if not exists public.admin_audit (
  id uuid primary key default gen_random_uuid(),
  actor uuid references auth.users (id) on delete set null,
  action text not null,
  target_type text,
  target_id uuid,
  summary text not null,
  created_at timestamptz not null default now()
);
create index if not exists admin_audit_created_idx on public.admin_audit (created_at desc);
alter table public.admin_audit enable row level security;
drop policy if exists "audit superadmin read" on public.admin_audit;
create policy "audit superadmin read" on public.admin_audit for select to authenticated using (public.is_superadmin());
revoke all on public.admin_audit from anon, authenticated;
grant select on public.admin_audit to authenticated;
grant all on public.admin_audit to service_role;
do $$ begin
  alter publication supabase_realtime add table public.admin_audit;
exception when duplicate_object then null; end $$;

-- ── Internal helpers ──
create or replace function public.admin_require() returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_superadmin() then raise exception 'Only the main admin can do this.'; end if;
end $$;
revoke execute on function public.admin_require() from public, anon, authenticated;

create or replace function public.admin_log(p_action text, p_type text, p_id uuid, p_summary text) returns void
language sql volatile security definer set search_path = '' as $$
  insert into public.admin_audit (actor, action, target_type, target_id, summary)
  values (auth.uid(), p_action, p_type, p_id, p_summary);
$$;
revoke execute on function public.admin_log(text, text, uuid, text) from public, anon, authenticated;

-- ── Properties ──
create or replace function public.admin_update_property(p_id uuid, p_name text, p_location text, p_rent bigint) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  old record;
  v_changes text[] := '{}';
begin
  perform public.admin_require();
  select * into old from public.properties where id = p_id for update;
  if not found then raise exception 'Property not found.'; end if;
  if nullif(trim(p_name), '') is null then raise exception 'Enter a name.'; end if;
  if p_rent is null or p_rent < 0 then raise exception 'Enter a valid monthly rent.'; end if;

  update public.properties
  set name = trim(p_name), location = coalesce(nullif(trim(p_location), ''), location), rent = p_rent
  where id = p_id;

  if old.name is distinct from trim(p_name) then v_changes := v_changes || format('name "%s" → "%s"', old.name, trim(p_name)); end if;
  if nullif(trim(p_location), '') is not null and old.location is distinct from trim(p_location) then
    v_changes := v_changes || format('location → %s', trim(p_location));
  end if;
  if old.rent is distinct from p_rent then v_changes := v_changes || format('rent %s → %s', public.ugx(old.rent), public.ugx(p_rent)); end if;

  if array_length(v_changes, 1) > 0 then
    perform public.admin_log('property.update', 'property', p_id, format('Edited %s: %s', trim(p_name), array_to_string(v_changes, ', ')));
    insert into public.staff_notifications (user_id, type, title, body, url)
    values (old.landlord_id, 'admin', 'Property updated by Renta UG',
      format('Renta UG updated %s: %s.', trim(p_name), array_to_string(v_changes, ', ')), '/landlord/properties');
  end if;
end $$;

create or replace function public.admin_delete_property(p_id uuid) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare p record;
begin
  perform public.admin_require();
  select * into p from public.properties where id = p_id;
  if not found then raise exception 'Property not found.'; end if;
  if exists (select 1 from public.tenants where property_id = p_id or last_property_id = p_id)
     or exists (select 1 from public.payments where property_id = p_id) then
    raise exception 'This property has tenants or payment history, so it cannot be deleted. Edit it instead.';
  end if;
  delete from public.properties where id = p_id;
  perform public.admin_log('property.delete', 'property', p_id, format('Deleted empty property %s', p.name));
  insert into public.staff_notifications (user_id, type, title, body, url)
  values (p.landlord_id, 'admin', 'Property removed by Renta UG', format('Renta UG removed the empty property %s from your account.', p.name), '/landlord/properties');
end $$;

-- ── Tenants ──
create or replace function public.admin_update_tenant(p_id uuid, p_name text, p_phone text, p_email text) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare old record;
begin
  perform public.admin_require();
  select * into old from public.tenants where id = p_id for update;
  if not found then raise exception 'Tenant not found.'; end if;
  if nullif(trim(p_name), '') is null then raise exception 'Enter a name.'; end if;
  update public.tenants
  set full_name = trim(p_name),
      phone = nullif(trim(p_phone), ''),
      email = coalesce(nullif(lower(trim(p_email)), ''), email)
  where id = p_id;
  perform public.admin_log('tenant.update', 'tenant', p_id,
    format('Edited tenant %s%s', trim(p_name), case when old.full_name <> trim(p_name) then format(' (was %s)', old.full_name) else '' end));
end $$;

create or replace function public.admin_end_tenancy(p_id uuid, p_reason text default null) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  t record;
  v_house text;
begin
  perform public.admin_require();
  select * into t from public.tenants where id = p_id for update;
  if not found then raise exception 'Tenant not found.'; end if;
  if t.property_id is null then raise exception 'This tenancy has already ended.'; end if;
  select name into v_house from public.properties where id = t.property_id;

  update public.tenants
  set last_property_id = property_id, property_id = null, ended_at = now(), connect_code = null, connect_code_expires_at = null
  where id = p_id;

  -- A waiting request to leave is now settled
  update public.move_out_requests
  set status = 'approved', decided_by = auth.uid(), decided_role = 'superadmin', decided_at = now(),
      decision_note = coalesce(nullif(trim(p_reason), ''), decision_note)
  where tenant_id = p_id and status = 'pending';

  insert into public.notifications (landlord_id, tenant_id, type, title, body)
  values (t.landlord_id, t.id, 'general', 'Tenancy ended',
    format('Your tenancy at %s has been ended by Renta UG%s. Your payment history is kept safely.',
      coalesce(v_house, 'your rental'), coalesce(': ' || nullif(trim(p_reason), ''), '')));
  insert into public.staff_notifications (user_id, type, title, body, url)
  values (t.landlord_id, 'admin', 'Tenancy ended by Renta UG',
    format('Renta UG ended %s''s tenancy at %s%s. The room is now vacant and their history is in Records.',
      t.full_name, coalesce(v_house, 'their rental'), coalesce(': ' || nullif(trim(p_reason), ''), '')),
    '/landlord/records');
  perform public.admin_log('tenant.end', 'tenant', p_id,
    format('Ended %s''s tenancy at %s%s', t.full_name, coalesce(v_house, 'their rental'), coalesce(' (' || nullif(trim(p_reason), '') || ')', '')));
end $$;

-- ── Announcements ──
-- p_audience: 'tenants' | 'landlords' | 'everyone'. p_landlord limits it to one landlord (and their tenants).
create or replace function public.admin_broadcast(p_audience text, p_landlord uuid, p_message text) returns integer
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_msg text := trim(coalesce(p_message, ''));
  n_t integer := 0;
  n_l integer := 0;
begin
  perform public.admin_require();
  if length(v_msg) < 3 then raise exception 'Write a message first.'; end if;
  if length(v_msg) > 1000 then raise exception 'Keep the message under 1,000 characters.'; end if;
  if p_audience not in ('tenants', 'landlords', 'everyone') then raise exception 'Choose who gets the message.'; end if;

  if p_audience in ('tenants', 'everyone') then
    insert into public.notifications (landlord_id, tenant_id, type, title, body)
    select t.landlord_id, t.id, 'general', 'From Renta UG', v_msg
    from public.tenants t
    where t.property_id is not null and t.user_id is not null
      and (p_landlord is null or t.landlord_id = p_landlord);
    get diagnostics n_t = row_count;
  end if;

  if p_audience in ('landlords', 'everyone') then
    insert into public.staff_notifications (user_id, type, title, body, url)
    select p.id, 'admin', 'From Renta UG', v_msg, '/landlord/inbox'
    from public.profiles p
    where p.role = 'landlord' and p.active and (p_landlord is null or p.id = p_landlord);
    get diagnostics n_l = row_count;
  end if;

  perform public.admin_log('broadcast', 'broadcast', p_landlord,
    format('Announcement to %s%s (%s tenant%s, %s landlord%s): %s',
      p_audience, case when p_landlord is not null then ' of one landlord' else '' end,
      n_t, case when n_t = 1 then '' else 's' end, n_l, case when n_l = 1 then '' else 's' end, left(v_msg, 300)));
  return n_t + n_l;
end $$;

-- ── Log an action done elsewhere (e.g. landlord registered / suspended through the server) ──
create or replace function public.admin_note(p_action text, p_type text, p_id uuid, p_summary text) returns void
language plpgsql volatile security definer set search_path = '' as $$
begin
  perform public.admin_require();
  perform public.admin_log(left(p_action, 60), left(p_type, 30), p_id, left(p_summary, 500));
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'admin_update_property(uuid, text, text, bigint)',
    'admin_delete_property(uuid)',
    'admin_update_tenant(uuid, text, text, text)',
    'admin_end_tenancy(uuid, text)',
    'admin_broadcast(text, uuid, text)',
    'admin_note(text, text, uuid, text)'
  ] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
