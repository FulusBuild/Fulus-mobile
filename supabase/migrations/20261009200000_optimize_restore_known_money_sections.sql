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
    'amount','credit_limit','outstanding_balance','opening_cash',
    'closing_cash','cash_difference','subtotal','whole_cart_discount',
    'discount','tax','total','amount_paid','cash_tendered',
    'cash_change','unit_price','cost_price_at_sale','line_total',
    'cost_price','selling_price','refund_amount','salary'
  ];
  v_money_sections constant text[] := array[
    'products','customers','sales','expenses','income_records','returns',
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
      "sales":[{"subtotal":1200,"total":1100,"meta":{"amount":50}}],
      "expenses":[{"amount":20}],
      "income_records":[{"amount":30}],
      "returns":[{"refund_amount":10}],
      "cash_ledger":[{"amount":4}],
      "cash_drawer_shifts":[{"opening_cash":100,"closing_cash":80,"cash_difference":20}],
      "sale_items":[{"unit_price":100,"cost_price_at_sale":60,"line_total":100}],
      "sale_payments":[{"amount":50,"cash_tendered":100,"cash_change":50}],
      "return_items":[{"unit_price":100,"line_total":100}],
      "customer_ledger_entries":[{"amount":25}],
      "supplier_ledger_entries":[{"amount":850}],
      "tax_remittances":[{"amount":75}],
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
      "sales":[{"subtotal":"1200.00","total":"1100.00","meta":{"amount":50}}],
      "expenses":[{"amount":"20.00"}],
      "income_records":[{"amount":"30.00"}],
      "returns":[{"refund_amount":"10.00"}],
      "cash_ledger":[{"amount":"4.00"}],
      "cash_drawer_shifts":[{"opening_cash":"100.00","closing_cash":"80.00","cash_difference":"20.00"}],
      "sale_items":[{"unit_price":"100.00","cost_price_at_sale":"60.00","line_total":"100.00"}],
      "sale_payments":[{"amount":"50.00","cash_tendered":"100.00","cash_change":"50.00"}],
      "return_items":[{"unit_price":"100.00","line_total":"100.00"}],
      "customer_ledger_entries":[{"amount":"25.00"}],
      "supplier_ledger_entries":[{"amount":"850.00"}],
      "tax_remittances":[{"amount":"75.00"}],
      "employees":[{"salary":"1200.00"}],
      "audit_events":[{"amount":700}],
      "inventory_movements":[{"amount":400}],
      "mixed":[{"total":1200},{"payload":{"amount":500}},null,3]
    }'::jsonb then
    raise exception 'restore normalizer money-section contract failed: %', v_actual;
  end if;
end;
$test$;
