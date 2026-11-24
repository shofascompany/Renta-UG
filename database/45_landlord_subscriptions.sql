-- 45 · landlord subscriptions (safe to run again; no data is deleted)
--
-- Landlords pay Renta UG a MONTHLY or YEARLY subscription to manage their properties.
--  • Prices, the free-trial length and Renta UG's MTN / Airtel receiving numbers are set by the main admin
--    (billing_settings, one row).
--  • Every landlord has: subscription_until (last day covered), subscription_plan (null = free trial) and a
--    billing_code: their payment reason, like a tenant's pay code.
--  • New landlords (and all existing ones, once) get the free trial.
--  • A landlord pays with mobile money from their phone, then submits the payment. It waits as 'pending'
--    until the main admin confirms it; the subscription is then extended (on top of any time left).
--  • When the subscription has ended a landlord can still SEE everything and renew, but every change
--    (houses, tenants, payments, notices, requests to leave…) is refused by the database itself.
--  • Reminders in the landlord's inbox 7, 3 and 1 days before the end, on the day, and the day after.

-- ── Settings ──
create table if not exists public.billing_settings (
  id int primary key default 1 check (id = 1),
  monthly_price bigint not null default 30000 check (monthly_price > 0),
  yearly_price bigint not null default 300000 check (yearly_price > 0),
  trial_days int not null default 30 check (trial_days between 0 and 365),
  mtn_phone text,
  mtn_name text,
  airtel_phone text,
  airtel_name text,
  updated_at timestamptz not null default now()
);
insert into public.billing_settings (id) values (1) on conflict (id) do nothing;
alter table public.billing_settings enable row level security;
drop policy if exists "billing settings read" on public.billing_settings;
create policy "billing settings read" on public.billing_settings for select to authenticated using (true);
revoke all on public.billing_settings from public, anon, authenticated;
grant select on public.billing_settings to authenticated;
grant all on public.billing_settings to service_role;

-- ── The landlord's subscription (on their profile; users can't write these columns) ──
alter table public.profiles add column if not exists subscription_until date;
alter table public.profiles add column if not exists subscription_plan text;
alter table public.profiles add column if not exists billing_code text;
create unique index if not exists profiles_billing_code_key on public.profiles (billing_code) where billing_code is not null;
do $$ begin
  alter table public.profiles add constraint profiles_subscription_plan_check check (subscription_plan in ('monthly', 'yearly'));
exception when duplicate_object then null; end $$;

create or replace function public.new_billing_code() returns text
language plpgsql volatile security definer set search_path = '' as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  c text;
begin
  loop
    c := 'RUG';
    for i in 1..5 loop
      c := c || substr(alphabet, 1 + get_byte(extensions.gen_random_bytes(1), 0) % 32, 1);
    end loop;
    exit when not exists (select 1 from public.profiles where billing_code = c);
  end loop;
  return c;
end $$;
revoke execute on function public.new_billing_code() from public, anon, authenticated;

-- A profile becomes a landlord → payment code + free trial (once)
create or replace function public.landlord_billing_defaults() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.role = 'landlord' then
    if new.billing_code is null then new.billing_code := public.new_billing_code(); end if;
    if new.subscription_until is null then
      new.subscription_until := public.kampala_today() + (select trial_days from public.billing_settings where id = 1);
    end if;
  end if;
  return new;
end $$;
drop trigger if exists profiles_landlord_billing on public.profiles;
create trigger profiles_landlord_billing before insert or update of role on public.profiles
  for each row execute function public.landlord_billing_defaults();

-- Existing landlords: code + free trial from today (one at a time so codes stay unique)
do $$
declare r record;
begin
  for r in select id from public.profiles where role = 'landlord' and (billing_code is null or subscription_until is null) loop
    update public.profiles
    set billing_code = coalesce(billing_code, public.new_billing_code()),
        subscription_until = coalesce(subscription_until, public.kampala_today() + (select trial_days from public.billing_settings where id = 1))
    where id = r.id;
  end loop;
end $$;

