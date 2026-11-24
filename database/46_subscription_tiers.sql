-- 46 · subscription scales + one permanent free landlord (safe to run again; no data is deleted)
--
--  Two scales, priced by how many houses / rooms a landlord has (all their properties, rooms included):
--    Small scale  UGX 55,000 / month   UGX 650,000 / year    up to small_max_units houses + rooms (default 10)
--    Big scale    UGX 105,000 / month  UGX 1,200,000 / year  any number
--  A landlord with more units than the small limit must choose Big scale, and a Small-scale subscriber
--  can't add houses / rooms beyond the limit (they upgrade to Big scale). The free trial has no limit.
--  Prices and the limit are set by the main admin (Subscriptions → Prices and payment numbers).
--
--  Permanent free landlord: ngumisiriza@gmail.com never pays and is never paused (subscription_exempt).
--  Nobody can switch this on from the app: only this file sets it.

-- ── Prices per scale ──
alter table public.billing_settings add column if not exists small_monthly bigint not null default 55000;
alter table public.billing_settings add column if not exists small_yearly bigint not null default 650000;
alter table public.billing_settings add column if not exists big_monthly bigint not null default 105000;
alter table public.billing_settings add column if not exists big_yearly bigint not null default 1200000;
alter table public.billing_settings add column if not exists small_max_units int not null default 10;

-- ── Landlord: their scale, and the permanent free flag (users can't write these columns) ──
alter table public.profiles add column if not exists subscription_tier text;
alter table public.profiles add column if not exists subscription_exempt boolean not null default false;
do $$ begin
  alter table public.profiles add constraint profiles_subscription_tier_check check (subscription_tier in ('small', 'big'));
exception when duplicate_object then null; end $$;

alter table public.subscription_payments add column if not exists tier text not null default 'small';
do $$ begin
  alter table public.subscription_payments add constraint subscription_payments_tier_check check (tier in ('small', 'big'));
exception when duplicate_object then null; end $$;

-- The one permanent free landlord account
update public.profiles set subscription_exempt = true where lower(email) = 'ngumisiriza@gmail.com';

-- ── Houses + rooms a landlord has ──
create or replace function public.landlord_unit_count(p_user uuid default auth.uid()) returns int
language sql stable security definer set search_path = '' as $$
  select count(*)::int from public.properties where landlord_id = p_user;
$$;
revoke execute on function public.landlord_unit_count(uuid) from public, anon;
grant execute on function public.landlord_unit_count(uuid) to authenticated;

-- ── Subscribed? Permanent free accounts always are ──
create or replace function public.landlord_subscribed(p_user uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select p.role <> 'landlord' or p.subscription_exempt or coalesce(p.subscription_until >= public.kampala_today(), false)
     from public.profiles p where p.id = p_user),
    true);
$$;

-- ── Guard: ended subscription → no changes; Small scale → no more than the unit limit ──
create or replace function public.require_active_subscription() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  p record;
  v_max int;
begin
  if auth.uid() is null then return coalesce(new, old); end if;
  if not public.landlord_subscribed(auth.uid()) then
    raise exception 'Your Renta UG subscription has ended. Renew it on the Subscription page to keep managing your properties.';
  end if;
  if tg_table_name = 'properties' and tg_op = 'INSERT' then
    select role, subscription_exempt, subscription_plan, subscription_tier into p from public.profiles where id = auth.uid();
    if p.role = 'landlord' and not p.subscription_exempt and p.subscription_plan is not null and p.subscription_tier = 'small' then
      select small_max_units into v_max from public.billing_settings where id = 1;
      if public.landlord_unit_count(auth.uid()) >= v_max then
        raise exception 'Small scale covers up to % houses and rooms. Upgrade to Big scale on the Subscription page to add more.', v_max;
      end if;
    end if;
  end if;
  return coalesce(new, old);
end $$;

