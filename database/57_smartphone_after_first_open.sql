-- 57 · a tenant without a smartphone becomes a smartphone tenant when they FIRST OPEN THEIR DASHBOARD
--      (safe to run again; no data is deleted)
--
--  Giving app access only creates their login; they stay "no smartphone" (managed_by_landlord = true) until they
--  really open their dashboard in the app:
--   • mark_dashboard_opened()   called by the tenant's dashboard, switches them over once
--   • change_managed_phone()    until then their landlord can still correct the phone number they sign in with
--   • one house per tenant (27) now compares the whole phone number, not the last 9 digits (see 56)

create or replace function public.mark_dashboard_opened() returns boolean
language plpgsql volatile security definer set search_path = '' as $$
begin
  -- Only once their own account is set up (email + password chosen)
  if not exists (select 1 from public.profiles where id = auth.uid() and role = 'tenant' and not must_change_password) then
    return false;
  end if;
  update public.tenants set managed_by_landlord = false
  where user_id = auth.uid() and property_id is not null and managed_by_landlord;
  return found;
end $$;
revoke execute on function public.mark_dashboard_opened() from public, anon;
grant execute on function public.mark_dashboard_opened() to authenticated;

create or replace function public.change_managed_phone(p_tenant_id uuid, p_phone text) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  t public.tenants%rowtype;
  v_phone text := nullif(btrim(p_phone), '');
begin
  if not public.is_landlord() then
    raise exception 'Only landlords can do this.';
  end if;
  select * into t from public.tenants where id = p_tenant_id and landlord_id = auth.uid() for update;
  if not found or t.managed_by_landlord is not true then
    raise exception 'Only the number of a tenant without a smartphone can be changed here.';
  end if;
  if public.phone_key(v_phone) = '' or char_length(v_phone) > 30 then
    raise exception 'Enter a valid phone number.';
  end if;

  if t.user_id is not null then
    -- Their login exists: allowed only while it has never been set up by the tenant
    if not exists (
      select 1 from public.profiles p
      where p.id = t.user_id and p.role = 'tenant' and p.must_change_password and p.email like '%@phone-signin.example.com'
    ) then
      raise exception 'This tenant has already set up their account. They change their number in their own settings.';
    end if;
    if exists (
      select 1 from public.profiles p
      where p.id <> t.user_id and public.phone_key(p.phone) = public.phone_key(v_phone)
    ) then
      raise exception 'This phone number is already used by another Renta account.';
    end if;
    update public.profiles set phone = v_phone where id = t.user_id;
  end if;
  update public.tenants set phone = v_phone where id = t.id;
end $$;
revoke execute on function public.change_managed_phone(uuid, text) from public, anon;
grant execute on function public.change_managed_phone(uuid, text) to authenticated;

create or replace function public.check_one_house_per_tenant() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_key text := public.phone_key(new.phone);
  v_other record;
begin
  if new.property_id is null then
    return new;
  end if;

  select t.full_name, p.name as house into v_other
  from public.tenants t
  left join public.properties p on p.id = t.property_id
  where t.id <> new.id
    and t.property_id is not null
    and (
      (new.user_id is not null and t.user_id = new.user_id)
      or (new.email is not null and new.email not like '%@phone-signin.example.com' and lower(t.email) = lower(new.email))
      or (v_key <> '' and public.phone_key(t.phone) = v_key)
    )
  limit 1;

  if found then
    raise exception '%', format('%s already rents %s. A tenant can only be in one house or room at a time.',
      v_other.full_name, coalesce(v_other.house, 'another house'));
  end if;
  return new;
end $$;
