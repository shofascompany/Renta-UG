-- 27 · a tenant lives in ONE house / room at a time
-- Blocks adding (or moving) a tenant into a house while the same person — same app account,
-- same email or same phone number (last 9 digits) — is already renting another house or room,
-- with this landlord or any other. Former stays (property_id is null) don't count.
-- Safe to run more than once.

create or replace function public.check_one_house_per_tenant() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_phone text := right(regexp_replace(coalesce(new.phone, ''), '\D', '', 'g'), 9);
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
      or (length(v_phone) = 9 and right(regexp_replace(coalesce(t.phone, ''), '\D', '', 'g'), 9) = v_phone)
    )
  limit 1;

  if found then
    raise exception '%', format('%s already rents %s. A tenant can only be in one house or room at a time.',
      v_other.full_name, coalesce(v_other.house, 'another house'));
  end if;
  return new;
end $$;

drop trigger if exists tenants_one_house on public.tenants;
create trigger tenants_one_house
  before insert or update of property_id, email, phone, user_id on public.tenants
  for each row execute function public.check_one_house_per_tenant();
