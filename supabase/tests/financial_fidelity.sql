-- Financial fidelity contract tests.
-- Run with a privileged SQL role against a test/branch database.

do $$
declare
  sale_sig text := 'public.fulus_api_create_sale_atomic_v2(uuid,uuid,uuid,uuid,text,timestamptz,numeric,numeric,numeric,text,text,uuid,jsonb,jsonb)';
  return_sig text := 'public.fulus_api_create_return_atomic_v2(uuid,uuid,uuid,text,text,numeric,text,uuid,jsonb)';
  return_impl_sig text := 'public.fulus_api_create_return_atomic_v2_unchecked(uuid,uuid,uuid,text,text,numeric,text,uuid,jsonb)';
  return_function_definition text;
  income_scale int;
  income_precision int;
begin
  if to_regprocedure(sale_sig) is null then
    raise exception 'Missing split-payment sale RPC: %', sale_sig;
  end if;

  -- The public authorization wrapper must reject even a one-cent mismatch.
  -- The canonical local contract uses integer cents, and the unchecked RPC
  -- caps sales.amount_paid at total; accepting 10.01 of legs for a 10.00
  -- sale would otherwise record a larger cash-ledger inflow than the sale.
  if position(
    'round(payment_total,2) <> round((result->>''total'')::numeric,2)'
    in pg_get_functiondef(to_regprocedure(sale_sig))
  ) = 0 then
    raise exception 'Sale RPC does not enforce exact payment-total equality';
  end if;
  if position(
    'round(collected_total,2) <> round((result->>''amount_paid'')::numeric,2)'
    in pg_get_functiondef(to_regprocedure(sale_sig))
  ) = 0 then
    raise exception 'Sale RPC does not enforce exact collected-payment equality';
  end if;
  if position(
    'round(credit_total,2) <> round((result->>''balance_due'')::numeric,2)'
    in pg_get_functiondef(to_regprocedure(sale_sig))
  ) = 0 then
    raise exception 'Sale RPC does not enforce exact credit-payment equality';
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

  -- Return amounts must be allocated from the authoritative net sale total,
  -- not raw pre-discount line prices. The function must also cap cumulative
  -- refunds at the sale total so repeated/partial returns cannot over-refund.
  if position('sale.total / sale_subtotal' in pg_get_functiondef(to_regprocedure(return_impl_sig))) = 0 then
    raise exception 'return RPC does not allocate refunds from the net sale total';
  end if;
  if position('previously_refunded' in pg_get_functiondef(to_regprocedure(return_impl_sig))) = 0 then
    raise exception 'return RPC does not cap cumulative refunds against prior returns';
  end if;
  return_function_definition := pg_get_functiondef(to_regprocedure(return_impl_sig));
  if position('weighted_refund_amount' in return_function_definition) = 0
     or position('order by id' in return_function_definition) = 0 then
    raise exception 'return RPC does not deterministically allocate product-only requests across duplicate sale lines';
  end if;
  if position('if credit_reversal > 0 then' in return_function_definition) = 0
     or position('if method<>''credit'' and cash_refund > 0 then' in return_function_definition) = 0 then
    raise exception 'return RPC does not post split-credit reversal and any remaining cash refund';
  end if;

  -- Idempotent replay must be resolved before the refundable-balance guard.
  -- After a successful full return, the sale has no refundable balance left,
  -- but an exact replay must still return the stored idempotency response.
  if position(
    'if idem.completed_at is not null and idem.response_body is not null then'
    in pg_get_functiondef(to_regprocedure(return_impl_sig))
  ) = 0 then
    raise exception 'return RPC is missing completed idempotency replay handling';
  end if;
  if position(
    'if previously_refunded >= greatest(round(coalesce(sale.total,0),2),0) then'
    in pg_get_functiondef(to_regprocedure(return_impl_sig))
  ) <= position(
    'if idem.completed_at is not null and idem.response_body is not null then'
    in pg_get_functiondef(to_regprocedure(return_impl_sig))
  ) then
    raise exception 'return RPC checks refund exhaustion before idempotent replay';
  end if;

  -- Credit-return behavior is covered by the authoritative return RPC
  -- implementation and the customer-ledger mutation contract tests.

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

