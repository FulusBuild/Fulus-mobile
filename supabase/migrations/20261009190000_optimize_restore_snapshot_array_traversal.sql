-- Keep the restore money-wire boundary strict while avoiding a full
-- object rebuild for every row in every snapshot array. The previous
-- normalizer traversed all 3k+ audit rows and 2k+ inventory rows even when
-- those rows had no direct monetary fields, which still exceeded the
-- production statement timeout after the per-row aggregation optimization.
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
begin
  if p_value is null then
    return null;
  end if;

  if pg_catalog.jsonb_typeof(p_value) <> 'object' then
    return p_value;
  end if;

  -- Snapshot roots rarely carry money fields. Avoid rebuilding the root
  -- object unless a direct monetary key actually needs normalization.
  if p_value ?| v_money_keys then
    v_result := public._fulus_money_wire_row_jsonb(p_value);
  else
    v_result := p_value;
  end if;

  select coalesce(
    pg_catalog.jsonb_object_agg(
      section.key,
      case
        when pg_catalog.jsonb_typeof(section.value) = 'array' then
          case
            when exists (
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

-- Regression contract: root and direct row money values normalize, nested
-- metadata stays untouched, non-money arrays remain unchanged, and row order
-- is preserved for mixed arrays.
do $test$
declare
  v_input jsonb := '{
    "amount": 300,
    "nested": {"amount": 400},
    "rows": [
      {"id": "money-row", "total": 1200, "meta": {"amount": 50}},
      {"id": "plain-row", "payload": {"amount": 500}},
      {"id": "string-money", "amount": "6.00"},
      null,
      3
    ],
    "audit_events": [
      {"id": "audit-1", "payload": {"amount": 700}},
      {"id": "audit-2", "metadata": {"total": 900}}
    ]
  }'::jsonb;
  v_expected jsonb := '{
    "amount": "300.00",
    "nested": {"amount": 400},
    "rows": [
      {"id": "money-row", "total": "1200.00", "meta": {"amount": 50}},
      {"id": "plain-row", "payload": {"amount": 500}},
      {"id": "string-money", "amount": "6.00"},
      null,
      3
    ],
    "audit_events": [
      {"id": "audit-1", "payload": {"amount": 700}},
      {"id": "audit-2", "metadata": {"total": 900}}
    ]
  }'::jsonb;
  v_actual jsonb;
begin
  v_actual := public._fulus_money_wire_jsonb(v_input);
  if v_actual is distinct from v_expected then
    raise exception 'optimized snapshot money wire regression: expected %, got %',
      v_expected, v_actual;
  end if;

  if public._fulus_money_wire_jsonb('null'::jsonb)
     is distinct from 'null'::jsonb then
    raise exception 'JSON null must remain JSON null';
  end if;
  if public._fulus_money_wire_jsonb('42'::jsonb)
     is distinct from '42'::jsonb then
    raise exception 'scalar snapshot values must remain unchanged';
  end if;
end;
$test$;
