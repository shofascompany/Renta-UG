-- 37 · email verification codes for new sign-ups
--
-- A new person fills in the sign-up form; the server emails them a 6-character code (letters and
-- numbers) that works for 20 minutes. The account is only created once the right code is entered, so
-- nobody can register with an email they don't own. This table holds the waiting sign-ups.
--
-- It is only ever read and written by the server (service role). Nobody can read it from the app.
-- Safe to run more than once.

create table if not exists public.email_verifications (
  email text primary key,
  full_name text not null,
  password_enc text not null, -- encrypted by the server; removed as soon as the account is created
  code_hash text not null,
  expires_at timestamptz not null,
  attempts int not null default 0,
  sent_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table public.email_verifications enable row level security; -- no policies = closed to the app
revoke all on public.email_verifications from public, anon, authenticated;

-- Tidy up expired sign-ups every hour (pg_cron is already used for the reminders)
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'renta-clean-email-verifications';
    perform cron.schedule('renta-clean-email-verifications', '17 * * * *',
      $job$delete from public.email_verifications where expires_at < now() - interval '1 hour'$job$);
  end if;
exception when others then
  null; -- cleaning up is optional: the server also removes expired rows itself
end $$;
