-- 60 · accounts that are signed in, with their information (safe to run again; no data is changed)
--
--  For the main admin's Downloads & visits page. Read from the sign-in system itself (auth.sessions): an account is
--  signed in when it has a session that was not signed out and has not expired. Never returned: passwords, sign-in
--  tokens, IP addresses.

create or replace function public.admin_signed_in() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_sessions jsonb;
  v_known boolean := true;
begin
  if not public.is_superadmin() then raise exception 'Only the main admin can see this.'; end if;

  begin
    execute $q$
      select coalesce(jsonb_object_agg(x.user_id, x.list), '{}') from (
        select s.user_id, jsonb_agg(jsonb_build_object(
          'signedInAt', s.created_at,
          'lastActive', greatest(s.created_at, s.updated_at, s.refreshed_at at time zone 'UTC'),
          'agent', left(s.user_agent, 300)
        ) order by greatest(s.created_at, s.updated_at, s.refreshed_at at time zone 'UTC') desc) as list
        from auth.sessions s
        where s.not_after is null or s.not_after > now()
        group by s.user_id) x $q$ into v_sessions;
  exception when others then
    -- The sessions could not be read here: accounts that have signed in before are listed, and the page says so
    v_known := false;
    v_sessions := '{}';
  end;

  return jsonb_build_object(
    'known', v_known,
    'accounts', coalesce((
      select jsonb_agg(a.info order by a.active_at desc nulls last)
      from (
        select z.active_at, jsonb_build_object(
          'id', p.id, 'name', p.full_name, 'role', p.role, 'phone', p.phone,
          'email', case when p.email like '%@phone-signin.example.com' then null else p.email end,
          'enabled', coalesce(p.active, true), 'ready', not coalesce(p.must_change_password, false),
          'joinedAt', p.created_at, 'lastSignInAt', z.last_sign_in_at, 'lastActive', z.active_at,
          'sessions', z.sessions,
          'appDevices', coalesce((select jsonb_agg(jsonb_build_object('device', d.device, 'source', d.source, 'firstAt', d.first_at, 'lastAt', d.last_at) order by d.last_at desc)
                                  from public.app_devices d where d.user_id = p.id), '[]'),
          'webVisits', (select count(*) from public.site_visits v where v.user_id = p.id),
          'lastWebVisit', (select max(v.at) from public.site_visits v where v.user_id = p.id),
          'stars', (select r.stars from public.app_ratings r where r.user_id = p.id),
          'landlord', case when p.role = 'landlord' then jsonb_build_object(
            'plan', p.subscription_plan, 'tier', p.subscription_tier, 'until', p.subscription_until,
            'exempt', p.subscription_exempt, 'plannedUnits', p.planned_units,
            'rentals', (select count(*) from public.rentals x where x.landlord_id = p.id),
            'places', (select count(*) from public.properties x where x.landlord_id = p.id),
            'tenants', (select count(*) from public.tenants x where x.landlord_id = p.id and x.property_id is not null),
            'collected', (select coalesce(sum(x.amount), 0) from public.payment_receipts x where x.landlord_id = p.id),
            'unpaid', (select coalesce(sum(x.amount - x.amount_paid), 0) from public.payments x where x.landlord_id = p.id and x.status <> 'paid')
          ) end,
          'tenant', case when p.role = 'tenant' then (
            select jsonb_build_object(
              'id', t.id, 'renting', t.property_id is not null,
              'place', h.name, 'rental', b.name, 'location', h.location, 'rent', h.rent,
              'leaseStart', t.lease_start, 'leaseEnd', t.lease_end, 'endedAt', t.ended_at,
              'landlordId', t.landlord_id, 'landlordName', l.full_name, 'landlordPhone', l.phone,
              'paid', (select coalesce(sum(x.amount), 0) from public.payment_receipts x where x.tenant_id = t.id),
              'unpaid', (select coalesce(sum(x.amount - x.amount_paid), 0) from public.payments x where x.tenant_id = t.id and x.status <> 'paid')
            )
            from public.tenants t
            left join public.properties h on h.id = coalesce(t.property_id, t.last_property_id)
            left join public.rentals b on b.id = h.rental_id
            left join public.profiles l on l.id = t.landlord_id
            where t.user_id = p.id
            order by t.property_id is null, t.created_at desc limit 1
          ) end
        ) as info
        from public.profiles p
        join lateral (
          select u.last_sign_in_at, coalesce(v_sessions -> p.id::text, '[]') as sessions,
                 coalesce((v_sessions -> p.id::text -> 0 ->> 'lastActive')::timestamptz, u.last_sign_in_at) as active_at
          from auth.users u where u.id = p.id
        ) z on true
        where case when v_known then v_sessions ? p.id::text else z.last_sign_in_at is not null end
        order by z.active_at desc nulls last
        limit 500
      ) a
    ), '[]'),
    'total', case when v_known then (select count(*) from public.profiles p where v_sessions ? p.id::text)
                  else (select count(*) from public.profiles p join auth.users u on u.id = p.id where u.last_sign_in_at is not null) end
  );
end $$;

revoke execute on function public.admin_signed_in() from public, anon;
grant execute on function public.admin_signed_in() to authenticated;
