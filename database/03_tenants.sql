-- 03 · tenants
-- People renting a property, added by their landlord.
-- The tenant creates their own account, then enters a connection code (valid 20 minutes)
-- that the landlord generates; that fills in `user_id` (see 07_functions.sql).
-- `property_id` is null for former tenants (history is kept).

create table public.tenants (
  id uuid primary key default gen_random_uuid(),
  landlord_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  user_id uuid unique references auth.users (id) on delete set null,
  property_id uuid references public.properties (id) on delete set null,
  full_name text not null,
  email text,
  phone text,
  lease_start date,
  lease_end date,
  connect_code text unique,              -- 6-character code shared with the tenant
  connect_code_expires_at timestamptz,   -- code stops working after this
  last_property_id uuid references public.properties (id) on delete set null, -- house before the tenancy ended
  ended_at timestamptz,                  -- when the tenancy ended (null = current tenant)
  created_at timestamptz not null default now()
);

create unique index tenants_landlord_email_key on public.tenants (landlord_id, lower(email));
create index tenants_landlord_id_idx on public.tenants (landlord_id);
create index tenants_property_id_idx on public.tenants (property_id);
