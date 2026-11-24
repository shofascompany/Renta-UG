-- 47 · no free trial (safe to run again; no data is deleted)
--
--  A landlord can't use Renta UG until they pay a subscription and the main admin confirms it.
--  • New landlords get their payment reference, but no free days.
--  • Free trials that are running now end (ONCE, the first time this file runs). Days the main admin
--    added by hand later ("Add days") are never touched again.
--  • Until confirmed, every change by the landlord is refused by the database (the app also shows only
--    the Subscription, Inbox and Settings pages).
--  • The permanent free account (subscription_exempt) is not affected.

alter table public.billing_settings add column if not exists trial_removed_at timestamptz;
update public.billing_settings set trial_days = 0 where id = 1;

-- ── New landlords: payment reference only ──
create or replace function public.landlord_billing_defaults() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.role = 'landlord' and new.billing_code is null then
    new.billing_code := public.new_billing_code();
  end if;
  return new;
end $$;

-- ── End the running free trials, once ──
do $$
begin
  if (select trial_removed_at from public.billing_settings where id = 1) is null then
    update public.profiles
    set subscription_until = null
    where role = 'landlord' and subscription_plan is null and not subscription_exempt and subscription_until is not null;
    update public.billing_settings set trial_removed_at = now() where id = 1;
  end if;
end $$;

-- ── Guard: no active subscription → no changes; Small scale → no more than the unit limit ──
create or replace function public.require_active_subscription() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  p record;
  v_max int;
begin
  if auth.uid() is null then return coalesce(new, old); end if;
  if not public.landlord_subscribed(auth.uid()) then
    raise exception 'Your Renta UG subscription is not active. Pay on the Subscription page: your account opens as soon as Renta UG confirms the payment.';
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

-- ── Reminders: no trial wording; an ended subscription locks the account ──
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
      when d.left_days < 0 then format('Your Renta UG subscription ended on %s. Your account is locked until you renew and Renta UG confirms the payment.',
        to_char(p.subscription_until, 'FMDD Mon YYYY'))
      when d.left_days = 0 then 'Your Renta UG subscription ends today. Renew now to keep managing your properties without a break.'
      else format('Your Renta UG subscription ends in %s day%s, on %s. Renew any time: the new period is added on top.',
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
