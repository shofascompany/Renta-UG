-- 64 · a landlord takes back a tenant's app access (safe to run again; no data is deleted)
--
--  The tenant goes back to being a tenant without a smartphone, managed by their landlord: their login is unlinked
--  from the tenant record (managed_by_landlord = true, user_id = null). Rent, payments and notices all stay. Their
--  login itself is kept, so the landlord can give app access again later.

create or replace function public.remove_app_access(p_tenant_id uuid) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  t public.tenants%rowtype;
begin
  if not public.is_landlord() then
    raise exception 'Only landlords can do this.';
  end if;
  select * into t from public.tenants where id = p_tenant_id and landlord_id = auth.uid() for update;
  if not found then raise exception 'Tenant not found.'; end if;
  if t.property_id is null then raise exception 'This tenant no longer rents from you.'; end if;
  update public.tenants set user_id = null, managed_by_landlord = true where id = t.id;
end $$;

revoke execute on function public.remove_app_access(uuid) from public, anon;
grant execute on function public.remove_app_access(uuid) to authenticated;
