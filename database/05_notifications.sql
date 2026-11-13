-- 05 · notifications
-- Messages from a landlord (or the system) to one of their tenants.

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  landlord_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  type text not null default 'general' check (type in ('general', 'maintenance', 'payment')),
  title text not null,
  body text not null,
  read boolean not null default false,
  created_at timestamptz not null default now()
);

create index notifications_landlord_id_idx on public.notifications (landlord_id);
create index notifications_tenant_id_idx on public.notifications (tenant_id);
