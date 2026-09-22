-- Quick Sale cloud-sync support.
--
-- Catalog-backed sale lines keep product_id and derive cost/stock from the
-- authoritative product. Quick Sale lines have no catalog product, so they
-- persist their description and captured cost and never affect inventory.

alter table public.sale_items
  alter column product_id drop not null;

alter table public.sale_items
  add column if not exists description text not null default '';

create or replace function public.create_sale_atomic(
  target_business_id uuid,
  target_location_id uuid,
  target_customer_id uuid,
  target_client_reference text,
  target_sale_date timestamp with time zone,
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
set search_path to ''
as $function$
declare
  actor uuid := coalesce(
    auth.uid(),
    (
      select d.registered_by
      from public.devices d
      where d.id = target_device_id
        and d.business_id = target_business_id
        and d.status = 'active'
    )
  );
  existing public.sales%rowtype;
  sale_id uuid;
  invoice text;
  item jsonb;
  product public.products%rowtype;
  product_id_text text;
  quick_description text;
  line_total numeric;
  subtotal numeric := 0;
  total numeric;
  paid numeric;
  updated_rows int;
  balance_due numeric;
  ledger_id uuid;
begin
  if actor is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  if not exists (
    select 1 from public.business_memberships bm
    join public.role_permissions rp on rp.role_id = bm.role_id
    join public.permissions p on p.id = rp.permission_id
    where bm.business_id = target_business_id
      and bm.user_id = actor
      and bm.status = 'active'
      and p.code = 'sales.create'
  ) then
    raise exception using errcode = '42501', message = 'Sales permission required';
  end if;

  if target_client_reference is null or length(trim(target_client_reference)) = 0 then
    raise exception using errcode = '22023', message = 'client_reference required';
  end if;

  select * into existing from public.sales
  where business_id = target_business_id
    and client_reference = target_client_reference;

  if existing.id is not null then
    return jsonb_build_object(
      'status', 'already_applied',
      'sale_id', existing.id,
      'invoice_number', existing.invoice_number,
      'total', existing.total,
      'amount_paid', existing.amount_paid
    );
  end if;

  if target_device_id is not null and not exists (
    select 1 from public.devices
    where id = target_device_id and business_id = target_business_id and status = 'active'
  ) then
    raise exception using errcode = '42501', message = 'Device is not active for this business';
  end if;

  if not exists (
    select 1 from public.locations
    where id = target_location_id and business_id = target_business_id
  ) then
    raise exception using errcode = '22023', message = 'Location does not belong to business';
  end if;

  if target_customer_id is not null and not exists (
    select 1 from public.customers
    where id = target_customer_id and business_id = target_business_id and is_active = true
  ) then
    raise exception using errcode = '22023', message = 'Customer does not belong to business';
  end if;

  if target_items is null or jsonb_array_length(target_items) = 0 then
    raise exception using errcode = '22023', message = 'Sale requires at least one item';
  end if;

  for item in select * from jsonb_array_elements(target_items) loop
    product_id_text := nullif(trim(item->>'product_id'), '');
    product := null;

    if product_id_text is not null then
      select * into product
      from public.products
      where id = product_id_text::uuid
        and business_id = target_business_id
        and deleted_at is null
        and is_active = true;

      if product.id is null then
        raise exception using errcode = '22023', message = 'Product does not belong to business';
      end if;
    else
      quick_description := nullif(trim(item->>'description'), '');
      if quick_description is null then
        raise exception using errcode = '22023', message = 'Quick Sale requires a description';
      end if;
    end if;

    if (item->>'quantity')::integer <= 0 then
      raise exception using errcode = '22023', message = 'Quantity must be positive';
    end if;

    line_total := round(
      (item->>'quantity')::numeric *
      coalesce(
        (item->>'unit_price')::numeric,
        case when product.id is not null then product.selling_price else null end
      ),
      2
    );

    if line_total is null then
      raise exception using errcode = '22023', message = 'Sale item requires a unit price';
    end if;

    subtotal := subtotal + line_total;
  end loop;

  total := greatest(0, round(subtotal - coalesce(target_discount, 0) + coalesce(target_tax, 0), 2));
  paid := least(greatest(coalesce(target_amount_paid, 0), 0), total);
  balance_due := round(total - paid, 2);

  if balance_due > 0 and target_customer_id is null then
    raise exception using errcode = '22023', message = 'Customer is required for unpaid sale';
  end if;

  if balance_due > 0 and not exists (
    select 1 from public.business_memberships bm
    join public.role_permissions rp on rp.role_id = bm.role_id
    join public.permissions p on p.id = rp.permission_id
    where bm.business_id = target_business_id
      and bm.user_id = actor
      and bm.status = 'active'
      and p.code = 'credit.manage'
  ) then
    raise exception using errcode = '42501', message = 'Credit management permission required';
  end if;

  invoice := 'INV-' || to_char(now(), 'YYYYMMDDHH24MISS') || '-' ||
             upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));

  insert into public.sales(
    business_id, location_id, customer_id, cashier_user_id, client_reference,
    invoice_number, sale_date, subtotal, discount, tax, total, amount_paid,
    payment_method, notes
  )
  values(
    target_business_id, target_location_id, target_customer_id, actor,
    target_client_reference, invoice, target_sale_date, subtotal,
    coalesce(target_discount, 0), coalesce(target_tax, 0), total, paid,
    target_payment_method, target_notes
  )
  returning id into sale_id;

  for item in select * from jsonb_array_elements(target_items) loop
    product_id_text := nullif(trim(item->>'product_id'), '');
    product := null;

    if product_id_text is not null then
      select * into product from public.products
      where id = product_id_text::uuid and business_id = target_business_id;
    end if;

    insert into public.sale_items(
      sale_id, product_id, description, quantity, unit_price, cost_price_at_sale
    )
    values(
      sale_id,
      product.id,
      coalesce(
        nullif(trim(item->>'description'), ''),
        case when product.id is not null then product.name else '' end
      ),
      (item->>'quantity')::integer,
      coalesce(
        (item->>'unit_price')::numeric,
        case when product.id is not null then product.selling_price else 0 end
      ),
      case
        when product.id is not null then product.cost_price
        else coalesce((item->>'cost_price_at_sale')::numeric, 0)
      end
    );

    if product.id is not null and product.tracks_stock then
      update public.product_stock_levels
      set current_stock = current_stock - (item->>'quantity')::integer,
          updated_at = now()
      where product_id = product.id
        and location_id = target_location_id
        and current_stock >= (item->>'quantity')::integer;

      get diagnostics updated_rows = row_count;
      if updated_rows <> 1 then
        raise exception using errcode = '22013', message = 'Insufficient stock';
      end if;

      insert into public.inventory_movements(
        business_id, product_id, location_id, quantity_delta, reason,
        operation_id, user_id, device_id
      )
      values(
        target_business_id, product.id, target_location_id,
        -(item->>'quantity')::integer, 'sale ' || invoice,
        target_client_reference || ':stock:' || product.id, actor, target_device_id
      );
    end if;
  end loop;

  if balance_due > 0 then
    update public.customers
    set outstanding_balance = round(outstanding_balance + balance_due, 2),
        updated_at = now()
    where id = target_customer_id;

    insert into public.customer_ledger_entries(
      business_id, customer_id, sale_id, amount, operation_id,
      entry_type, created_by, device_id, note
    )
    values(
      target_business_id, target_customer_id, sale_id, balance_due,
      target_client_reference || ':credit', 'credit_sale', actor,
      target_device_id, 'Credit from ' || invoice
    )
    returning id into ledger_id;

    perform public._fulus_append_change(
      target_business_id, 'customer_ledger', ledger_id, 'upsert',
      jsonb_build_object(
        'id', ledger_id, 'customer_id', target_customer_id,
        'sale_id', sale_id, 'entry_type', 'credit_sale', 'amount', balance_due
      )
    );
  end if;

  perform public._fulus_append_change(
    target_business_id, 'sale', sale_id, 'upsert',
    jsonb_build_object(
      'id', sale_id, 'client_reference', target_client_reference,
      'invoice_number', invoice, 'subtotal', subtotal,
      'discount', coalesce(target_discount, 0), 'tax', coalesce(target_tax, 0),
      'total', total, 'amount_paid', paid, 'balance_due', balance_due
    )
  );

  return jsonb_build_object(
    'status', 'applied', 'sale_id', sale_id, 'invoice_number', invoice,
    'subtotal', subtotal, 'total', total, 'amount_paid', paid,
    'balance_due', balance_due, 'server_authoritative', true
  );
end
$function$;