-- ── Subscription payments (written only through the functions below) ──
create table if not exists public.subscription_payments (
  id uuid primary key default gen_random_uuid(),
  landlord_id uuid not null references auth.users (id) on delete cascade,
  plan text not null check (plan in ('monthly', 'yearly')),
  months int not null check (months in (1, 12)),
  amount bigint not null check (amount > 0),
  network text not null check (network in ('mtn', 'airtel')),
  sender_phone text not null,
  sender_name text not null,
  reference text not null,
  paid_on date not null,
  status text not null default 'pending' check (status in ('pending', 'confirmed', 'rejected', 'cancelled')),
  period_start date,
  period_end date,
  reviewed_by uuid references auth.users (id) on delete set null,
  reviewed_at timestamptz,
  reject_reason text,
  created_at timestamptz not null default now()
);
create index if not exists subscription_payments_landlord_idx on public.subscription_payments (landlord_id, created_at desc);
create unique index if not exists subscription_payments_one_pending on public.subscription_payments (landlord_id) where status = 'pending';
alter table public.subscription_payments enable row level security;
drop policy if exists "subscription payments own" on public.subscription_payments;
drop policy if exists "subscription payments admin" on public.subscription_payments;
create policy "subscription payments own" on public.subscription_payments for select to authenticated using (landlord_id = auth.uid());
create policy "subscription payments admin" on public.subscription_payments for select to authenticated using (public.is_superadmin());
revoke all on public.subscription_payments from public, anon, authenticated;
grant select on public.subscription_payments to authenticated;
grant all on public.subscription_payments to service_role;

do $$ begin
  alter publication supabase_realtime add table public.subscription_payments;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.billing_settings;
exception when duplicate_object then null; end $$;

-- ── Is this landlord's subscription running today? (non-landlords: always true) ──
create or replace function public.landlord_subscribed(p_user uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select p.role <> 'landlord' or coalesce(p.subscription_until >= public.kampala_today(), false) from public.profiles p where p.id = p_user),
    true);
$$;
revoke execute on function public.landlord_subscribed(uuid) from public, anon;
grant execute on function public.landlord_subscribed(uuid) to authenticated, service_role;

-- ── Ended subscription → the landlord's changes are refused (reading is unaffected) ──
create or replace function public.require_active_subscription() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is not null and not public.landlord_subscribed(auth.uid()) then
    raise exception 'Your Renta UG subscription has ended. Renew it on the Subscription page to keep managing your properties.';
  end if;
  return coalesce(new, old);
end $$;

