-- 18 · smart notifications
--   • new types: security (sign-in alerts), welcome (connected to landlord), status (rent check), rent_due (overdue reminder)
--   • sign-in alert: device and time, for tenants, landlords and the main admin
--   • welcome: when a tenant connects to their landlord (+ a note in the landlord's inbox)
--   • rent status: on sign-in and the first time the app is opened each day
--   • overdue reminders: every 5 hours (07:00–22:00 Kampala) while rent is overdue or the paid period has ended
--   • landlords can't see their tenants' sign-in alerts
-- Every notification's TITLE is shown as "Renta UG"; the `title` column holds the sender line
-- (e.g. "Rent reminder", "Account security"), followed by the message in `body`.
-- Safe to run more than once. No data is deleted.

-- ── Types ──
alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in ('general', 'maintenance', 'payment', 'reminder', 'security', 'welcome', 'status', 'rent_due'));

create index if not exists notifications_tenant_type_created_idx on public.notifications (tenant_id, type, created_at desc);

-- ── Landlords: everything for their tenants EXCEPT the tenant's private sign-in alerts ──
drop policy if exists "notifications landlord" on public.notifications;
create policy "notifications landlord" on public.notifications for all to authenticated
  using (public.is_landlord() and landlord_id = auth.uid() and type <> 'security')
  with check (public.is_landlord() and landlord_id = auth.uid() and public.owns_tenant(tenant_id));

-- ── Helpers ──
create or replace function public.ugx(p_amount bigint) returns text
language sql immutable set search_path = '' as $$
  select 'UGX ' || to_char(coalesce(p_amount, 0), 'FM999,999,999,999');
$$;

create or replace function public.kampala_today() returns date
language sql stable set search_path = '' as $$
  select (now() at time zone 'Africa/Kampala')::date;
$$;

create or replace function public.days_text(p_days integer) returns text
language sql immutable set search_path = '' as $$
  select case when p_days = 1 then '1 day' else p_days || ' days' end;
$$;

-- ── Rent status for one tenant (internal) ──
-- p_force = true  → always send (sign-in)
-- p_force = false → at most once per day (opening the app)
create or replace function public.send_rent_status(p_tenant_id uuid, p_force boolean) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  t record;
  today date := public.kampala_today();
  v_key text := format('status:%s:%s', p_tenant_id, public.kampala_today());
  v_owed bigint;
  v_overdue bigint;
  v_oldest_overdue date;
  v_next_due date;
  v_next_amount bigint;
  v_days_left integer;
  v_body text;
begin
  select tn.*, p.name as house into t
  from public.tenants tn join public.properties p on p.id = tn.property_id
  where tn.id = p_tenant_id and tn.property_id is not null;
  if not found then return; end if;

  if not p_force and exists (select 1 from public.notifications where dedupe_key = v_key) then
    return;
  end if;

  select coalesce(sum(amount - amount_paid), 0),
         coalesce(sum(amount - amount_paid) filter (where due_date < today), 0),
         min(due_date) filter (where due_date < today)
    into v_owed, v_overdue, v_oldest_overdue
  from public.payments where tenant_id = t.id and status = 'pending';

  select due_date, amount - amount_paid into v_next_due, v_next_amount
  from public.payments where tenant_id = t.id and status = 'pending' and due_date >= today
  order by due_date limit 1;

  v_days_left := case when t.lease_end is not null then t.lease_end - today end;

  if v_overdue > 0 then
    v_body := format('Your rent of %s for %s was due on %s and is now %s overdue. Please make payment through the Payments page at your earliest convenience.',
      public.ugx(v_overdue), t.house, to_char(v_oldest_overdue, 'FMDD Mon YYYY'), public.days_text(today - v_oldest_overdue));
  elsif v_days_left is not null and v_days_left < 0 then
    v_body := format('Your paid rental period for %s ended on %s. Please make a payment to renew your tenancy, or contact your landlord to discuss your plans.',
      t.house, to_char(t.lease_end, 'FMDD Mon YYYY'));
  elsif v_next_due = today then
    v_body := format('Your rent of %s for %s is due today. You can pay securely via MTN Mobile Money or Airtel Money on the Payments page.',
      public.ugx(v_next_amount), t.house);
  elsif v_next_due is not null and v_next_due - today <= 7 then
    v_body := format('Your rent of %s for %s is due on %s (in %s). You can pay securely via MTN Mobile Money or Airtel Money on the Payments page.',
      public.ugx(v_next_amount), t.house, to_char(v_next_due, 'FMDay, FMDD Mon'), public.days_text(v_next_due - today));
  elsif v_days_left is not null and v_days_left <= 7 then
    v_body := format('Your current rental period for %s ends %s. Please arrange your next payment or inform your landlord of your plans.',
      t.house,
      case when v_days_left = 0 then 'today'
           when v_days_left = 1 then 'tomorrow, ' || to_char(t.lease_end, 'FMDD Mon YYYY')
           else format('on %s (in %s)', to_char(t.lease_end, 'FMDD Mon YYYY'), public.days_text(v_days_left)) end);
  elsif v_owed > 0 then
    v_body := format('Your next rent payment of %s for %s is due on %s. No action is required at this time.',
      public.ugx(v_next_amount), t.house, to_char(v_next_due, 'FMDD Mon YYYY'));
  else
    v_body := 'Your rent is fully paid.' ||
      case when v_days_left is not null
        then format(' Your current rental period for %s runs until %s (%s remaining).', t.house, to_char(t.lease_end, 'FMDD Mon YYYY'), public.days_text(v_days_left))
        else '' end || ' Thank you.';
  end if;

  insert into public.notifications (landlord_id, tenant_id, type, title, body, dedupe_key)
  values (t.landlord_id, t.id, 'status', 'Rent status', v_body,
          case when exists (select 1 from public.notifications where dedupe_key = v_key) then null else v_key end)
  on conflict (dedupe_key) do nothing;
