-- 35 · keep the numbers in agreement
-- Every amount paid on a rent month must have a matching payment record (payment_receipts), because
-- Transactions, the admin statistics and the landlord reports add up the records. Older payments made
-- before payment records existed are filled in here with the method, reference and date the rent month
-- already has. Only the missing difference is added, so running this again changes nothing.
-- Safe to run more than once. No data is deleted.

insert into public.payment_receipts (payment_id, tenant_id, landlord_id, amount, method, reference, note, received_at)
select p.id, p.tenant_id, p.landlord_id,
       p.amount_paid - coalesce(r.total, 0),
       coalesce(nullif(p.method, ''), 'Payment'),
       p.reference,
       'Recorded before payment records existed',
       coalesce(p.paid_at, p.created_at, now())
from public.payments p
left join (select payment_id, sum(amount) as total from public.payment_receipts group by payment_id) r on r.payment_id = p.id
where p.amount_paid > coalesce(r.total, 0);
