-- 54 · what the browser may write (safe to run again; no data is deleted)
--
--  The app talks to the database straight from the browser. Row rules (08) already stop anyone touching
--  another person's rows; this file also limits WHICH columns and values a signed-in user can write, so
--  nobody can edit the database through the browser beyond what the app itself does:
--   • Rent months, payments and receipts: written only by the database functions (confirming a payment,
--     recording cash…). A landlord can no longer insert, change or delete them directly.
--   • Tenants: only the fields the app edits (name, email, phone, house, managed / ended). Rental time
--     (lease dates), the linked app account and the connection code are set by the database only.
--   • Notices from a landlord: always a plain "general" notice, 1–1,000 characters. Nobody can fake a
--     "payment confirmation" or a security alert.
--   • Sensible sizes for names, phone numbers, addresses and rents.
--  Database functions (security definer) and the server are not affected.

-- ── Rent months, payments, receipts: database functions only ──
revoke insert, update, delete on public.payments from anon, authenticated;
revoke insert, update, delete on public.payment_receipts from anon, authenticated;

-- ── Tenants: only the fields the app edits ──
revoke insert, update on public.tenants from anon, authenticated;
grant insert (full_name, email, phone, property_id, managed_by_landlord) on public.tenants to authenticated;
grant update (full_name, email, phone, property_id, last_property_id, ended_at, managed_by_landlord) on public.tenants to authenticated;

-- ── Notices written from the app ──
revoke insert on public.notifications from anon, authenticated;
grant insert (tenant_id, type, title, body) on public.notifications to authenticated;

create or replace function public.guard_app_notice() returns trigger
language plpgsql set search_path = '' as $$
begin
  -- Only writes made directly from the browser; database functions run as the owner and are not limited
  if current_user in ('authenticated', 'anon') then
    new.type := 'general';
    new.title := left(trim(coalesce(new.title, '')), 120);
    new.body := trim(coalesce(new.body, ''));
    if length(new.body) < 1 or length(new.body) > 1000 then
      raise exception 'Write a message of up to 1,000 characters.';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists notifications_guard_app on public.notifications;
create trigger notifications_guard_app
  before insert on public.notifications
  for each row execute function public.guard_app_notice();

-- ── Sensible sizes (checked for new and changed rows; old rows are left as they are) ──
do $$
declare c text[];
begin
  foreach c slice 1 in array array[
    array['properties', 'properties_rent_range', 'check (rent is null or (rent >= 0 and rent <= 100000000000))'],
    array['properties', 'properties_name_length', 'check (char_length(name) between 1 and 120)'],
    array['properties', 'properties_location_length', 'check (location is null or char_length(location) <= 200)'],
    array['rentals', 'rentals_name_length', 'check (char_length(name) between 1 and 120)'],
    array['rentals', 'rentals_location_length', 'check (location is null or char_length(location) <= 200)'],
    array['tenants', 'tenants_name_length', 'check (char_length(full_name) between 1 and 120)'],
    array['tenants', 'tenants_email_length', 'check (email is null or char_length(email) <= 254)'],
    array['tenants', 'tenants_phone_length', 'check (phone is null or char_length(phone) <= 30)'],
    array['profiles', 'profiles_name_length', 'check (full_name is null or char_length(full_name) <= 120)'],
    array['profiles', 'profiles_phone_length', 'check (phone is null or char_length(phone) <= 30)'],
    array['landlord_pay_accounts', 'pay_accounts_name_length', 'check (char_length(account_name) between 1 and 80)'],
    array['landlord_pay_accounts', 'pay_accounts_phone_length', 'check (char_length(phone) between 9 and 20)']
  ] loop
    begin
      execute format('alter table public.%I add constraint %I %s not valid', c[1], c[2], c[3]);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;