-- Behavioral regression: exact-cent payment totals succeed, while a one-cent
-- cash overstatement is rejected and all writes from the rejected command
-- (sale, payment, cash ledger, inventory, idempotency, and change feed) roll
-- back together. This file runs only against the disposable local CI DB.
begin;

create temporary table _sale_fidelity_ids (
  user_id uuid not null,
  business_id uuid not null,
  location_id uuid not null,
  product_id uuid not null,
  customer_id uuid not null,
  device_id uuid not null
) on commit drop;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at
)
values (
  gen_random_uuid(),
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'sale-fidelity@example.test',
  'x',
  now()
);

insert into public.businesses (name)
values ('Sale Fidelity Regression Business');

insert into public.roles (business_id, name, is_system)
select id, 'sale-fidelity-role', false
from public.businesses
where name = 'Sale Fidelity Regression Business';

insert into public.locations (business_id, name, status)
select id, 'Sale Fidelity Location', 'active'
from public.businesses
where name = 'Sale Fidelity Regression Business';

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in ('sales.create', 'credit.manage', 'returns.create')
where r.name = 'sale-fidelity-role';

insert into public.business_memberships (business_id, user_id, role_id, status, joined_at)
select b.id, u.id, r.id, 'active', now()
from public.businesses b
join public.roles r on r.business_id = b.id and r.name = 'sale-fidelity-role'
cross join auth.users u
where b.name = 'Sale Fidelity Regression Business'
  and u.email = 'sale-fidelity@example.test';

insert into public.location_memberships (business_id, location_id, user_id, status)
select b.id, l.id, u.id, 'active'
from public.businesses b
join public.locations l on l.business_id = b.id and l.name = 'Sale Fidelity Location'
cross join auth.users u
where b.name = 'Sale Fidelity Regression Business'
  and u.email = 'sale-fidelity@example.test';

insert into public.devices (
  business_id, registered_by, device_client_id, device_name,
  platform, app_version, status, last_seen_at
)
select b.id, u.id, 'sale-fidelity-device', 'Sale Fidelity Device',
       'test', 'test', 'active', now()
from public.businesses b
cross join auth.users u
where b.name = 'Sale Fidelity Regression Business'
  and u.email = 'sale-fidelity@example.test';

insert into public.products (
  business_id, location_id, name, sku, cost_price, selling_price, tracks_stock
)
select b.id, l.id, 'Sale Fidelity Product', 'SALE-FIDELITY-SKU', 4, 10, true
from public.businesses b
join public.locations l on l.business_id = b.id and l.name = 'Sale Fidelity Location'
where b.name = 'Sale Fidelity Regression Business';

insert into public.product_stock_levels (product_id, location_id, current_stock)
select p.id, p.location_id, 10
from public.products p
where p.sku = 'SALE-FIDELITY-SKU';

insert into public.customers (business_id, location_id, name, credit_limit, outstanding_balance)
select b.id, l.id, 'Sale Fidelity Customer', 1000, 0
from public.businesses b
join public.locations l on l.business_id = b.id and l.name = 'Sale Fidelity Location'
where b.name = 'Sale Fidelity Regression Business';

insert into _sale_fidelity_ids
select u.id, b.id, l.id, p.id, c.id, d.id
from auth.users u
join public.businesses b on b.name = 'Sale Fidelity Regression Business'
join public.locations l on l.business_id = b.id and l.name = 'Sale Fidelity Location'
join public.products p on p.business_id = b.id and p.sku = 'SALE-FIDELITY-SKU'
join public.customers c on c.business_id = b.id and c.name = 'Sale Fidelity Customer'
join public.devices d on d.business_id = b.id and d.device_client_id = 'sale-fidelity-device'
where u.email = 'sale-fidelity@example.test';

grant select on _sale_fidelity_ids to service_role;

set local role service_role;
select set_config(
  'request.jwt.claim.sub',
  (select user_id::text from _sale_fidelity_ids),
  true
);

