-- Emit a canonical customer change whenever the business-wide outstanding balance changes.
--
-- Credit sales, repayments, and return credit reversals update customers.outstanding_balance
-- inside server-side mutation transactions. Those mutations historically emitted only
-- customer_ledger events, so another device could receive the ledger change but never
-- receive the authoritative customer balance. Keep the balance itself as the single
-- source of truth and make every balance mutation automatically enter sync_changes.

create or replace function public.emit_customer_balance_sync_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.outstanding_balance is distinct from old.outstanding_balance then
    perform public._fulus_append_change(
      new.business_id,
      'customer',
      new.id,
      'upsert',
      to_jsonb(new)
    );
  end if;
  return new;
end;
$function$;

revoke execute on function public.emit_customer_balance_sync_change()
from public, anon, authenticated;

drop trigger if exists customers_balance_sync_change_trigger on public.customers;

create trigger customers_balance_sync_change_trigger
after update of outstanding_balance on public.customers
for each row
execute function public.emit_customer_balance_sync_change();

alter function public.emit_customer_balance_sync_change() set search_path = '';
