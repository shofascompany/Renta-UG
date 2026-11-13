-- 14 · tenant records
-- When a landlord ends a tenancy, the tenant moves to "Records": property_id becomes null,
-- and we remember which house they were in and when they left. All their payments,
-- notifications and alerts are kept. They can be added back later with history intact.
-- Safe to run on its own on an existing database (no data is deleted).

alter table public.tenants
  add column if not exists last_property_id uuid references public.properties (id) on delete set null,
  add column if not exists ended_at timestamptz;

-- Existing former tenants: work out their last house from their latest rent charge.
update public.tenants t
set last_property_id = (
  select p.property_id from public.payments p
  where p.tenant_id = t.id and p.property_id is not null
  order by p.period desc
  limit 1
)
where t.property_id is null and t.last_property_id is null;
