-- 11 · backfill profiles
-- Gives a profile to any login account that existed before the tables were (re)created,
-- so people who already signed up can still sign in. Safe to run any time.

insert into public.profiles (id, email, full_name)
select u.id, u.email, coalesce(u.raw_user_meta_data ->> 'full_name', split_part(u.email, '@', 1))
from auth.users u
on conflict (id) do nothing;
