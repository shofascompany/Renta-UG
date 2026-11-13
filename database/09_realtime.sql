-- 09 · realtime
-- Lets the app receive live updates: notifications, payments, and tenants
-- (so the landlord sees the moment a tenant connects with their code).
-- Safe to run again (skips tables that are already added).

do $$
declare
  t text;
begin
  foreach t in array array['notifications', 'payments', 'tenants'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then
      null; -- already added
    end;
  end loop;
end $$;
