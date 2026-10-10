-- Keep the row-level allowlist in sync with every direct monetary field
-- accepted by CloudRestoreImporter. The section normalizer delegates row
-- conversion to this helper, so expanding only the caller's key probe is not
-- sufficient.
create or replace function public._fulus_money_wire_row_jsonb(p_value jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  if p_value is null
     or pg_catalog.jsonb_typeof(p_value) <> 'object' then
    return p_value;
  end if;

  select coalesce(
    pg_catalog.jsonb_object_agg(
      section.key,
      case
        when section.key = any (array[
          'amount','amount_remitted','credit_limit','outstanding_balance',
          'opening_cash','closing_cash','cash_difference','subtotal',
          'whole_cart_discount','discount','tax','total','amount_paid',
          'cash_tendered','cash_change','tendered_amount','unit_price',
          'cost_price_at_sale','line_total','line_discount','cost_price',
          'selling_price','refund_amount','salary'
        ]::text[])
        and pg_catalog.jsonb_typeof(section.value) = 'number'
        then pg_catalog.to_jsonb(
          pg_catalog.to_char(
            (section.value #>> '{}')::numeric,
            'FM999999999999999999999999999999990.00'
          )
        )
        else section.value
      end
    ),
    '{}'::jsonb
  )
  into v_result
  from pg_catalog.jsonb_each(p_value) as section(key, value);

  return v_result;
end;
$function$;

revoke all on function public._fulus_money_wire_row_jsonb(jsonb) from public;

-- Skip large non-financial snapshot arrays during money-wire normalization.
create or replace function public._fulus_money_wire_jsonb(p_value jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_result jsonb;
  v_money_keys constant text[] := array[
    'amount','amount_remitted','credit_limit','outstanding_balance','opening_cash',
    'closing_cash','cash_difference','subtotal','whole_cart_discount',
    'discount','tax','total','amount_paid','cash_tendered',
    'cash_change','tendered_amount','unit_price','cost_price_at_sale','line_total','line_discount',
    'cost_price','selling_price','refund_amount','salary'
  ];
  v_money_sections constant text[] := array[
    'products','customers','suppliers','sales','expenses','income_records','returns',
    'cash_ledger','cash_drawer_shifts','sale_items','sale_payments',
    'return_items','customer_ledger_entries','supplier_ledger_entries',
    'tax_remittances','employees'
  ];
begin
  if p_value is null then return null; end if;
  if pg_catalog.jsonb_typeof(p_value) <> 'object' then return p_value; end if;

  if p_value ?| v_money_keys then
    v_result := public._fulus_money_wire_row_jsonb(p_value);
  else
    v_result := p_value;
  end if;

  select coalesce(
    pg_catalog.jsonb_object_agg(
      section.key,
      case
        when section.key = any(v_money_sections)
          and pg_catalog.jsonb_typeof(section.value) = 'array'
        then (
          select coalesce(
            pg_catalog.jsonb_agg(
              case
                when pg_catalog.jsonb_typeof(element.value) = 'object'
                  and element.value ?| v_money_keys
                then public._fulus_money_wire_row_jsonb(element.value)
                else element.value
              end order by element.ordinality
            ), '[]'::jsonb
          )
          from pg_catalog.jsonb_array_elements(section.value)
            with ordinality as element(value, ordinality)
        )
        else section.value
      end
    ), '{}'::jsonb
  ) into v_result
  from pg_catalog.jsonb_each(v_result) as section(key, value);

  return v_result;
end;
$function$;

-- Exercise every financial snapshot section explicitly. Keep nested metadata
-- and large non-financial arrays opaque, and preserve mixed-array order.
do $test$
declare
  v_actual jsonb;
begin
  v_actual := public._fulus_money_wire_jsonb(
    '{
      "amount":300,
      "products":[{"selling_price":100,"cost_price":40}],
      "customers":[{"credit_limit":1000,"outstanding_balance":500}],
      "suppliers":[{"outstanding_balance":400}],
      "sales":[{"subtotal":1200,"whole_cart_discount":20,"discount":10,"tax":5,"total":1100,"amount_paid":600,"cash_tendered":1200,"cash_change":100,"meta":{"amount":50}}],
      "expenses":[{"amount":20}],
      "income_records":[{"amount":30}],
      "returns":[{"refund_amount":10}],
      "cash_ledger":[{"amount":4}],
      "cash_drawer_shifts":[{"opening_cash":100,"closing_cash":80,"cash_difference":20}],
      "sale_items":[{"unit_price":100,"cost_price_at_sale":60,"line_discount":5.25,"line_total":100}],
      "sale_payments":[{"amount":50,"tendered_amount":100,"cash_tendered":100,"cash_change":50}],
      "return_items":[{"unit_price":100,"line_total":100}],
      "customer_ledger_entries":[{"amount":25}],
      "supplier_ledger_entries":[{"amount":850}],
      "tax_remittances":[{"amount_remitted":75}],
      "employees":[{"salary":1200}],
      "audit_events":[{"amount":700}],
      "inventory_movements":[{"amount":400}],
      "mixed":[{"total":1200},{"payload":{"amount":500}},null,3]
    }'::jsonb
  );

  if v_actual is distinct from
    '{
      "amount":"300.00",
      "products":[{"selling_price":"100.00","cost_price":"40.00"}],
      "customers":[{"credit_limit":"1000.00","outstanding_balance":"500.00"}],
      "suppliers":[{"outstanding_balance":"400.00"}],
      "sales":[{"subtotal":"1200.00","whole_cart_discount":"20.00","discount":"10.00","tax":"5.00","total":"1100.00","amount_paid":"600.00","cash_tendered":"1200.00","cash_change":"100.00","meta":{"amount":50}}],
      "expenses":[{"amount":"20.00"}],
      "income_records":[{"amount":"30.00"}],
      "returns":[{"refund_amount":"10.00"}],
      "cash_ledger":[{"amount":"4.00"}],
      "cash_drawer_shifts":[{"opening_cash":"100.00","closing_cash":"80.00","cash_difference":"20.00"}],
      "sale_items":[{"unit_price":"100.00","cost_price_at_sale":"60.00","line_discount":"5.25","line_total":"100.00"}],
      "sale_payments":[{"amount":"50.00","tendered_amount":"100.00","cash_tendered":"100.00","cash_change":"50.00"}],
      "return_items":[{"unit_price":"100.00","line_total":"100.00"}],
      "customer_ledger_entries":[{"amount":"25.00"}],
      "supplier_ledger_entries":[{"amount":"850.00"}],
      "tax_remittances":[{"amount_remitted":"75.00"}],
      "employees":[{"salary":"1200.00"}],
      "audit_events":[{"amount":700}],
      "inventory_movements":[{"amount":400}],
      "mixed":[{"total":1200},{"payload":{"amount":500}},null,3]
    }'::jsonb then
    raise exception 'restore normalizer money-section contract failed: %', v_actual;
  end if;
end;
$test$;


-- Regression with restore-sized non-financial arrays. These sections must not
-- be row-normalized just because arbitrary audit/movement payloads contain a
-- key named "amount". This catches both accidental money conversion and a
-- reintroduction of per-row traversal over thousands of unrelated records.
do $large_snapshot_test$
declare
  v_input jsonb;
  v_actual jsonb;
begin
  select pg_catalog.jsonb_build_object(
    'products',
    pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object('id', 'product-1', 'selling_price', 300)
    ),
    'audit_events',
    (
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', i,
          'amount', i,
          'metadata', pg_catalog.jsonb_build_object('amount', i)
        ) order by i
      )
      from pg_catalog.generate_series(1, 3000) as rows(i)
    ),
    'inventory_movements',
    (
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', i,
          'amount', i,
          'metadata', pg_catalog.jsonb_build_object('amount', i)
        ) order by i
      )
      from pg_catalog.generate_series(1, 2000) as rows(i)
    )
  )
  into v_input;

  v_actual := public._fulus_money_wire_jsonb(v_input);

  if v_actual -> 'audit_events' is distinct from v_input -> 'audit_events' then
    raise exception 'large audit_events section must remain byte-for-byte equivalent as JSONB';
  end if;

  if v_actual -> 'inventory_movements' is distinct from v_input -> 'inventory_movements' then
    raise exception 'large inventory_movements section must remain byte-for-byte equivalent as JSONB';
  end if;

  if pg_catalog.jsonb_array_length(v_actual -> 'audit_events') <> 3000
     or v_actual -> 'audit_events' -> 0 ->> 'id' <> '1'
     or v_actual -> 'audit_events' -> 2999 ->> 'id' <> '3000'
     or pg_catalog.jsonb_typeof(v_actual -> 'audit_events' -> 0 -> 'amount') <> 'number'
     or pg_catalog.jsonb_typeof(v_actual -> 'audit_events' -> 0 -> 'metadata' -> 'amount') <> 'number' then
    raise exception 'large audit_events section was not preserved unchanged';
  end if;

  if pg_catalog.jsonb_array_length(v_actual -> 'inventory_movements') <> 2000
     or v_actual -> 'inventory_movements' -> 0 ->> 'id' <> '1'
     or v_actual -> 'inventory_movements' -> 1999 ->> 'id' <> '2000'
     or pg_catalog.jsonb_typeof(v_actual -> 'inventory_movements' -> 0 -> 'amount') <> 'number'
     or pg_catalog.jsonb_typeof(v_actual -> 'inventory_movements' -> 0 -> 'metadata' -> 'amount') <> 'number' then
    raise exception 'large inventory_movements section was not preserved unchanged';
  end if;

  if v_actual -> 'products' -> 0 ->> 'selling_price' <> '300.00' then
    raise exception 'financial sections must still normalize direct money fields';
  end if;
end;
$large_snapshot_test$;