end $$;

revoke execute on function public.send_rent_status(uuid, boolean) from public, anon, authenticated;

-- ── Tenant opens the app: rent status at most once a day ──
create or replace function public.check_rent_status() returns void
language plpgsql volatile security definer set search_path = '' as $$
declare v_tenant uuid;
begin
  select id into v_tenant from public.tenants where user_id = auth.uid() and property_id is not null;
  if v_tenant is not null then
    perform public.send_rent_status(v_tenant, false);
  end if;
end $$;

-- ── Anyone signs in: security alert (+ rent status for tenants) ──
create or replace function public.notify_sign_in(p_device text) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  v_role text;
  v_device text := left(coalesce(nullif(trim(p_device), ''), 'an unknown device'), 80);
  v_when text := to_char(now() at time zone 'Africa/Kampala', 'FMHH12:MI AM "on" FMDD Mon YYYY');
  v_body text;
  t record;
begin
  if me is null then return; end if;
  select role into v_role from public.profiles where id = me;
  v_body := format('A new sign-in to your account was detected on %s at %s (EAT). If this was not you, please change your password immediately under Settings > Change password.', v_device, v_when);

  if v_role in ('landlord', 'superadmin') then
    insert into public.staff_notifications (user_id, type, title, body, url)
    values (me, 'security', 'Account security', v_body, case when v_role = 'landlord' then '/landlord/inbox' else '/admin2026/inbox' end);
    return;
  end if;

  -- Tenants: notifications belong to a tenant record (none yet = not connected, nothing to store)
  select id, landlord_id, property_id into t from public.tenants where user_id = me;
  if not found then return; end if;

  insert into public.notifications (landlord_id, tenant_id, type, title, body)
  values (t.landlord_id, t.id, 'security', 'Account security', v_body);

  if t.property_id is not null then
    perform public.send_rent_status(t.id, true);
  end if;
end $$;

revoke execute on function public.check_rent_status() from public, anon;
revoke execute on function public.notify_sign_in(text) from public, anon;
grant execute on function public.check_rent_status() to authenticated;
grant execute on function public.notify_sign_in(text) to authenticated;

-- ── Tenant connects to their landlord: welcome + note to the landlord ──
create or replace function public.notify_tenant_connected() returns trigger
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_house text;
  v_landlord text;
begin
  if new.user_id is null or new.property_id is null or old.user_id is not distinct from new.user_id then
    return new;
  end if;
  select name into v_house from public.properties where id = new.property_id;
  select nullif(full_name, '') into v_landlord from public.profiles where id = new.landlord_id;

  insert into public.notifications (landlord_id, tenant_id, type, title, body)
  values (new.landlord_id, new.id, 'welcome', 'Account connected',
    format('Your account is now connected to %s%s. Rent charges, payment receipts and notices from your landlord will appear here.',
      coalesce(v_house, 'your rental'), coalesce(', managed by ' || v_landlord, '')));

  insert into public.staff_notifications (user_id, type, title, body, url)
  values (new.landlord_id, 'tenant', 'Tenant connected',
    format('%s has connected their Renta account for %s and will now receive your notifications.', new.full_name, coalesce(v_house, 'their rental')),
    '/landlord/tenants');
  return new;
end $$;

drop trigger if exists tenants_notify_connected on public.tenants;
create trigger tenants_notify_connected after update of user_id on public.tenants
  for each row execute function public.notify_tenant_connected();

-- ── Every 5 hours while rent is overdue or the paid period has ended ──
create or replace function public.send_overdue_reminders() returns integer
language plpgsql volatile security definer set search_path = '' as $$
declare
  today date := public.kampala_today();
  v_hour integer := extract(hour from now() at time zone 'Africa/Kampala');
  n integer;
begin
  if v_hour < 7 or v_hour >= 22 then return 0; end if; -- quiet hours: no reminders at night

  insert into public.notifications (landlord_id, tenant_id, type, title, body)
  select t.landlord_id, t.id, 'rent_due', 'Rent reminder',
    case when o.amount > 0
      then format('This is a reminder that %s for %s has been outstanding since %s. Please make payment through the Payments page as soon as possible.',
             public.ugx(o.amount), p.name, to_char(o.since, 'FMDD Mon YYYY'))
      else format('Your paid rental period for %s ended on %s. Please make a payment to renew your tenancy, or contact your landlord to discuss your plans.',
             p.name, to_char(t.lease_end, 'FMDD Mon YYYY')) end
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
      where x.tenant_id = t.id and x.type = 'rent_due' and x.created_at > now() - interval '4 hours 50 minutes'
    );

  get diagnostics n = row_count;
  return n;
end $$;

revoke execute on function public.send_overdue_reminders() from public, anon, authenticated;

-- Checked every hour; each tenant gets one at most every 5 hours
create extension if not exists pg_cron;
select cron.schedule('renta-overdue-reminders', '0 * * * *', 'select public.send_overdue_reminders()');