do $$
declare
  ids _sale_fidelity_ids%rowtype;
  accepted jsonb;
  sale_id uuid;
  row_count integer;
  stock integer;
  ledger_amount numeric;
  return_result jsonb;
  duplicate_sale_id uuid;
  new_return_id uuid;
  expected_sale_item_id uuid;
begin
  select * into ids from _sale_fidelity_ids;

  accepted := public.fulus_api_create_sale_atomic_v2(
    ids.user_id, ids.business_id, ids.location_id, null,
    'sale-fidelity-exact', now(), 0, 0, 10, 'cash', null,
    ids.device_id,
    jsonb_build_array(jsonb_build_object(
      'product_id', ids.product_id::text,
      'description', 'Sale Fidelity Product',
      'quantity', 1,
      'unit_price', '10.00',
      'cost_price_at_sale', '4.00'
    )),
    jsonb_build_array(jsonb_build_object(
      'method', 'cash', 'amount', '10.00', 'tendered_amount', '10.00'
    ))
  );

  if accepted->>'status' <> 'applied'
     or round((accepted->>'total')::numeric,2) <> 10
     or round((accepted->>'amount_paid')::numeric,2) <> 10 then
    raise exception 'FAIL: exact-cent sale returned unexpected result: %', accepted;
  end if;

  sale_id := (accepted->>'sale_id')::uuid;
  select count(*), coalesce(max(amount),0)
  into row_count, ledger_amount
  from public.cash_ledger
  where business_id = ids.business_id
    and operation_id = 'sale-fidelity-exact:cash:1';
  if row_count <> 1 or ledger_amount <> 10 then
    raise exception 'FAIL: exact sale cash ledger is count %, amount %', row_count, ledger_amount;
  end if;

  accepted := public.fulus_api_create_sale_atomic_v2(
    ids.user_id, ids.business_id, ids.location_id, ids.customer_id,
    'sale-fidelity-split', now(), 0, 0, 8, 'split', null,
    ids.device_id,
    jsonb_build_array(jsonb_build_object(
      'product_id', ids.product_id::text,
      'description', 'Sale Fidelity Product',
      'quantity', 1,
      'unit_price', '10.00',
      'cost_price_at_sale', '4.00'
    )),
    jsonb_build_array(
      jsonb_build_object('method', 'cash', 'amount', '8.00', 'tendered_amount', '8.00'),
      jsonb_build_object('method', 'credit', 'amount', '2.00')
    )
  );

  if accepted->>'status' <> 'applied'
     or round((accepted->>'total')::numeric,2) <> 10
     or round((accepted->>'amount_paid')::numeric,2) <> 8
     or round((accepted->>'balance_due')::numeric,2) <> 2 then
    raise exception 'FAIL: exact split-payment sale returned unexpected result: %', accepted;
  end if;

  select count(*), coalesce(max(amount),0)
  into row_count, ledger_amount
  from public.cash_ledger
  where business_id = ids.business_id
    and operation_id = 'sale-fidelity-split:cash:1';
  if row_count <> 1 or ledger_amount <> 8 then
    raise exception 'FAIL: split sale cash ledger is count %, amount %', row_count, ledger_amount;
  end if;

  if (select outstanding_balance from public.customers where id = ids.customer_id) <> 2
     or not exists (
       select 1 from public.customer_ledger_entries
       where business_id = ids.business_id
         and customer_id = ids.customer_id
         and operation_id = 'sale-fidelity-split:credit'
         and amount = 2
     ) then
    raise exception 'FAIL: split credit did not create the expected customer balance and ledger row';
  end if;

  accepted := public.fulus_api_create_sale_atomic_v2(
    ids.user_id, ids.business_id, ids.location_id, ids.customer_id,
    'sale-fidelity-duplicate-product-lines', now(), 0, 0, 20, 'split', null,
    ids.device_id,
    jsonb_build_array(
      jsonb_build_object(
        'product_id', ids.product_id::text,
        'description', 'Sale Fidelity Product line A',
        'quantity', 1,
        'unit_price', '10.00',
        'cost_price_at_sale', '4.00'
      ),
      jsonb_build_object(
        'product_id', ids.product_id::text,
        'description', 'Sale Fidelity Product line B',
        'quantity', 1,
        'unit_price', '20.00',
        'cost_price_at_sale', '4.00'
      )
    ),
    jsonb_build_array(
      jsonb_build_object('method', 'cash', 'amount', '20.00', 'tendered_amount', '20.00'),
      jsonb_build_object('method', 'credit', 'amount', '10.00')
    )
  );
  if accepted->>'status' <> 'applied'
     or round((accepted->>'total')::numeric,2) <> 30 then
    raise exception 'FAIL: duplicate-product-line sale was not persisted: %', accepted;
  end if;
  duplicate_sale_id := (accepted->>'sale_id')::uuid;

  return_result := public.fulus_api_create_return_atomic_v2(
    ids.user_id, ids.business_id, duplicate_sale_id,
    'return-fidelity-duplicate-product-lines',
    'Regression for product-only split-credit return',
    15, 'cash', ids.device_id,
    jsonb_build_array(jsonb_build_object(
      'product_id', ids.product_id::text,
      'quantity', 1
    ))
  );
  if return_result->>'status' <> 'applied'
     or round((return_result->>'refund_amount')::numeric,2) <> 15
     or round((return_result->>'credit_reversal')::numeric,2) <> 10
     or round((return_result->>'cash_refund')::numeric,2) <> 5 then
    raise exception 'FAIL: duplicate-line split-credit refund returned unexpected allocation: %', return_result;
  end if;
  new_return_id := (return_result->>'return_id')::uuid;

  select min(id) into expected_sale_item_id
  from public.sale_items where sale_id=duplicate_sale_id;
  if not exists (
    select 1 from public.return_items ri
    where ri.return_id=new_return_id
      and ri.sale_item_id=expected_sale_item_id
      and ri.quantity=1
      and ri.amount=15
  ) then
    raise exception 'FAIL: product-only return did not resolve to a stable sale line and weighted refund amount';
  end if;

  if (select outstanding_balance from public.customers where id=ids.customer_id) <> 2
     or not exists (
       select 1 from public.customer_ledger_entries
       where business_id=ids.business_id
         and customer_id=ids.customer_id
         and operation_id='return-fidelity-duplicate-product-lines:credit-reversal'
         and entry_type='credit_reversal'
         and amount=10
     ) then
    raise exception 'FAIL: cash refund did not reverse the eligible split-credit balance exactly once';
  end if;
  select count(*),coalesce(max(amount),0)
  into row_count,ledger_amount
  from public.cash_ledger
  where business_id=ids.business_id
    and operation_id='return-fidelity-duplicate-product-lines:cash';
  if row_count <> 1 or ledger_amount <> 5 then
    raise exception 'FAIL: split-credit cash refund ledger is count %, amount %',row_count,ledger_amount;
  end if;

  -- Exact retries must replay the same return without another stock, credit,
  -- or cash-ledger effect.
  if public.fulus_api_create_return_atomic_v2(
    ids.user_id, ids.business_id, duplicate_sale_id,
    'return-fidelity-duplicate-product-lines',
    'Regression for product-only split-credit return',
    15, 'cash', ids.device_id,
    jsonb_build_array(jsonb_build_object(
      'product_id', ids.product_id::text,
      'quantity', 1
    ))
  ) <> return_result then
    raise exception 'FAIL: exact return retry did not replay its original response';
  end if;
  select count(*) into row_count from public.returns where id=new_return_id;
  if row_count <> 1 then
    raise exception 'FAIL: idempotent return retry created another return row';
  end if;

  begin
    perform public.fulus_api_create_sale_atomic_v2(
      ids.user_id, ids.business_id, ids.location_id, null,
      'sale-fidelity-one-cent-over', now(), 0, 0, 10.01, 'cash', null,
      ids.device_id,
      jsonb_build_array(jsonb_build_object(
        'product_id', ids.product_id::text,
        'description', 'Sale Fidelity Product',
        'quantity', 1,
        'unit_price', '10.00',
        'cost_price_at_sale', '4.00'
      )),
      jsonb_build_array(jsonb_build_object(
        'method', 'cash', 'amount', '10.01', 'tendered_amount', '10.01'
      ))
    );
    raise exception 'FAIL: one-cent sale overpayment was accepted';
  exception when sqlstate '22023' then
    if sqlerrm <> 'Sale payment legs must exactly equal the server-calculated total' then
      raise;
    end if;
  end;

  select count(*) into row_count
  from public.sales
  where business_id = ids.business_id
    and client_reference = 'sale-fidelity-one-cent-over';
  if row_count <> 0 then
    raise exception 'FAIL: rejected sale left a sales row';
  end if;

  select count(*) into row_count
  from public.sync_changes
  where business_id = ids.business_id
    and entity_type = 'sale'
    and payload->>'client_reference' = 'sale-fidelity-one-cent-over';
  if row_count <> 0 then
    raise exception 'FAIL: rejected sale left a sale change-feed event';
  end if;

  select count(*) into row_count
  from public.sale_payments sp
  join public.sales s on s.id = sp.sale_id
  where s.business_id = ids.business_id
    and s.client_reference = 'sale-fidelity-one-cent-over';
  if row_count <> 0 then
    raise exception 'FAIL: rejected sale left a sale payment';
  end if;

  select count(*) into row_count
  from public.cash_ledger
  where business_id = ids.business_id
    and operation_id = 'sale-fidelity-one-cent-over:cash:1';
  if row_count <> 0 then
    raise exception 'FAIL: rejected sale left a cash-ledger row';
  end if;

  select count(*) into row_count
  from public.inventory_movements
  where business_id = ids.business_id
    and operation_id = 'sale-fidelity-one-cent-over:stock:' || ids.product_id::text;
  if row_count <> 0 then
    raise exception 'FAIL: rejected sale left an inventory movement';
  end if;

  select current_stock into stock
  from public.product_stock_levels
  where product_id = ids.product_id and location_id = ids.location_id;
  if stock <> 7 then
    raise exception 'FAIL: rejected sale changed stock to %, expected 7', stock;
  end if;

  select count(*) into row_count
  from public.idempotency_keys
  where business_id = ids.business_id and key = 'sale-fidelity-one-cent-over';
  if row_count <> 0 then
    raise exception 'FAIL: rejected sale left an idempotency row';
  end if;

  begin
    perform public.fulus_api_create_sale_atomic_v2(
      ids.user_id, ids.business_id, ids.location_id, null,
      'sale-fidelity-request-paid-mismatch', now(), 0, 0, 9.99, 'cash', null,
      ids.device_id,
      jsonb_build_array(jsonb_build_object(
        'product_id', ids.product_id::text,
        'description', 'Sale Fidelity Product',
        'quantity', 1,
        'unit_price', '10.00',
        'cost_price_at_sale', '4.00'
      )),
      jsonb_build_array(jsonb_build_object(
        'method', 'cash', 'amount', '10.00', 'tendered_amount', '10.00'
      ))
    );
    raise exception 'FAIL: mismatched requested amount_paid was accepted';
  exception when sqlstate '22023' then
    if sqlerrm <> 'Requested amount paid must exactly equal collected payment legs' then
      raise;
    end if;
  end;

  select count(*) into row_count
  from public.sales
  where business_id = ids.business_id
    and client_reference = 'sale-fidelity-request-paid-mismatch';
  if row_count <> 0 then
    raise exception 'FAIL: amount_paid mismatch left a sales row';
  end if;

  select count(*) into row_count
  from public.cash_ledger
  where business_id = ids.business_id
    and operation_id = 'sale-fidelity-request-paid-mismatch:cash:1';
  if row_count <> 0 then
    raise exception 'FAIL: amount_paid mismatch left a cash-ledger row';
  end if;

  if not exists (
    select 1 from public.sales
    where id = sale_id and client_reference = 'sale-fidelity-exact'
  ) then
    raise exception 'FAIL: valid exact-cent sale was not persisted';
  end if;
end $$;

rollback;

