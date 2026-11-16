-- 39 · text messages (SMS) when a landlord confirms a cash payment
-- The server texts the tenant the same message the app shows (tenants with or without a smartphone). These columns remember which notifications were already texted, so nobody
-- gets the same SMS twice. Run once in Supabase → SQL Editor. Safe to run more than once.

alter table public.notifications add column if not exists sms_sent_at timestamptz;
alter table public.notifications add column if not exists sms_error text;

-- Don't text old payment messages when SMS is first switched on
update public.notifications set sms_sent_at = coalesce(sms_sent_at, created_at)
where sms_sent_at is null and type = 'payment';
