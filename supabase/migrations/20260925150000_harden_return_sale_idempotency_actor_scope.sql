-- Restore the durable actor-bound idempotency boundary for return commands and
-- bind sale-create replay to the original account/device as well as its request hash.

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
set search_path=''
as $function$
declare
  item jsonb;
  normalized_items jsonb := '[]'::jsonb;
  resolved_sale_item_id uuid;
  match_count integer;
  idem public.idempotency_keys%rowtype;
  request_hash text;
  result jsonb;
begin
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);

  if not exists (
    select 1 from public.devices
    where id=target_device_id
      and business_id=target_business_id
      and registered_by=target_user_id
      and status='active'
  ) then
    raise exception using errcode='42501',message='Device is not registered or active';
  end if;

  if target_items is null or jsonb_array_length(target_items)=0 then
    raise exception using errcode='22023',message='Return requires items';
  end if;

  for item in select * from jsonb_array_elements(target_items) loop
    if nullif(trim(item->>'sale_item_id'),'') is not null then
      normalized_items := normalized_items || jsonb_build_array(item);
    elsif nullif(trim(item->>'product_id'),'') is not null then
      resolved_sale_item_id := null;
      match_count := 0;
      select count(*)::integer,(array_agg(si.id))[1]
        into match_count,resolved_sale_item_id
      from public.sale_items si
      join public.sales s on s.id=si.sale_id
      where si.sale_id=target_sale_id
        and si.product_id=(item->>'product_id')::uuid
        and s.business_id=target_business_id;
      if match_count<>1 then
        raise exception using errcode='22023',message='Return product must identify exactly one sale item';
      end if;
      normalized_items := normalized_items || jsonb_build_array(
        jsonb_build_object(
          'sale_item_id',resolved_sale_item_id,
          'quantity',(item->>'quantity')::integer
        )
      );
    else
      raise exception using errcode='22023',message='Return item requires sale_item_id or product_id';
    end if;
  end loop;

  request_hash := md5(jsonb_build_object(
    'sale_id',target_sale_id,
    'reason',target_reason,
    'refund_amount',target_refund_amount,
    'device_id',target_device_id,
    'items',normalized_items
  )::text);

  insert into public.idempotency_keys(
    business_id,device_id,user_id,key,operation_type,request_hash
  )
  values(
    target_business_id,target_device_id,target_user_id,
    target_client_reference,'return.create',request_hash
  )
  on conflict(business_id,key) do nothing;

  select * into idem
  from public.idempotency_keys
  where business_id=target_business_id
    and key=target_client_reference
  for update;

  if idem.device_id is distinct from target_device_id
     or idem.user_id is distinct from target_user_id then
    raise exception using errcode='P0009',
      message='Operation id was already used from a different device or account';
  end if;
  if idem.operation_type<>'return.create'
     or idem.request_hash<>request_hash then
    raise exception using errcode='P0009',
      message='Operation id was already used with a different request';
  end if;
  if idem.completed_at is not null and idem.response_body is not null then
    return idem.response_body;
  end if;

  result := public.create_return_atomic(
    target_business_id,
    target_sale_id,
    target_client_reference,
    target_reason,
    target_refund_amount,
    target_device_id,
    normalized_items
  );

  update public.idempotency_keys
  set response_status=200,response_body=result,completed_at=now()
  where id=idem.id;

  return result;
end;
$function$;

create or replace function public.fulus_api_create_sale_atomic(
  target_user_id uuid,
  target_business_id uuid,
  target_location_id uuid,
  target_customer_id uuid,
  target_client_reference text,
  target_sale_date timestamptz,
  target_discount numeric,
  target_tax numeric,
  target_amount_paid numeric,
  target_payment_method text,
  target_notes text,
  target_device_id uuid,
  target_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  idem public.idempotency_keys%rowtype;
  request_hash text;
  result jsonb;
  sale_id uuid;
  payment_id uuid;
  actual_paid numeric;
begin
  if not exists(
    select 1 from public.devices
    where id=target_device_id
      and business_id=target_business_id
      and registered_by=target_user_id
      and status='active'
  ) then
    raise exception using errcode='42501',message='Device is not registered or active';
  end if;

  request_hash:=md5(jsonb_build_object(
    'location_id',target_location_id,
    'customer_id',target_customer_id,
    'client_reference',target_client_reference,
    'sale_date',target_sale_date,
    'discount',target_discount,
    'tax',target_tax,
    'amount_paid',target_amount_paid,
    'payment_method',target_payment_method,
    'notes',target_notes,
    'device_id',target_device_id,
    'items',target_items
  )::text);

  insert into public.idempotency_keys(
    business_id,device_id,user_id,key,operation_type,request_hash
  )
  values(
    target_business_id,target_device_id,target_user_id,
    target_client_reference,'sale.create',request_hash
  )
  on conflict(business_id,key) do nothing;

  select * into idem
  from public.idempotency_keys
  where business_id=target_business_id
    and key=target_client_reference
  for update;

  if idem.device_id is distinct from target_device_id
     or idem.user_id is distinct from target_user_id then
    raise exception using errcode='P0009',
      message='Operation id was already used from a different device or account';
  end if;
  if idem.operation_type<>'sale.create'
     or idem.request_hash<>request_hash then
    raise exception using errcode='P0009',
      message='Operation id was already used with a different request';
  end if;
  if idem.completed_at is not null and idem.response_body is not null then
    return idem.response_body;
  end if;

  perform set_config('request.jwt.claim.sub',target_user_id::text,true);
  result:=public.create_sale_atomic(
    target_business_id,target_location_id,target_customer_id,
    target_client_reference,target_sale_date,target_discount,target_tax,
    target_amount_paid,target_payment_method,target_notes,
    target_device_id,target_items
  );

  if coalesce((result->>'status'),'')='applied'
     and coalesce(target_amount_paid,0)>0
     and target_payment_method is not null then
    sale_id:=(result->>'sale_id')::uuid;
    actual_paid:=coalesce(target_amount_paid,0);
    insert into public.sale_payments(
      business_id,sale_id,amount,payment_method,operation_id,created_by,device_id
    )
    values(
      target_business_id,sale_id,actual_paid,target_payment_method,
      target_client_reference||':initial-payment',target_user_id,target_device_id
    )
    on conflict(business_id,operation_id) do nothing
    returning id into payment_id;

    if payment_id is not null then
      insert into public.cash_ledger(
        business_id,location_id,entry_type,amount,direction,
        reference_id,operation_id,created_by,device_id
      )
      values(
        target_business_id,target_location_id,'sale',actual_paid,'in',
        sale_id,target_client_reference||':initial-cash',
        target_user_id,target_device_id
      )
      on conflict(business_id,operation_id) do nothing;
    end if;
  end if;

  update public.idempotency_keys
  set response_status=200,response_body=result,completed_at=now()
  where id=idem.id;

  return result;
end;
$function$;

revoke all on function public.fulus_api_create_return_atomic(
  uuid,uuid,uuid,text,text,numeric,uuid,jsonb
) from public,anon,authenticated;

revoke all on function public.fulus_api_create_sale_atomic(
  uuid,uuid,uuid,uuid,text,timestamptz,numeric,numeric,numeric,text,text,uuid,jsonb
) from public,anon,authenticated;

grant execute on function public.fulus_api_create_return_atomic(
  uuid,uuid,uuid,text,text,numeric,uuid,jsonb
) to service_role;

grant execute on function public.fulus_api_create_sale_atomic(
  uuid,uuid,uuid,uuid,text,timestamptz,numeric,numeric,numeric,text,text,uuid,jsonb
) to service_role;
