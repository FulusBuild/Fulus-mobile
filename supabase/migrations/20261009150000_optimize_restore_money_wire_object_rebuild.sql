-- Reduce restore-snapshot normalization overhead by rebuilding the root
-- object once instead of applying jsonb_set once per top-level array.
-- Preserve the v2 contract: only direct monetary fields on the root and on
-- rows in top-level arrays are normalized; nested JSON is deliberately opaque.
create or replace function public._fulus_money_wire_jsonb(p_value jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  if p_value is null then
    return null;
  end if;

  v_result := public._fulus_money_wire_row_jsonb(p_value);

  if pg_catalog.jsonb_typeof(v_result) <> 'object' then
    return v_result;
  end if;

  select coalesce(
    pg_catalog.jsonb_object_agg(
      section.key,
      case
        when pg_catalog.jsonb_typeof(section.value) = 'array' then (
          select coalesce(
            pg_catalog.jsonb_agg(
              public._fulus_money_wire_row_jsonb(element.value)
            ),
            '[]'::jsonb
          )
          from pg_catalog.jsonb_array_elements(section.value) as element(value)
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

revoke all on function public._fulus_money_wire_jsonb(jsonb) from public;

-- Guard the wire contract and untouched nested JSON while this optimization is
-- installed. These assertions intentionally cover objects, arrays, scalars,
-- nulls, and arrays containing non-object values.
do $test$
declare
  v_input jsonb := '{
    "amount": 300,
    "meta": {"amount": 400, "nested": [{"total": 500}]},
    "sales": [
      {"total": 1200, "notes": {"amount": 77}},
      {"amount": 0, "label": "zero"},
      null,
      7,
      ["not-an-object"]
    ],
    "empty": [],
    "unchanged": "text"
  }'::jsonb;
  v_actual jsonb;
  v_expected jsonb := '{
    "amount": "300.00",
    "meta": {"amount": 400, "nested": [{"total": 500}]},
    "sales": [
      {"total": "1200.00", "notes": {"amount": 77}},
      {"amount": "0.00", "label": "zero"},
      null,
      7,
      ["not-an-object"]
    ],
    "empty": [],
    "unchanged": "text"
  }'::jsonb;
begin
  v_actual := public._fulus_money_wire_jsonb(v_input);
  if v_actual is distinct from v_expected then
    raise exception 'money wire normalization regression: expected %, got %',
      v_expected, v_actual;
  end if;

  if public._fulus_money_wire_jsonb('null'::jsonb) is distinct from 'null'::jsonb then
    raise exception 'JSON null must remain JSON null';
  end if;

  if public._fulus_money_wire_jsonb('42'::jsonb) is distinct from '42'::jsonb then
    raise exception 'scalar roots must remain unchanged';
  end if;
end;
$test$;
