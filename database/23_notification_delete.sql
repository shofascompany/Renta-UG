-- 23 · tenants can delete notifications
-- "Delete" hides the notification for the TENANT only (tenant_hidden = true). The landlord keeps
-- their record of what was sent. Tenants may only change `read` and `tenant_hidden` on their own
-- notifications (the "notifications mark read" policy from 08 limits it to their own rows).
-- Safe to run more than once.

alter table public.notifications add column if not exists tenant_hidden boolean not null default false;

revoke update on public.notifications from anon, authenticated;
grant update (read, tenant_hidden) on public.notifications to authenticated;
