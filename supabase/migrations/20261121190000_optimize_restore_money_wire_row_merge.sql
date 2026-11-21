-- Avoid rebuilding every key in every row while enforcing the strict
-- decimal-string money wire contract on restore snapshots.
--
-- The production restore E2E reached the final money-wire normalization step,
-- where the previous jsonb_each/jsonb_object_agg implementation exceeded the
-- PostgREST statement timeout on a business with several thousand financial
-- rows. Merge only converted money keys back into each row; preserve all
-- unrelated fields and already-string/null money values unchanged.

create or replace function public._fulus_money_wire_row_jsonb(p_value jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_money_keys constant text[] := array[
    'amount','amount_remitted','balance_after','new_balance',
    'credit_limit','outstanding_balance','opening_cash','closing_cash',
    'cash_difference','subtotal','whole_cart_discount','discount','tax',
    'total','amount_paid','cash_tendered','cash_change','tendered_amount',
    'unit_price','cost_price_at_sale','line_total','line_discount',
    'cost_price','selling_price','refund_amount','salary'
  ];
  v_converted jsonb;
begin
  if p_value is null
     or pg_catalog.jsonb_typeof(p_value) <> 'object' then
    return p_value;
  end if;

  -- jsonb concatenation replaces only numeric monetary keys. Other keys,
  -- nested metadata, and pre-normalized string/null values remain untouched.
  select coalesce(
    pg_catalog.jsonb_object_agg(
      section.key,
      pg_catalog.to_jsonb(
        pg_catalog.to_char(
          (section.value #>> '{}')::numeric,
          'FM999999999999999999999999999999990.00'
        )
      )
    ),
    '{}'::jsonb
  )
  into v_converted
  from pg_catalog.jsonb_each(p_value) as section(key, value)
  where section.key = any(v_money_keys)
    and pg_catalog.jsonb_typeof(section.value) = 'number';

  return p_value || v_converted;
end;
$function$;

revoke all on function public._fulus_money_wire_row_jsonb(jsonb) from public;

create or replace function public._fulus_money_wire_jsonb(p_value jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_result jsonb;
  v_money_keys constant text[] := array[
    'amount','amount_remitted','balance_after','new_balance','credit_limit',
    'outstanding_balance','opening_cash','closing_cash','cash_difference',
    'subtotal','whole_cart_discount','discount','tax','total','amount_paid',
    'cash_tendered','cash_change','tendered_amount','unit_price',
    'cost_price_at_sale','line_total','line_discount','cost_price',
    'selling_price','refund_amount','salary'
  ];
  v_money_sections constant text[] := array[
    'products','customers','suppliers','sales','expenses','income_records',
    'returns','cash_ledger','cash_drawer_shifts','sale_items','sale_payments',
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
          and exists (
            select 1
            from pg_catalog.jsonb_array_elements(section.value) as probe(value)
            where pg_catalog.jsonb_typeof(probe.value) = 'object'
              and probe.value ?| v_money_keys
          )
        then (
          select coalesce(
            pg_catalog.jsonb_agg(
              case
                when pg_catalog.jsonb_typeof(element.value) = 'object'
                  and element.value ?| v_money_keys
                then public._fulus_money_wire_row_jsonb(element.value)
                else element.value
              end
              order by element.ordinality
            ),
            '[]'::jsonb
          )
          from pg_catalog.jsonb_array_elements(section.value)
            with ordinality as element(value, ordinality)
        )
        else section.value
      end
    ),
    '{}'::jsonb
  )
  into v_result
  from pg_catalog.jsonb_each(v_result) as section(key, value);

  return v_result;
end;
$function$;

-- Contract: normalize every supported direct monetary field, but do not
-- descend into nested JSON or alter strings, nulls, scalar rows, or row order.
do $money_wire_test$
declare
  v_input jsonb := '{
    "amount": 300,
    "sales": [
      {"id":"a","total":1200,"balance_after":7.5,"meta":{"amount":50}},
      {"id":"b","amount":"6.00","new_balance":null},
      null,
      3
    ],
    "suppliers": [{"outstanding_balance":400}],
    "supplier_ledger_entries": [{"amount":850,"balance_after":850}],
    "tax_remittances": [{"amount_remitted":75}],
    "audit_events": [{"amount":700}],
    "inventory_movements": [{"amount":400}]
  }'::jsonb;
  v_actual jsonb;
begin
  v_actual := public._fulus_money_wire_jsonb(v_input);

  if v_actual ->> 'amount' <> '300.00'
     or v_actual #>> '{sales,0,total}' <> '1200.00'
     or v_actual #>> '{sales,0,balance_after}' <> '7.50'
     or v_actual #>> '{sales,0,meta,amount}' <> '50'
     or v_actual #>> '{sales,1,amount}' <> '6.00'
     or v_actual #> '{sales,1,new_balance}' <> 'null'::jsonb
     or v_actual #>> '{suppliers,0,outstanding_balance}' <> '400.00'
     or v_actual #>> '{supplier_ledger_entries,0,balance_after}' <> '850.00'
     or v_actual #>> '{tax_remittances,0,amount_remitted}' <> '75.00'
     or v_actual -> 'audit_events' is distinct from v_input -> 'audit_events'
     or v_actual -> 'inventory_movements' is distinct from v_input -> 'inventory_movements'
     or v_actual #>> '{sales,0,id}' <> 'a'
     or v_actual #>> '{sales,1,id}' <> 'b'
     or v_actual #> '{sales,2}' <> 'null'::jsonb
     or v_actual #>> '{sales,3}' <> '3' then
    raise exception 'optimized restore money-wire contract failed: %', v_actual;
  end if;
end;
$money_wire_test$;

-- Exercise a large financial section so this optimization remains covered by
-- the migration-chain CI rather than only by tiny example objects.
do $large_money_wire_test$
declare
  v_input jsonb;
  v_actual jsonb;
begin
  select pg_catalog.jsonb_build_object(
    'sale_payments',
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'id', i,
        'amount', i::numeric + 0.25,
        'payment_method', 'cash',
        'metadata', pg_catalog.jsonb_build_object('amount', i)
      ) order by i
    )
  )
  into v_input
  from pg_catalog.generate_series(1, 5000) as rows(i);

  v_actual := public._fulus_money_wire_jsonb(v_input);

  if pg_catalog.jsonb_array_length(v_actual -> 'sale_payments') <> 5000
     or v_actual #>> '{sale_payments,0,amount}' <> '1.25'
     or v_actual #>> '{sale_payments,4999,amount}' <> '5000.25'
     or pg_catalog.jsonb_typeof(v_actual #> '{sale_payments,0,metadata,amount}') <> 'number' then
    raise exception 'large restore money-wire normalization failed';
  end if;
end;
$large_money_wire_test$;
