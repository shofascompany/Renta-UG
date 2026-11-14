-- 00 · reset
-- ⚠ Deletes ALL Renta tables and their data (properties, tenants, payments, notifications,
-- alerts, profiles). Login accounts in Supabase Auth are kept.

drop trigger if exists on_auth_user_created on auth.users;

drop table if exists
  public.platform_archives,
  public.admin_audit,
  public.move_out_requests,
  public.staff_notifications,
  public.payment_receipts,
  public.momo_attempts,
  public.push_subscriptions,
  public.alerts,
  public.notifications,
  public.payments,
  public.tenants,
  public.properties,
  public.rentals,
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
drop function if exists public.check_one_house_per_tenant() cascade;
drop function if exists public.my_rental_id() cascade;
drop function if exists public.next_rent_period(uuid) cascade;
drop function if exists public.extend_rental_time() cascade;
drop function if exists public.request_move_out(int, text, text, text) cascade;
drop function if exists public.cancel_move_out() cascade;
drop function if exists public.decide_move_out(uuid, boolean, text) cascade;
drop function if exists public.finish_move_out() cascade;
drop function if exists public.admin_require() cascade;
drop function if exists public.admin_log(text, text, uuid, text) cascade;
drop function if exists public.admin_update_property(uuid, text, text, bigint) cascade;
drop function if exists public.admin_delete_property(uuid) cascade;
drop function if exists public.admin_update_tenant(uuid, text, text, text) cascade;
drop function if exists public.admin_end_tenancy(uuid, text) cascade;
drop function if exists public.admin_broadcast(text, uuid, text) cascade;
drop function if exists public.admin_note(text, text, uuid, text) cascade;
drop function if exists public.admin_archive_and_clear(uuid, text) cascade;