-- ── Landlord: submit a payment (now with the scale) ──
drop function if exists public.submit_subscription_payment(text, text, text, text, date);
create or replace function public.submit_subscription_payment(
  p_tier text, p_plan text, p_network text, p_sender_phone text, p_sender_name text, p_paid_on date default null
) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  s public.billing_settings;
  p record;
  v_paid_on date := coalesce(p_paid_on, public.kampala_today());
  v_phone text := regexp_replace(coalesce(p_sender_phone, ''), '[^0-9+]', '', 'g');
  v_units int;
  v_amount bigint;
  v_id uuid;
begin
  select * into p from public.profiles where id = me;
  if p.role is distinct from 'landlord' then raise exception 'Only landlords have a subscription.'; end if;
  if p.subscription_exempt then raise exception 'Your account is free for life: there is nothing to pay.'; end if;
  if not p.active then raise exception 'This account is suspended. Please contact Renta UG.'; end if;
  if p_tier not in ('small', 'big') then raise exception 'Choose Small scale or Big scale.'; end if;
  if p_plan not in ('monthly', 'yearly') then raise exception 'Choose monthly or yearly.'; end if;
  if p_network not in ('mtn', 'airtel') then raise exception 'Choose MTN or Airtel.'; end if;

  select * into s from public.billing_settings where id = 1;
  v_units := public.landlord_unit_count(me);
  if p_tier = 'small' and v_units > s.small_max_units then
    raise exception 'You have % houses and rooms. Small scale covers up to %, so please choose Big scale.', v_units, s.small_max_units;
  end if;
  if (p_network = 'mtn' and s.mtn_phone is null) or (p_network = 'airtel' and s.airtel_phone is null) then
    raise exception 'Renta UG has not added a number for this network yet.';
  end if;
  if length(right(regexp_replace(v_phone, '\D', '', 'g'), 9)) < 9 then raise exception 'Enter the number you paid from.'; end if;
  if length(trim(coalesce(p_sender_name, ''))) < 5 or trim(p_sender_name) !~ '\S+\s+\S+' then
    raise exception 'Enter the full names registered on the line you paid from (at least two names).';
  end if;
  if v_paid_on > public.kampala_today() then raise exception 'The payment date cannot be in the future.'; end if;
  if v_paid_on < public.kampala_today() - 30 then raise exception 'That payment date is more than 30 days ago. Contact Renta UG.'; end if;
  if exists (select 1 from public.subscription_payments where landlord_id = me and status = 'pending') then
    raise exception 'You already have a payment waiting to be confirmed.';
  end if;

  v_amount := case
    when p_tier = 'big' and p_plan = 'yearly' then s.big_yearly
    when p_tier = 'big' then s.big_monthly
    when p_plan = 'yearly' then s.small_yearly
    else s.small_monthly end;

  insert into public.subscription_payments (landlord_id, tier, plan, months, amount, network, sender_phone, sender_name, reference, paid_on)
  values (me, p_tier, p_plan, case p_plan when 'yearly' then 12 else 1 end, v_amount, p_network, v_phone,
          upper(left(regexp_replace(trim(p_sender_name), '\s+', ' ', 'g'), 80)), coalesce(p.billing_code, '—'), v_paid_on)
  returning id into v_id;

  insert into public.staff_notifications (user_id, type, title, body, url)
  select id, 'subscription', 'Subscription payment to confirm',
    format('%s says they sent %s on %s for %s scale, %s (reason %s, from %s, registered to %s). Check the money, then confirm it.',
      coalesce(nullif(p.full_name, ''), p.email), public.ugx(v_amount),
      case p_network when 'mtn' then 'MTN' else 'Airtel' end, initcap(p_tier), p_plan, coalesce(p.billing_code, '—'), v_phone,
      upper(trim(p_sender_name))),
    '/admin2026/subscriptions'
  from public.profiles where role = 'superadmin';

  return v_id;
end $$;

