-- Cloud Sync V1: normalize return item identity at the API boundary.
-- The authoritative return function consumes sale_item_id, while the mobile
-- return model naturally carries product identity. Resolve product_id only when
-- the sale contains exactly one matching line; ambiguous lines remain rejected.
create or replace function public.fulus_api_create_return_atomic(
  target_user_id uuid,
  target_business_id uuid,
  target_sale_id uuid,
  target_client_reference text,
  target_reason text,
  target_refund_amount numeric,
  target_device_id uuid,
  target_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid;
  item jsonb;
  normalized_items jsonb := '[]'::jsonb;
  resolved_sale_item_id uuid;
  match_count integer;
begin
  actor := target_user_id;
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);

  if target_items is null or jsonb_array_length(target_items) = 0 then
    return public.create_return_atomic(
      target_business_id, target_sale_id, target_client_reference,
      target_reason, target_refund_amount, target_device_id, target_items
    );
  end if;

  for item in select * from jsonb_array_elements(target_items) loop
    if nullif(trim(item->>'sale_item_id'), '') is not null then
      normalized_items := normalized_items || jsonb_build_array(item);
    elsif nullif(trim(item->>'product_id'), '') is not null then
      resolved_sale_item_id := null;
      match_count := 0;

      select count(*)::integer, min(si.id)
        into match_count, resolved_sale_item_id
      from public.sale_items si
      join public.sales s on s.id = si.sale_id
      where si.sale_id = target_sale_id
        and si.product_id = (item->>'product_id')::uuid
        and s.business_id = target_business_id;

      if match_count <> 1 then
        raise exception using
          errcode = '22023',
          message = 'Return product must identify exactly one sale item';
      end if;

      normalized_items := normalized_items || jsonb_build_array(
        jsonb_build_object(
          'sale_item_id', resolved_sale_item_id,
          'quantity', (item->>'quantity')::integer
        )
      );
    else
      raise exception using
        errcode = '22023',
        message = 'Return item requires sale_item_id or product_id';
    end if;
  end loop;

  return public.create_return_atomic(
    target_business_id,
    target_sale_id,
    target_client_reference,
    target_reason,
    target_refund_amount,
    target_device_id,
    normalized_items
  );
end;
$$;

revoke all on function public.fulus_api_create_return_atomic(uuid,uuid,uuid,text,text,numeric,uuid,jsonb)
  from public, anon, authenticated;
grant execute on function public.fulus_api_create_return_atomic(uuid,uuid,uuid,text,text,numeric,uuid,jsonb)
  to service_role;
