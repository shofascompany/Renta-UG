-- 00 · reset
-- ⚠ Deletes ALL Renta tables and their data (properties, tenants, payments, notifications,
-- alerts, profiles). Login accounts in Supabase Auth are kept.

drop trigger if exists on_auth_user_created on auth.users;

drop table if exists
  public.staff_notifications,
  public.payment_receipts,
  public.momo_attempts,
  public.push_subscriptions,
  public.alerts,
  public.notifications,
  public.payments,
  public.tenants,
  public.properties,
  public.profiles
cascade;

drop function if exists public.handle_new_user() cascade;
drop function if exists public.link_tenant_user() cascade;
drop function if exists public.new_connect_code(uuid) cascade;
drop function if exists public.redeem_connect_code(text) cascade;
drop function if exists public.complete_password_setup() cascade;
drop function if exists public.send_lease_reminders() cascade;
drop function if exists public.record_cash_payment(uuid, bigint, timestamptz, text) cascade;
drop function if exists public.save_push_subscription(text, text, text) cascade;
drop function if exists public.delete_push_subscription(text) cascade;
drop function if exists public.readd_tenant(uuid, uuid, text, text, text, date, date) cascade;
drop function if exists public.set_tenant_person_id() cascade;
drop function if exists public.my_property_id() cascade;
drop function if exists public.my_landlord_id() cascade;
drop function if exists public.owns_property(uuid) cascade;
drop function if exists public.owns_tenant(uuid) cascade;
drop function if exists public.is_admin() cascade;
drop function if exists public.is_superadmin() cascade;
drop function if exists public.is_landlord() cascade;
drop function if exists public.my_tenant_id() cascade;
