-- Phase 2 field parity: fields already present in local syncable entities
-- must exist in the authoritative cloud representation as well.

alter table public.customers
  add column if not exists notes text;

alter table public.expenses
  add column if not exists payment_method text;

create or replace function public.create_customer(
  target_business_id uuid,
  target_name text,
  target_phone text,
  target_email text,
  target_address text,
  target_credit_limit numeric,
  target_notes text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare actor uuid:=auth.uid(); cid uuid;
begin
 if actor is null then raise exception using errcode='42501',message='Authentication required'; end if;
 if not public.has_permission(target_business_id,'customers.manage') then raise exception using errcode='42501',message='Customer management permission required'; end if;
 if target_name is null or length(trim(target_name))=0 then raise exception using errcode='22023',message='Customer name required'; end if;
 insert into public.customers(business_id,name,phone,email,address,credit_limit,notes)
 values(target_business_id,trim(target_name),nullif(trim(target_phone),''),nullif(trim(target_email),''),nullif(trim(target_address),''),greatest(coalesce(target_credit_limit,0),0),nullif(trim(target_notes),''))
 returning id into cid;
 perform public._fulus_append_change(target_business_id,'customer',cid,'upsert',(
   select to_jsonb(c) from public.customers c where c.id=cid
 ));
 return jsonb_build_object('status','applied','customer_id',cid,'server_authoritative',true);
end
$$;

create or replace function public.record_expense(
  target_business_id uuid,
  target_location_id uuid,
  target_amount numeric,
  target_category text,
  target_description text,
  target_operation_id text,
  target_device_id uuid,
  target_payment_method text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare actor uuid:=auth.uid(); eid uuid;
begin
 if actor is null or not public.has_permission(target_business_id,'finance.manage') then
   raise exception using errcode='42501',message='Finance permission required';
 end if;
 if not exists (
   select 1 from public.locations l
   where l.id=target_location_id and l.business_id=target_business_id and l.status='active'
 ) then
   raise exception using errcode='22023',message='Location does not belong to this business';
 end if;
 insert into public.expenses(
   business_id,location_id,amount,category,description,operation_id,created_by,device_id,payment_method
 )
 values(
   target_business_id,target_location_id,target_amount,trim(target_category),
   target_description,target_operation_id,actor,target_device_id,target_payment_method
 )
 on conflict(business_id,operation_id) do nothing returning id into eid;
 if eid is null then
   return jsonb_build_object('status','already_applied','server_authoritative',true);
 end if;
 insert into public.cash_ledger(
   business_id,location_id,entry_type,amount,direction,reference_id,operation_id,created_by,device_id
 )
 values(target_business_id,target_location_id,'expense',target_amount,'out',eid,target_operation_id||':cash',actor,target_device_id);
 perform public._fulus_append_change(
   target_business_id,'expense',eid,'upsert',
   (select to_jsonb(e) from public.expenses e where e.id=eid)
 );
 return jsonb_build_object('status','applied','expense_id',eid,'server_authoritative',true);
end
$$;

create or replace function public.fulus_api_create_customer(
  target_user_id uuid, target_business_id uuid, target_name text, target_phone text,
  target_email text, target_address text, target_credit_limit numeric, target_notes text
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);
  return public.create_customer(
    target_business_id,target_name,target_phone,target_email,target_address,target_credit_limit,target_notes
  );
end;
$$;

create or replace function public.fulus_api_record_expense(
  target_user_id uuid, target_business_id uuid, target_location_id uuid, target_amount numeric,
  target_category text, target_description text, target_operation_id text, target_device_id uuid,
  target_payment_method text
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);
  return public.record_expense(
    target_business_id,target_location_id,target_amount,target_category,target_description,
    target_operation_id,target_device_id,target_payment_method
  );
end;
$$;

revoke all on function public.fulus_api_create_customer(uuid,uuid,text,text,text,text,numeric,text) from public,anon,authenticated;
revoke all on function public.fulus_api_record_expense(uuid,uuid,uuid,numeric,text,text,text,uuid,text) from public,anon,authenticated;
grant execute on function public.fulus_api_create_customer(uuid,uuid,text,text,text,text,numeric,text) to service_role;
grant execute on function public.fulus_api_record_expense(uuid,uuid,uuid,numeric,text,text,text,uuid,text) to service_role;
