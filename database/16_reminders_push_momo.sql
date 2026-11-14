-- 16 · reminders, phone notifications and mobile money
--   • removes the old "alerts" feature (the app now uses notifications only)
--   • automatic end-of-stay reminders: every day in the last 7 days of a lease (pg_cron)
--   • push subscriptions: which phones get notifications in their notification panel
--   • mobile money attempts: MTN / Airtel payments, verified automatically by the server
-- Safe to run more than once. ⚠ Deletes the alerts table and its data.

-- ── Remove alerts ──
drop table if exists public.alerts cascade;

-- ── Notifications: reminder type, de-duplication, push tracking ──
alter table public.notifications drop constraint if exists notifications_type_check;
-- Full list (incl. the types added in 18), so re-running this on a newer database doesn't fail
alter table public.notifications
  add constraint notifications_type_check
  check (type in ('general', 'maintenance', 'payment', 'reminder', 'security', 'welcome', 'status', 'rent_due'));
alter table public.notifications add column if not exists dedupe_key text;
alter table public.notifications add column if not exists pushed_at timestamptz;
create unique index if not exists notifications_dedupe_key on public.notifications (dedupe_key);
-- Don't push old notifications when phone notifications are first switched on
update public.notifications set pushed_at = coalesce(pushed_at, created_at) where pushed_at is null and created_at < now() - interval '10 minutes';

-- ── End-of-stay reminders ──
-- One notification per tenant per day while 0–7 days remain on the lease (Uganda time).
create or replace function public.send_lease_reminders() returns integer
language plpgsql volatile security definer set search_path = '' as $$
declare
  today date := (now() at time zone 'Africa/Kampala')::date;
  n integer;
begin
  insert into public.notifications (landlord_id, tenant_id, type, title, body, dedupe_key)
  select
    t.landlord_id,
    t.id,
    'reminder',
    'Tenancy reminder', -- sender line; the notification title is always "Renta UG"
    case
      when d.days_left = 0 then format(
        'Your current rental period for %s ends today. Please settle any outstanding rent and confirm your plans with your landlord.', p.name)
      when d.days_left = 1 then format(
        'Your current rental period for %s ends tomorrow, %s. Please arrange your next payment or inform your landlord of your plans.',
        p.name, to_char(t.lease_end, 'FMDD Mon YYYY'))
      else format(
        'Your current rental period for %s ends in %s days, on %s. Please arrange your next payment or inform your landlord of your plans.',
        p.name, d.days_left, to_char(t.lease_end, 'FMDD Mon YYYY'))
    end,
    format('lease_end:%s:%s', t.id, today)
  from public.tenants t
  join public.properties p on p.id = t.property_id
  cross join lateral (select (t.lease_end - today) as days_left) d
  where t.property_id is not null
    and t.lease_end is not null
    and d.days_left between 0 and 7
  on conflict (dedupe_key) do nothing;

  get diagnostics n = row_count;
  return n;
end $$;

revoke execute on function public.send_lease_reminders() from public, anon, authenticated;

-- Run every day at 06:00 UTC = 09:00 in Kampala
create extension if not exists pg_cron;
select cron.schedule('renta-lease-reminders', '0 6 * * *', 'select public.send_lease_reminders()');
-- …and once now, so anyone already in their last week is reminded today
select public.send_lease_reminders();

-- ── Phones registered for notifications ──
create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  created_at timestamptz not null default now()
);
create index if not exists push_subscriptions_user_id_idx on public.push_subscriptions (user_id);
alter table public.push_subscriptions enable row level security;

drop policy if exists "push read own" on public.push_subscriptions;
create policy "push read own" on public.push_subscriptions for select to authenticated using (user_id = auth.uid());

-- Save / remove this device for the signed-in user (a phone may change hands between accounts)
create or replace function public.save_push_subscription(p_endpoint text, p_p256dh text, p_auth text) returns void
language sql volatile security definer set search_path = '' as $$
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth)
  values (auth.uid(), p_endpoint, p_p256dh, p_auth)
  on conflict (endpoint) do update set user_id = auth.uid(), p256dh = excluded.p256dh, auth = excluded.auth;
$$;

create or replace function public.delete_push_subscription(p_endpoint text) returns void
language sql volatile security definer set search_path = '' as $$
  delete from public.push_subscriptions where endpoint = p_endpoint and user_id = auth.uid();
$$;

revoke execute on function public.save_push_subscription(text, text, text) from public, anon;
revoke execute on function public.delete_push_subscription(text) from public, anon;
grant execute on function public.save_push_subscription(text, text, text) to authenticated;
grant execute on function public.delete_push_subscription(text) to authenticated;

-- ── Mobile money payment attempts (written only by the server) ──
create table if not exists public.momo_attempts (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.payments (id) on delete cascade,
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  landlord_id uuid not null references auth.users (id) on delete cascade,
  network text not null check (network in ('MTN', 'AIRTEL')),
  phone text not null,
  amount bigint not null,
  tx_ref text not null unique,
  provider text not null,              -- 'flutterwave' or 'test'
  provider_ref text,
  status text not null default 'pending' check (status in ('pending', 'successful', 'failed')),
  failure_reason text,
  redirect_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists momo_attempts_payment_id_idx on public.momo_attempts (payment_id);
create index if not exists momo_attempts_pending_idx on public.momo_attempts (status) where status = 'pending';
alter table public.momo_attempts enable row level security;

-- Table access: read only for signed-in users (writes go through the functions / the server)
revoke all on public.push_subscriptions, public.momo_attempts from anon, authenticated;
grant select on public.push_subscriptions, public.momo_attempts to authenticated;
grant all on public.push_subscriptions, public.momo_attempts to service_role;

drop policy if exists "momo tenant read" on public.momo_attempts;
drop policy if exists "momo landlord read" on public.momo_attempts;
create policy "momo tenant read" on public.momo_attempts for select to authenticated using (tenant_id = public.my_tenant_id());
create policy "momo landlord read" on public.momo_attempts for select to authenticated
  using (public.is_landlord() and landlord_id = auth.uid());
