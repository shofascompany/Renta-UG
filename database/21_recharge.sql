-- 21 · recharge (pay rent in advance)
-- A tenant can pay any unpaid rent PLUS 1–12 months ahead in ONE mobile money payment.
-- The server records it as one momo attempt with `advance_months` set. Only after the payment
-- is verified does it create the rent charges for the months ahead and pay everything off,
-- oldest first. A failed or cancelled payment leaves nothing behind.
-- Safe to run more than once.

-- A recharge may not be tied to one existing rent charge (there may be none yet)
alter table public.momo_attempts alter column payment_id drop not null;

alter table public.momo_attempts add column if not exists advance_months int;
alter table public.momo_attempts drop constraint if exists momo_attempts_advance_months_check;
alter table public.momo_attempts add constraint momo_attempts_advance_months_check
  check (advance_months is null or advance_months between 1 and 12);

create index if not exists momo_attempts_tenant_pending_idx on public.momo_attempts (tenant_id) where status = 'pending';