do $$
declare t text;
begin
  foreach t in array array['properties', 'rentals', 'tenants', 'payments', 'cash_payments', 'landlord_pay_accounts', 'move_out_requests'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_require_subscription', t);
    execute format('create trigger %I before insert or update or delete on public.%I for each row execute function public.require_active_subscription()',
      t || '_require_subscription', t);
  end loop;
end $$;
-- Notices: sending / deleting needs a subscription; marking as read does not
drop trigger if exists notifications_require_subscription on public.notifications;
create trigger notifications_require_subscription before insert or delete on public.notifications
  for each row execute function public.require_active_subscription();

-- ── Landlord: submit a payment they sent ──
create or replace function public.submit_subscription_payment(
  p_plan text, p_network text, p_sender_phone text, p_sender_name text, p_paid_on date default null
) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  s public.billing_settings;
  p record;
  v_paid_on date := coalesce(p_paid_on, public.kampala_today());
  v_phone text := regexp_replace(coalesce(p_sender_phone, ''), '[^0-9+]', '', 'g');
  v_amount bigint;
  v_id uuid;
begin
  select * into p from public.profiles where id = me;
  if p.role is distinct from 'landlord' then raise exception 'Only landlords have a subscription.'; end if;
  if not p.active then raise exception 'This account is suspended. Please contact Renta UG.'; end if;
  if p_plan not in ('monthly', 'yearly') then raise exception 'Choose monthly or yearly.'; end if;
  if p_network not in ('mtn', 'airtel') then raise exception 'Choose MTN or Airtel.'; end if;

  select * into s from public.billing_settings where id = 1;
  if (p_network = 'mtn' and s.mtn_phone is null) or (p_network = 'airtel' and s.airtel_phone is null) then
    raise exception 'Renta UG has not added a number for this network yet.';
  end if;
  if length(right(regexp_replace(v_phone, '\D', '', 'g'), 9)) < 9 then raise exception 'Enter the number you paid from.'; end if;
  if length(trim(coalesce(p_sender_name, ''))) < 3 then raise exception 'Enter the names registered on that number.'; end if;
  if v_paid_on > public.kampala_today() then raise exception 'The payment date cannot be in the future.'; end if;
  if v_paid_on < public.kampala_today() - 30 then raise exception 'That payment date is more than 30 days ago. Contact Renta UG.'; end if;
  if exists (select 1 from public.subscription_payments where landlord_id = me and status = 'pending') then
    raise exception 'You already have a payment waiting to be confirmed.';
  end if;

  v_amount := case p_plan when 'yearly' then s.yearly_price else s.monthly_price end;

  insert into public.subscription_payments (landlord_id, plan, months, amount, network, sender_phone, sender_name, reference, paid_on)
  values (me, p_plan, case p_plan when 'yearly' then 12 else 1 end, v_amount, p_network, v_phone,
          upper(left(trim(p_sender_name), 80)), coalesce(p.billing_code, '—'), v_paid_on)
  returning id into v_id;

  insert into public.staff_notifications (user_id, type, title, body, url)
  select id, 'subscription', 'Subscription payment to confirm',
    format('%s says they sent %s on %s for a %s subscription (reason %s, from %s). Check the money, then confirm it.',
      coalesce(nullif(p.full_name, ''), p.email), public.ugx(v_amount),
      case p_network when 'mtn' then 'MTN' else 'Airtel' end, p_plan, coalesce(p.billing_code, '—'), v_phone),
    '/admin2026/subscriptions'
  from public.profiles where role = 'superadmin';

  return v_id;
end $$;

-- ── Landlord: withdraw a payment that is still waiting ──
create or replace function public.cancel_subscription_payment(p_id uuid) returns void
language plpgsql volatile security definer set search_path = '' as $$
begin
  update public.subscription_payments set status = 'cancelled', reviewed_at = now()
  where id = p_id and landlord_id = auth.uid() and status = 'pending';
  if not found then raise exception 'There is no waiting payment to cancel.'; end if;
end $$;

-- ── Main admin: confirm → extend the subscription on top of any time left ──
create or replace function public.admin_confirm_subscription_payment(p_id uuid) returns json
language plpgsql volatile security definer set search_path = '' as $$
declare
  r public.subscription_payments;
  p record;
  v_start date;
  v_end date;
begin
  perform public.admin_require();
  select * into r from public.subscription_payments where id = p_id for update;
  if not found then raise exception 'Payment not found.'; end if;
  if r.status <> 'pending' then raise exception 'This payment has already been %.', r.status; end if;
  select * into p from public.profiles where id = r.landlord_id for update;

  v_start := case when p.subscription_until >= public.kampala_today() then p.subscription_until + 1 else public.kampala_today() end;
  v_end := (v_start + make_interval(months => r.months) - interval '1 day')::date;

  update public.profiles set subscription_until = v_end, subscription_plan = r.plan where id = r.landlord_id;
  update public.subscription_payments
  set status = 'confirmed', period_start = v_start, period_end = v_end, reviewed_by = auth.uid(), reviewed_at = now()
  where id = r.id;

  insert into public.staff_notifications (user_id, type, title, body, url)
  values (r.landlord_id, 'subscription', 'Subscription renewed',
    format('Thank you! Your %s payment of %s was received. Your Renta UG subscription now runs until %s.',
      r.plan, public.ugx(r.amount), to_char(v_end, 'FMDD Mon YYYY')),
    '/landlord/subscription');
  perform public.admin_log('subscription.confirm', 'landlord', r.landlord_id,
    format('Confirmed %s %s subscription from %s, now runs to %s', public.ugx(r.amount), r.plan,
      coalesce(nullif(p.full_name, ''), p.email), to_char(v_end, 'FMDD Mon YYYY')));
  return json_build_object('until', v_end, 'start', v_start);
end $$;

-- ── Main admin: reject (the money did not arrive) ──
create or replace function public.admin_reject_subscription_payment(p_id uuid, p_reason text default null) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  r public.subscription_payments;
  v_reason text := nullif(trim(p_reason), '');
begin
  perform public.admin_require();
  select * into r from public.subscription_payments where id = p_id for update;
  if not found then raise exception 'Payment not found.'; end if;
  if r.status <> 'pending' then raise exception 'This payment has already been %.', r.status; end if;
  update public.subscription_payments
  set status = 'rejected', reject_reason = v_reason, reviewed_by = auth.uid(), reviewed_at = now()
  where id = r.id;
  insert into public.staff_notifications (user_id, type, title, body, url)
  values (r.landlord_id, 'subscription', 'Subscription payment not confirmed',
    format('Your %s payment of %s from %s could not be confirmed%s. Please check it, or contact Renta UG.',
      r.plan, public.ugx(r.amount), to_char(r.paid_on, 'FMDD Mon YYYY'), coalesce(': ' || v_reason, '')),
    '/landlord/subscription');
  perform public.admin_log('subscription.reject', 'landlord', r.landlord_id,
    format('Rejected %s %s subscription payment%s', public.ugx(r.amount), r.plan, coalesce(' (' || v_reason || ')', '')));
end $$;

-- ── Main admin: add free days (goodwill, a payment made another way, a longer trial…) ──
create or replace function public.admin_grant_subscription(p_landlord uuid, p_days int, p_note text default null) returns date
language plpgsql volatile security definer set search_path = '' as $$
declare
  p record;
  v_end date;
begin
  perform public.admin_require();
  if p_days is null or p_days < 1 or p_days > 730 then raise exception 'Choose between 1 and 730 days.'; end if;
  select * into p from public.profiles where id = p_landlord and role = 'landlord' for update;
  if not found then raise exception 'Landlord not found.'; end if;
  v_end := greatest(coalesce(p.subscription_until, public.kampala_today() - 1), public.kampala_today() - 1) + p_days;
  update public.profiles set subscription_until = v_end where id = p_landlord;
  insert into public.staff_notifications (user_id, type, title, body, url)
  values (p_landlord, 'subscription', 'Subscription extended',
    format('Renta UG added %s day%s to your subscription%s. It now runs until %s.',
      p_days, case when p_days = 1 then '' else 's' end, coalesce(': ' || nullif(trim(p_note), ''), ''), to_char(v_end, 'FMDD Mon YYYY')),
    '/landlord/subscription');
  perform public.admin_log('subscription.grant', 'landlord', p_landlord,
    format('Added %s days to %s''s subscription (now to %s)%s', p_days, coalesce(nullif(p.full_name, ''), p.email),
      to_char(v_end, 'FMDD Mon YYYY'), coalesce(': ' || nullif(trim(p_note), ''), '')));
  return v_end;
end $$;

-- ── Main admin: prices, trial, receiving numbers ──
create or replace function public.admin_save_billing_settings(
  p_monthly bigint, p_yearly bigint, p_trial_days int,
  p_mtn_phone text, p_mtn_name text, p_airtel_phone text, p_airtel_name text
) returns void
language plpgsql volatile security definer set search_path = '' as $$
begin
  perform public.admin_require();
  if p_monthly is null or p_monthly < 500 then raise exception 'Enter a monthly price of at least UGX 500.'; end if;
  if p_yearly is null or p_yearly < 500 then raise exception 'Enter a yearly price of at least UGX 500.'; end if;
  if p_trial_days is null or p_trial_days < 0 or p_trial_days > 365 then raise exception 'The free trial must be 0 to 365 days.'; end if;
  if nullif(trim(p_mtn_phone), '') is not null and length(trim(coalesce(p_mtn_name, ''))) < 3 then
    raise exception 'Enter the name MTN shows for that number.';
  end if;
  if nullif(trim(p_airtel_phone), '') is not null and length(trim(coalesce(p_airtel_name, ''))) < 3 then
    raise exception 'Enter the name Airtel shows for that number.';
  end if;
  update public.billing_settings
  set monthly_price = p_monthly, yearly_price = p_yearly, trial_days = p_trial_days,
      mtn_phone = nullif(trim(p_mtn_phone), ''), mtn_name = nullif(upper(trim(p_mtn_name)), ''),
      airtel_phone = nullif(trim(p_airtel_phone), ''), airtel_name = nullif(upper(trim(p_airtel_name)), ''),
      updated_at = now()
  where id = 1;
  perform public.admin_log('billing.settings', 'billing', null,
    format('Subscription prices: %s / month, %s / year, %s-day free trial', public.ugx(p_monthly), public.ugx(p_yearly), p_trial_days));
end $$;

-- ── Daily reminders in the landlord's inbox ──
create or replace function public.send_subscription_reminders() returns integer
language plpgsql volatile security definer set search_path = '' as $$
declare
  today date := public.kampala_today();
  n integer;
begin
  insert into public.staff_notifications (user_id, type, title, body, url)
  select p.id, 'subscription',
    case when d.left_days < 0 then 'Subscription ended' else 'Subscription ending soon' end,
    case
      when d.left_days < 0 then format('Your Renta UG %s ended on %s. You can still see everything, but changes are paused until you renew.',
        case when p.subscription_plan is null then 'free trial' else 'subscription' end, to_char(p.subscription_until, 'FMDD Mon YYYY'))
      when d.left_days = 0 then format('Your Renta UG %s ends today. Renew now to keep managing your properties without a break.',
        case when p.subscription_plan is null then 'free trial' else 'subscription' end)
      else format('Your Renta UG %s ends in %s day%s, on %s. Renew any time: the new period is added on top.',
        case when p.subscription_plan is null then 'free trial' else 'subscription' end,
        d.left_days, case when d.left_days = 1 then '' else 's' end, to_char(p.subscription_until, 'FMDD Mon YYYY'))
    end,
    '/landlord/subscription'
  from public.profiles p
  cross join lateral (select p.subscription_until - today as left_days) d
  where p.role = 'landlord' and p.active and p.subscription_until is not null
    and d.left_days in (7, 3, 1, 0, -1)
    and not exists (
      select 1 from public.staff_notifications x
      where x.user_id = p.id and x.type = 'subscription' and x.title in ('Subscription ending soon', 'Subscription ended')
        and x.created_at > now() - interval '20 hours'
    );
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.send_subscription_reminders() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'renta-subscription-reminders';
    perform cron.schedule('renta-subscription-reminders', '0 6 * * *', 'select public.send_subscription_reminders()');
  end if;
exception when others then null;
end $$;

-- ── Who may call what ──
revoke execute on function public.submit_subscription_payment(text, text, text, text, date) from public, anon;
revoke execute on function public.cancel_subscription_payment(uuid) from public, anon;
revoke execute on function public.admin_confirm_subscription_payment(uuid) from public, anon;
revoke execute on function public.admin_reject_subscription_payment(uuid, text) from public, anon;
revoke execute on function public.admin_grant_subscription(uuid, int, text) from public, anon;
revoke execute on function public.admin_save_billing_settings(bigint, bigint, int, text, text, text, text) from public, anon;
grant execute on function public.submit_subscription_payment(text, text, text, text, date) to authenticated;
grant execute on function public.cancel_subscription_payment(uuid) to authenticated;
grant execute on function public.admin_confirm_subscription_payment(uuid) to authenticated;
grant execute on function public.admin_reject_subscription_payment(uuid, text) to authenticated;
grant execute on function public.admin_grant_subscription(uuid, int, text) to authenticated;
grant execute on function public.admin_save_billing_settings(bigint, bigint, int, text, text, text, text) to authenticated;
