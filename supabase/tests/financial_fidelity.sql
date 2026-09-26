-- Financial fidelity contract tests.
-- Run with a privileged SQL role against a test/branch database.

do $$
declare
  sale_sig text := 'public.fulus_api_create_sale_atomic_v2(uuid,uuid,uuid,uuid,text,timestamptz,numeric,numeric,numeric,text,text,uuid,jsonb,jsonb)';
  return_sig text := 'public.fulus_api_create_return_atomic_v2(uuid,uuid,uuid,text,text,numeric,text,uuid,jsonb)';
  income_scale int;
  income_precision int;
begin
  if to_regprocedure(sale_sig) is null then
    raise exception 'Missing split-payment sale RPC: %', sale_sig;
  end if;

  if to_regprocedure(return_sig) is null then
    raise exception 'Missing authoritative return RPC: %', return_sig;
  end if;

  select numeric_precision, numeric_scale
  into income_precision, income_scale
  from information_schema.columns
  where table_schema='public'
    and table_name='income_records'
    and column_name='amount';

  if income_precision <> 14 or income_scale <> 2 then
    raise exception 'income_records.amount must be numeric(14,2), got (% , %)', income_precision, income_scale;
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname='public'
      and tablename='diagnostic_events'
      and policyname='diagnostic_events_client_deny'
  ) then
    raise exception 'diagnostic_events client-deny RLS policy is missing';
  end if;
end $$;
