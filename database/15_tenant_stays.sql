-- 15 · tenant stays
-- Each row in `tenants` is one STAY: one person in one house for one period, with its own
-- payments, notifications and alerts. When a landlord adds a former tenant back, a NEW stay
-- is created (fresh history) and linked to the same person via `person_id`. Old stays stay in
-- Records, separated per house and period.
-- Safe to run on its own on an existing database (no data is deleted).

alter table public.tenants add column if not exists person_id uuid;
update public.tenants set person_id = id where person_id is null;
alter table public.tenants alter column person_id set not null;
create index if not exists tenants_person_id_idx on public.tenants (person_id);

-- A new person's first stay: person_id = its own id
create or replace function public.set_tenant_person_id() returns trigger
language plpgsql as $$
begin
  new.person_id := coalesce(new.person_id, new.id);
  return new;
end $$;

drop trigger if exists tenants_person_id on public.tenants;
create trigger tenants_person_id
  before insert on public.tenants
  for each row execute function public.set_tenant_person_id();

-- The same email may now appear on several (past) stays; only CURRENT tenants must be unique.
drop index if exists public.tenants_landlord_email_key;
create unique index if not exists tenants_current_email_key
  on public.tenants (landlord_id, lower(email))
  where property_id is not null;

-- Landlord: add a former tenant back into a house as a NEW stay.
-- Their app account (if any) moves to the new stay, so their dashboard starts fresh.
create or replace function public.readd_tenant(
  p_former_id uuid,
  p_property_id uuid,
  p_full_name text,
  p_email text,
  p_phone text,
  p_lease_start date,
  p_lease_end date
) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_person uuid;
  v_email text;
  v_user uuid;
  v_new uuid;
begin
  if not public.is_landlord() then
    raise exception 'Only landlords can add tenants.';
  end if;

  select person_id, email into v_person, v_email
  from public.tenants
  where id = p_former_id and landlord_id = auth.uid();
  if v_person is null then
    raise exception 'Former tenant not found.';
  end if;

  if exists (select 1 from public.tenants where person_id = v_person and property_id is not null) then
    raise exception 'This tenant is already renting one of your houses.';
  end if;
  if not public.owns_property(p_property_id) then
    raise exception 'House not found.';
  end if;
  if exists (select 1 from public.tenants where property_id = p_property_id) then
    raise exception 'That house already has a tenant.';
  end if;

  -- Move the app account link from the old stay(s) to the new one
  select user_id into v_user from public.tenants where person_id = v_person and user_id is not null limit 1;
  update public.tenants set user_id = null where person_id = v_person and user_id is not null;

  insert into public.tenants (landlord_id, person_id, user_id, property_id, full_name, email, phone, lease_start, lease_end)
  values (
    auth.uid(), v_person, v_user, p_property_id,
    p_full_name, coalesce(nullif(lower(trim(p_email)), ''), v_email), nullif(trim(p_phone), ''),
    p_lease_start, p_lease_end
  )
  returning id into v_new;

  return v_new;
end $$;

revoke execute on function public.readd_tenant(uuid, uuid, text, text, text, date, date) from public, anon;
grant execute on function public.readd_tenant(uuid, uuid, text, text, text, date, date) to authenticated;
