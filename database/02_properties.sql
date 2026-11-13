-- 02 · properties
-- Houses/units, each owned by a landlord.

create table public.properties (
  id uuid primary key default gen_random_uuid(),
  landlord_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  location text not null,
  type text not null default 'Apartment',
  bedrooms int not null default 1,
  bathrooms int not null default 1,
  rent bigint not null check (rent >= 0), -- monthly rent in whole UGX
  created_at timestamptz not null default now()
);

create index properties_landlord_id_idx on public.properties (landlord_id);
