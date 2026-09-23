-- Serialize absolute stock adjustment read/target calculation with the stock row mutation.
create or replace function public.set_inventory_quantity(
  target_business_id uuid,target_product_id uuid,target_location_id uuid,
  target_new_quantity integer,target_reason text,target_operation_id text,target_device_id uuid
) returns jsonb language plpgsql security definer set search_path=public as $$
declare product_business_id uuid; tracks_stock boolean; current_quantity integer; quantity_delta integer; actor uuid:=auth.uid();
begin
 if target_new_quantity < 0 then raise exception using errcode='22023',message='Stock quantity cannot be negative'; end if;
 if actor is null then raise exception using errcode='42501',message='Authentication required'; end if;
 if not exists(select 1 from business_memberships where business_id=target_business_id and user_id=actor and status='active') then raise exception using errcode='42501',message='User is not an active member of this business'; end if;
 if not exists(select 1 from devices where id=target_device_id and business_id=target_business_id and status='active') then raise exception using errcode='42501',message='Device is not registered or active'; end if;
 select p.business_id,p.tracks_stock into product_business_id,tracks_stock from products p where p.id=target_product_id for update;
 if product_business_id is null or product_business_id<>target_business_id then raise exception using errcode='P0002',message='Product does not belong to this business'; end if;
 if not coalesce(tracks_stock,false) then raise exception using errcode='22023',message='Product does not track stock'; end if;
 if not exists(select 1 from locations l where l.id=target_location_id and l.business_id=target_business_id) then raise exception using errcode='P0002',message='Location does not belong to this business'; end if;
 insert into product_stock_levels(product_id,location_id,current_stock,updated_at) values(target_product_id,target_location_id,0,now()) on conflict(product_id,location_id) do nothing;
 select coalesce(ps.current_stock,0) into current_quantity from product_stock_levels ps where ps.product_id=target_product_id and ps.location_id=target_location_id for update;
 quantity_delta:=target_new_quantity-coalesce(current_quantity,0);
 if quantity_delta=0 then return jsonb_build_object('status','already_applied','current_stock',current_quantity,'server_authoritative',true); end if;
 return apply_inventory_adjustment(target_business_id,target_product_id,target_location_id,quantity_delta,target_reason,target_operation_id,target_device_id);
end;
$$;
