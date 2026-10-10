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

do $test$
declare
  v_actual jsonb;
begin
  v_actual := public._fulus_money_wire_jsonb(
    '{"amount":300,"sales":[{"total":1200,"meta":{"amount":50}}],"supplier_ledger_entries":[{"amount":850}],"tax_remittances":[{"amount":75}],"audit_events":[{"amount":700}],"inventory_movements":[{"amount":400}]}'::jsonb
  );
  if v_actual is distinct from
    '{"amount":"300.00","sales":[{"total":"1200.00","meta":{"amount":50}}],"supplier_ledger_entries":[{"amount":"850.00"}],"tax_remittances":[{"amount":"75.00"}],"audit_events":[{"amount":700}],"inventory_movements":[{"amount":400}]}'::jsonb then
    raise exception 'restore normalizer money-section contract failed: %', v_actual;
  end if;
end;
$test$;
