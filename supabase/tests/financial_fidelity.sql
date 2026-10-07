-- Financial fidelity contract tests.
-- Run with a privileged SQL role against a test/branch database.

do $$
declare
  sale_sig text := 'public.fulus_api_create_sale_atomic_v2(uuid,uuid,uuid,uuid,text,timestamptz,numeric,numeric,numeric,text,text,uuid,jsonb,jsonb)';
  return_sig text := 'public.fulus_api_create_return_atomic_v2(uuid,uuid,uuid,text,text,numeric,text,uuid,jsonb)';
  income_scale int;
  income_precision int;
  return_def text;
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

  -- The service-role Edge Function passes the verified user explicitly.
  -- The return RPC must bind that actor before calling has_permission(),
  -- otherwise auth.uid() resolves to the service actor and every legitimate
  -- return sync is rejected with 42501.
  if position('set_config(''request.jwt.claim.sub'',target_user_id::text,true)' in pg_get_functiondef(to_regprocedure(return_sig))) = 0 then
    raise exception 'return RPC must bind target_user_id to auth.uid() before permission checks';
  end if;

  -- A credit-method return must settle one customer-ledger reversal.
  -- Keep the contract assertion structural: the authoritative return RPC must
  -- contain the credit-method branch and the ledger settlement statement.
  -- Avoid parsing function text with substring arithmetic in CI, because the
  -- PostgreSQL parser treats that syntax differently across supported versions.
  return_def := pg_get_functiondef(to_regprocedure(return_sig));
    if return_def !~* 'method[[:space:]]*=[[:space:]]*''credit''' then
      raise exception 'return RPC is missing the credit-method branch';
    end if;
    if position('insert into public.customer_ledger_entries' in return_def) = 0 then
      raise exception 'return RPC is missing customer ledger settlement';
    end if;

  -- Money wire contract: monetary JSON must be a decimal string, never a
  -- JSON number whose integer form is ambiguous at the mobile boundary.
  if public._fulus_money_wire_jsonb(
    '{"selling_price":300,"amount":300.50,"quantity":100}'::jsonb
  ) <> '{"selling_price":"300.00","amount":"300.50","quantity":100}'::jsonb then
    raise exception 'strict money wire normalizer returned an unexpected shape';
  end if;

  if position(
    'public._fulus_money_wire_jsonb(v_snapshot)'
    in pg_get_functiondef(
      'public.build_fulus_restore_snapshot(uuid,uuid)'::regprocedure
    )
  ) = 0 then
    raise exception 'full restore snapshot is not protected by the strict money wire boundary';
  end if;

  if position(
    'public._fulus_money_wire_jsonb(v_snapshot)'
    in pg_get_functiondef(
      'public.build_fulus_employee_restore_snapshot(uuid,uuid)'::regprocedure
    )
  ) = 0 then
    raise exception 'employee restore snapshot is not protected by the strict money wire boundary';
  end if;

end $$;