-- ── Main admin: confirm → extend on top of any time left, and set the scale ──
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

  update public.profiles set subscription_until = v_end, subscription_plan = r.plan, subscription_tier = r.tier where id = r.landlord_id;
  update public.subscription_payments
  set status = 'confirmed', period_start = v_start, period_end = v_end, reviewed_by = auth.uid(), reviewed_at = now()
  where id = r.id;

  insert into public.staff_notifications (user_id, type, title, body, url)
  values (r.landlord_id, 'subscription', 'Subscription renewed',
    format('Thank you! Your %s scale %s payment of %s was received. Your Renta UG subscription now runs until %s.',
      initcap(r.tier), r.plan, public.ugx(r.amount), to_char(v_end, 'FMDD Mon YYYY')),
    '/landlord/subscription');
  perform public.admin_log('subscription.confirm', 'landlord', r.landlord_id,
    format('Confirmed %s %s scale %s subscription from %s, now runs to %s', public.ugx(r.amount), r.tier, r.plan,
      coalesce(nullif(p.full_name, ''), p.email), to_char(v_end, 'FMDD Mon YYYY')));
  return json_build_object('until', v_end, 'start', v_start);
end $$;

-- ── Main admin: prices per scale, the small-scale limit, trial, receiving numbers ──
drop function if exists public.admin_save_billing_settings(bigint, bigint, int, text, text, text, text);
create or replace function public.admin_save_billing_settings(
  p_small_monthly bigint, p_small_yearly bigint, p_big_monthly bigint, p_big_yearly bigint,
  p_small_max_units int, p_trial_days int,
  p_mtn_phone text, p_mtn_name text, p_airtel_phone text, p_airtel_name text
) returns void
language plpgsql volatile security definer set search_path = '' as $$
begin
  perform public.admin_require();
  if least(p_small_monthly, p_small_yearly, p_big_monthly, p_big_yearly) is null
     or least(p_small_monthly, p_small_yearly, p_big_monthly, p_big_yearly) < 500 then
    raise exception 'Every price must be at least UGX 500.';
  end if;
  if p_small_max_units is null or p_small_max_units < 1 or p_small_max_units > 10000 then raise exception 'Enter how many houses and rooms Small scale covers.'; end if;
  if p_trial_days is null or p_trial_days < 0 or p_trial_days > 365 then raise exception 'The free trial must be 0 to 365 days.'; end if;
  if nullif(trim(p_mtn_phone), '') is not null and length(trim(coalesce(p_mtn_name, ''))) < 3 then
    raise exception 'Enter the name MTN shows for that number.';
  end if;
  if nullif(trim(p_airtel_phone), '') is not null and length(trim(coalesce(p_airtel_name, ''))) < 3 then
    raise exception 'Enter the name Airtel shows for that number.';
  end if;
  update public.billing_settings
  set small_monthly = p_small_monthly, small_yearly = p_small_yearly, big_monthly = p_big_monthly, big_yearly = p_big_yearly,
      small_max_units = p_small_max_units, trial_days = p_trial_days,
      monthly_price = p_small_monthly, yearly_price = p_small_yearly, -- older app versions read these
      mtn_phone = nullif(trim(p_mtn_phone), ''), mtn_name = nullif(upper(trim(p_mtn_name)), ''),
      airtel_phone = nullif(trim(p_airtel_phone), ''), airtel_name = nullif(upper(trim(p_airtel_name)), ''),
      updated_at = now()
  where id = 1;
  perform public.admin_log('billing.settings', 'billing', null,
    format('Subscription prices: small %s / month, %s / year (up to %s units); big %s / month, %s / year; %s-day trial',
      public.ugx(p_small_monthly), public.ugx(p_small_yearly), p_small_max_units, public.ugx(p_big_monthly), public.ugx(p_big_yearly), p_trial_days));
end $$;

-- ── Reminders: never for the permanent free account ──
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
  where p.role = 'landlord' and p.active and not p.subscription_exempt and p.subscription_until is not null
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

revoke execute on function public.submit_subscription_payment(text, text, text, text, text, date) from public, anon;
revoke execute on function public.admin_save_billing_settings(bigint, bigint, bigint, bigint, int, int, text, text, text, text) from public, anon;
grant execute on function public.submit_subscription_payment(text, text, text, text, text, date) to authenticated;
grant execute on function public.admin_save_billing_settings(bigint, bigint, bigint, bigint, int, int, text, text, text, text) to authenticated;
