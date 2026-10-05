-- Optimize the strict money wire boundary without recursively walking every
-- scalar in a potentially large restore snapshot.
--
-- Restore snapshots are shaped as a top-level object whose business-data
-- sections are arrays of row objects. Monetary fields are direct row fields.
-- Normalize only those direct fields instead of recursively traversing audit
-- payloads, profiles, permissions, and other non-monetary JSON.

create or replace function public._fulus_money_wire_jsonb(p_value jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_result jsonb := p_value;
  v_section_key text;
  v_section_value jsonb;
  v_row jsonb;
  v_rows jsonb := '[]'::jsonb;
  v_money_key text;
begin
  if p_value is null then
    return null;
  end if;

  -- Normalize direct monetary fields on a root object too.
  foreach v_money_key in array ARRAY[
    'amount','credit_limit','outstanding_balance','opening_cash',
    'closing_cash','cash_difference','subtotal','whole_cart_discount',
    'discount','tax','total','amount_paid','cash_tendered',
    'cash_change','unit_price','cost_price_at_sale','line_total',
    'cost_price','selling_price','refund_amount','salary'
  ]
  loop
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

  -- Restore snapshots store rows in top-level arrays. Only inspect those
  -- direct row fields; nested JSON blobs are intentionally left untouched.
  for v_section_key, v_section_value in
    select key, value
    from pg_catalog.jsonb_each(v_result)
  loop
    if pg_catalog.jsonb_typeof(v_section_value) <> 'array' then
      continue;
    end if;

    v_rows := '[]'::jsonb;

    for v_row in
      select value
      from pg_catalog.jsonb_array_elements(v_section_value)
    loop
      if pg_catalog.jsonb_typeof(v_row) = 'object' then
        foreach v_money_key in array ARRAY[
          'amount','credit_limit','outstanding_balance','opening_cash',
          'closing_cash','cash_difference','subtotal','whole_cart_discount',
          'discount','tax','total','amount_paid','cash_tendered',
          'cash_change','unit_price','cost_price_at_sale','line_total',
          'cost_price','selling_price','refund_amount','salary'
        ]
        loop
          if v_row ? v_money_key
             and pg_catalog.jsonb_typeof(v_row -> v_money_key) = 'number' then
            v_row := pg_catalog.jsonb_set(
              v_row,
              array[v_money_key],
              pg_catalog.to_jsonb(
                pg_catalog.to_char(
                  (v_row ->> v_money_key)::numeric,
                  'FM999999999999999999999999999999990.00'
                )
              ),
              false
            );
          end if;
        end loop;
      end if;

      v_rows := v_rows || pg_catalog.jsonb_build_array(v_row);
    end loop;

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

revoke all on function public._fulus_money_wire_jsonb(jsonb) from public;