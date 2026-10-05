-- Strict money wire contract for restore snapshots.
--
-- Local/domain money is integer minor units. Cloud JSON money is always a
-- decimal string. This prevents PostgreSQL NUMERIC values such as 300.00 from
-- arriving as JSON number 300 and being misinterpreted as 300 major units.

create or replace function public._fulus_money_wire_jsonb(p_value jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_result jsonb := '{}'::jsonb;
  v_key text;
  v_value jsonb;
begin
  if p_value is null then
    return null;
  end if;

  case pg_catalog.jsonb_typeof(p_value)
    when 'array' then
      select coalesce(
        pg_catalog.jsonb_agg(public._fulus_money_wire_jsonb(value)),
        '[]'::jsonb
      )
      into v_result
      from pg_catalog.jsonb_array_elements(p_value) as elements(value);
      return v_result;

    when 'object' then
      for v_key, v_value in
        select key, value
        from pg_catalog.jsonb_each(p_value)
      loop
        if v_key = any (array[
          'amount','credit_limit','outstanding_balance','opening_cash',
          'closing_cash','cash_difference','subtotal','whole_cart_discount',
          'discount','tax','total','amount_paid','cash_tendered',
          'cash_change','unit_price','cost_price_at_sale','line_total',
          'cost_price','selling_price','refund_amount','salary'
        ])
        and pg_catalog.jsonb_typeof(v_value) = 'number' then
          v_result := v_result || pg_catalog.jsonb_build_object(
            v_key,
            pg_catalog.to_char(
              (v_value::text)::numeric,
              'FM999999999999999999999999999999990.00'
            )
          );
        else
          v_result := v_result || pg_catalog.jsonb_build_object(
            v_key,
            public._fulus_money_wire_jsonb(v_value)
          );
        end if;
      end loop;
      return v_result;

    else
      return p_value;
  end case;
end;
$function$;

revoke all on function public._fulus_money_wire_jsonb(jsonb) from public;

do $migration$
declare
  v_signature text;
  v_definition text;
begin
  foreach v_signature in array array[
    'public.build_fulus_restore_snapshot(uuid,uuid)',
    'public.build_fulus_employee_restore_snapshot(uuid,uuid)'
  ]
  loop
    select pg_catalog.pg_get_functiondef(v_signature::regprocedure)
      into v_definition;

    if position('return v_snapshot;' in lower(v_definition)) = 0 then
      raise exception 'Restore function % does not contain the expected snapshot return boundary', v_signature;
    end if;

    v_definition := replace(
      v_definition,
      'return v_snapshot;',
      'return public._fulus_money_wire_jsonb(v_snapshot);'
    );

    execute v_definition;
  end loop;
end;
$migration$;
