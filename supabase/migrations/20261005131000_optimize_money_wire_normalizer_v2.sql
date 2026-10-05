-- Keep row normalization O(n) by aggregating transformed rows in SQL.
create or replace function public._fulus_money_wire_row_jsonb(p_value jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_result jsonb := p_value;
  v_money_key text;
begin
  if p_value is null or pg_catalog.jsonb_typeof(p_value) <> 'object' then
    return p_value;
  end if;

  foreach v_money_key in array array[
    'amount','credit_limit','outstanding_balance','opening_cash',
    'closing_cash','cash_difference','subtotal','whole_cart_discount',
    'discount','tax','total','amount_paid','cash_tendered',
    'cash_change','unit_price','cost_price_at_sale','line_total',
    'cost_price','selling_price','refund_amount','salary'
  ] loop
    if v_result ? v_money_key
       and pg_catalog.jsonb_typeof(v_result -> v_money_key) = 'number' then
      v_result := pg_catalog.jsonb_set(
        v_result,
        array[v_money_key],
        pg_catalog.to_jsonb(
          pg_catalog.to_char(
            (v_result ->> v_money_key)::numeric,
            'FM999999999999999999999999999999990.00'
          )
        ),
        false
      );
    end if;
  end loop;

  return v_result;
end;
$function$;

create or replace function public._fulus_money_wire_jsonb(p_value jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_result jsonb;
  v_section_key text;
  v_section_value jsonb;
  v_rows jsonb;
begin
  if p_value is null then
    return null;
  end if;

  v_result := public._fulus_money_wire_row_jsonb(p_value);

  if pg_catalog.jsonb_typeof(v_result) <> 'object' then
    return v_result;
  end if;

  for v_section_key, v_section_value in
    select key, value
    from pg_catalog.jsonb_each(v_result)
  loop
    if pg_catalog.jsonb_typeof(v_section_value) <> 'array' then
      continue;
    end if;

    select coalesce(
      pg_catalog.jsonb_agg(
        public._fulus_money_wire_row_jsonb(value)
      ),
      '[]'::jsonb
    )
    into v_rows
    from pg_catalog.jsonb_array_elements(v_section_value);

    v_result := pg_catalog.jsonb_set(
      v_result,
      array[v_section_key],
      v_rows,
      false
    );
  end loop;

  return v_result;
end;
$function$;

revoke all on function public._fulus_money_wire_row_jsonb(jsonb) from public;
revoke all on function public._fulus_money_wire_jsonb(jsonb) from public;