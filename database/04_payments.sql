-- 04 · payments
-- One rent charge per tenant per month. Starts as 'pending'; becomes 'paid' when fully paid by mobile
-- money (verified by the server) or cash recorded by the landlord (part payments: see 17).
-- "Overdue" is not stored: the app derives it from due_date.

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  landlord_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  property_id uuid references public.properties (id) on delete set null,
  period text not null check (period ~ '^\d{4}-\d{2}$'), -- YYYY-MM
  amount bigint not null check (amount > 0),             -- whole UGX
  due_date date not null,
  status text not null default 'pending' check (status in ('pending', 'paid')),
  paid_at timestamptz,
  method text,     -- MTN Mobile Money, Airtel Money, Cash
  reference text,  -- mobile money transaction reference
  created_at timestamptz not null default now(),
  unique (tenant_id, period)
);

create index payments_landlord_id_idx on public.payments (landlord_id);
create index payments_tenant_id_idx on public.payments (tenant_id);
