-- 26 · rentals (a business with several rooms / houses)
-- A landlord can own a rental (e.g. "Kira Rentals") and choose how many rooms it has.
-- Each room is an ordinary row in properties (so tenants, rent charges and payments work as before),
-- linked to its rental with properties.rental_id. Rooms can be renamed and each can have its own rent.
-- Safe to run more than once.

create table if not exists public.rentals (
  id uuid primary key default gen_random_uuid(),
  landlord_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  location text not null default '',
  type text not null default 'Rooms',
  created_at timestamptz not null default now()
);

create index if not exists rentals_landlord_id_idx on public.rentals (landlord_id);

-- Deleting a rental deletes its rooms (the app blocks it while rooms still have tenants)
alter table public.properties add column if not exists rental_id uuid references public.rentals (id) on delete cascade;
create index if not exists properties_rental_id_idx on public.properties (rental_id);

alter table public.rentals enable row level security;

drop policy if exists "rentals landlord" on public.rentals;
drop policy if exists "rentals superadmin read" on public.rentals;

create policy "rentals landlord" on public.rentals for all to authenticated
  using (public.is_landlord() and landlord_id = auth.uid())
  with check (public.is_landlord() and landlord_id = auth.uid());
create policy "rentals superadmin read" on public.rentals for select to authenticated
  using (public.is_superadmin());

grant select, insert, update, delete on public.rentals to authenticated;
grant all on public.rentals to service_role; -- the server (notifications, app access) reads rental names

-- A tenant in a room can see the name of the rental it belongs to ("Room 3 · Kira Rentals")
create or replace function public.my_rental_id() returns uuid
language sql stable security definer set search_path = '' as $$
  select p.rental_id from public.tenants t join public.properties p on p.id = t.property_id where t.user_id = auth.uid();
$$;
revoke execute on function public.my_rental_id() from public, anon;
grant execute on function public.my_rental_id() to authenticated;

drop policy if exists "rentals tenant read" on public.rentals;
create policy "rentals tenant read" on public.rentals for select to authenticated
  using (id = public.my_rental_id());

-- Live updates when rooms / rentals change (another device of the same landlord, or the tenant's view)
do $$
declare t text;
begin
  foreach t in array array['properties', 'rentals'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;
