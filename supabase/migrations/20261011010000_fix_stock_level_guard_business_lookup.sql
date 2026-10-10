-- Fix the stock-level guard: product_stock_levels has no business_id column.
-- Tenant ownership must be derived from the referenced product and location.
-- Correct the stock-level location guard: product_stock_levels has no business_id column.
-- Enforce tenant isolation using the authoritative business IDs of the product and location.
-- Close cross-business reference gaps in the location ownership guards.
-- Location equality alone is insufficient: privileged direct writes must not
-- be able to connect rows from different businesses even if a caller supplies
-- otherwise matching IDs. Existing historical rows are not rewritten.
create or replace function public.guard_location_transaction_references()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_customer_location uuid;
  v_customer_business uuid;
  v_product_location uuid;
  v_product_business uuid;
  v_sale_location uuid;
  v_sale_business uuid;
  v_location_business uuid;
begin
  if tg_table_name = 'sales' then
    select l.business_id into v_location_business
    from public.locations l
    where l.id = new.location_id;

    if v_location_business is distinct from new.business_id then
      raise exception using errcode = '42501',
        message = 'Sale location does not belong to the sale business';
    end if;

    if new.customer_id is not null
       and (tg_op = 'INSERT' or new.customer_id is distinct from old.customer_id
            or new.location_id is distinct from old.location_id
            or new.business_id is distinct from old.business_id) then
      select c.location_id, c.business_id
        into v_customer_location, v_customer_business
      from public.customers c
      where c.id = new.customer_id;

      if v_customer_business is distinct from new.business_id
         or v_customer_location is null
         or v_customer_location is distinct from new.location_id then
        raise exception using errcode = '42501',
          message = 'Customer is not owned by the sale business and location';
      end if;
    end if;
    return new;

  elsif tg_table_name = 'sale_items' then
    if new.product_id is null then return new; end if;

    select s.location_id, s.business_id
      into v_sale_location, v_sale_business
    from public.sales s
    where s.id = new.sale_id;

    select p.location_id, p.business_id
      into v_product_location, v_product_business
    from public.products p
    where p.id = new.product_id;

    if v_product_location is null
       or v_sale_location is null
       or v_product_business is distinct from v_sale_business
       or v_product_location is distinct from v_sale_location then
      raise exception using errcode = '42501',
        message = 'Product is not owned by the sale business and location';
    end if;
    return new;

  elsif tg_table_name = 'product_stock_levels' then
    select p.location_id, p.business_id
      into v_product_location, v_product_business
    from public.products p
    where p.id = new.product_id;

    select l.business_id into v_location_business
    from public.locations l
    where l.id = new.location_id;

    if v_product_location is null
       or v_product_location is distinct from new.location_id
       or v_product_business is distinct from v_location_business then
      raise exception using errcode = '42501',
        message = 'Stock product and location must belong to the same business and owner location';
    end if;
    return new;

  elsif tg_table_name = 'inventory_movements' then
    select p.location_id, p.business_id
      into v_product_location, v_product_business
    from public.products p
    where p.id = new.product_id;

    select l.business_id into v_location_business
    from public.locations l
    where l.id = new.location_id;

    if v_product_location is null
       or v_product_location is distinct from new.location_id
       or v_product_business is distinct from v_location_business then
      raise exception using errcode = '42501',
        message = 'Movement product and location must belong to the same business and owner location';
    end if;
    return new;

  elsif tg_table_name = 'returns' then
    select s.location_id, s.business_id
      into v_sale_location, v_sale_business
    from public.sales s
    where s.id = new.sale_id;

    if v_sale_location is null
       or v_sale_business is distinct from new.business_id then
      raise exception using errcode = '42501',
        message = 'Return sale must belong to the return business';
    end if;

    if new.customer_id is not null then
      select c.location_id, c.business_id
        into v_customer_location, v_customer_business
      from public.customers c
      where c.id = new.customer_id;

      if v_customer_location is null
         or v_customer_business is distinct from new.business_id
         or v_customer_location is distinct from v_sale_location then
        raise exception using errcode = '42501',
          message = 'Return customer and sale must belong to the same business and location';
      end if;
    end if;
    return new;

  elsif tg_table_name = 'customer_ledger_entries' then
    select c.location_id, c.business_id
      into v_customer_location, v_customer_business
    from public.customers c
    where c.id = new.customer_id;

    if v_customer_location is null
       or v_customer_business is distinct from new.business_id then
      raise exception using errcode = '42501',
        message = 'Customer ledger customer must belong to the ledger business';
    end if;

    if new.sale_id is not null then
      select s.location_id, s.business_id
        into v_sale_location, v_sale_business
      from public.sales s
      where s.id = new.sale_id;

      if v_sale_business is distinct from new.business_id
         or v_sale_location is distinct from v_customer_location then
        raise exception using errcode = '42501',
          message = 'Customer ledger sale must belong to the customer business and location';
      end if;
    end if;
    return new;
  end if;

  return new;
end;
$function$;

revoke all on function public.guard_location_transaction_references()
  from public, anon, authenticated;
