-- Normalize each row by aggregating its keys once instead of repeatedly
-- rebuilding the same JSONB object with jsonb_set for every possible money
-- field. Restore snapshots contain thousands of rows, so the previous fixed
-- list of repeated object rewrites caused production statement timeouts.
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
          'amount','credit_limit','outstanding_balance','opening_cash',
          'closing_cash','cash_difference','subtotal','whole_cart_discount',
          'discount','tax','total','amount_paid','cash_tendered',
          'cash_change','unit_price','cost_price_at_sale','line_total',
          'cost_price','selling_price','refund_amount','salary'
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

-- Assert direct money fields are normalized, while nested metadata and
-- unrelated values remain unchanged at the JSONB level.
do $test$
declare
  v_input jsonb := '{
    "amount": 300,
    "selling_price": 485,
    "salary": 0,
    "quantity": 100,
    "meta": {"amount": 400, "nested": [{"total": 500}]}
  }'::jsonb;
  v_expected jsonb := '{
    "amount": "300.00",
    "selling_price": "485.00",
    "salary": "0.00",
    "quantity": 100,
    "meta": {"amount": 400, "nested": [{"total": 500}]}
  }'::jsonb;
  v_actual jsonb;
begin
  v_actual := public._fulus_money_wire_row_jsonb(v_input);
  if v_actual is distinct from v_expected then
    raise exception 'row money wire normalization regression: expected %, got %',
      v_expected, v_actual;
  end if;

  if public._fulus_money_wire_row_jsonb('null'::jsonb)
     is distinct from 'null'::jsonb then
    raise exception 'JSON null must remain JSON null';
  end if;

  if public._fulus_money_wire_row_jsonb('42'::jsonb)
     is distinct from '42'::jsonb then
    raise exception 'scalar row inputs must remain unchanged';
  end if;
end;
$test$;
