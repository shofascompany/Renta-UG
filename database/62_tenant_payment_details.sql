-- 62 · a tenant's mobile money payment: the number and the registered name they paid from (safe to run again)
--
--  Renta UG has no payment provider: it cannot see mobile money. The tenant pays from their own phone, then submits
--  the number they paid from and the name registered to it. Both are TYPED BY THE TENANT and NOT CHECKED by anyone:
--  the landlord checks the money against their own MTN / Airtel messages before approving. Nothing is credited until
--  the landlord approves (confirm_cash_payment, as before).
--    cash_payments.payer_phone   the number the tenant says they paid from (international format)
--    cash_payments.payer_name    the name the tenant says is registered to it (not verified)

alter table public.cash_payments add column if not exists payer_phone text;
alter table public.cash_payments add column if not exists payer_name text;
comment on column public.cash_payments.payer_phone is 'Typed by the tenant, not verified';
comment on column public.cash_payments.payer_name is 'Typed by the tenant, not verified';

create or replace function public.submit_mobile_payment(
  p_amount bigint,
  p_network text,
  p_payer_phone text,
  p_payer_name text
) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_digits text := regexp_replace(coalesce(p_payer_phone, ''), '\D', '', 'g');
  v_phone text;
  v_name text := upper(regexp_replace(trim(coalesce(p_payer_name, '')), '\s+', ' ', 'g'));
  v_id uuid;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role = 'tenant') then
    raise exception 'Only tenants can submit a mobile money payment here.';
  end if;
  -- A Ugandan mobile number: 07XXXXXXXX, 7XXXXXXXX or 2567XXXXXXXX
  if v_digits ~ '^0?7\d{8}$' then v_phone := '+256' || right(v_digits, 9);
  elsif v_digits ~ '^2567\d{8}$' then v_phone := '+' || v_digits;
  else raise exception 'Enter the Ugandan mobile money number you paid from, for example 0772 123 456.';
  end if;
  if array_length(array_remove(string_to_array(v_name, ' '), ''), 1) is null
     or (select count(*) from unnest(string_to_array(v_name, ' ')) w where length(w) >= 2) < 2 then
    raise exception 'Enter the name registered to that number (at least two names).';
  end if;
  if length(v_name) > 80 then raise exception 'That name is too long.'; end if;

  v_id := public.submit_payment(
    null, p_amount, null,
    format('Sent from %s, registered to %s (given by the tenant, not checked)', v_phone, v_name),
    'mobile_money', p_network);
  update public.cash_payments set payer_phone = v_phone, payer_name = v_name where id = v_id;
  return v_id;
end $$;

revoke execute on function public.submit_mobile_payment(bigint, text, text, text) from public, anon;
grant execute on function public.submit_mobile_payment(bigint, text, text, text) to authenticated;
