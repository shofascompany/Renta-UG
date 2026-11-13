-- 01 · profiles
-- One row per login account (created automatically on sign-up, see 07_functions.sql).
-- role:
--   superadmin → the main admin from .env (ADMIN_*), signs in at /admin2026, monitors everything
--   landlord   → registered by the main admin, manages their own properties and tenants
--   tenant     → signs up themselves, connects to a landlord with a code

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  full_name text,
  phone text,
  role text not null default 'tenant' check (role in ('superadmin', 'landlord', 'tenant')),
  active boolean not null default true, -- false = landlord suspended by the main admin
  created_at timestamptz not null default now()
);
