-- Make products and customers location-owned without guessing ownership
-- for legacy records that were historically business-wide.
alter table public.products
  add column if not exists location_id uuid
  references public.locations(id) on delete restrict;

alter table public.customers
  add column if not exists location_id uuid
  references public.locations(id) on delete restrict;

create table if not exists public.location_ownership_review (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  entity_type text not null check (entity_type in ('product', 'customer')),
  entity_id uuid not null,
  candidate_location_ids uuid[] not null default '{}'::uuid[],
  classification text not null check (classification in ('ambiguous', 'unassigned')),
  reason text not null,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  unique (entity_type, entity_id)
);

alter table public.location_ownership_review enable row level security;
revoke all on public.location_ownership_review from public, anon, authenticated;
grant select, insert, update, delete on public.location_ownership_review to service_role;

-- Only auto-assign when every observed location reference agrees. References
-- include stock, movements and historical sales. A product used in multiple
-- locations remains unassigned for explicit review.
with evidence as (
  select p.id as product_id, p.business_id, ps.location_id
  from public.products p
  join public.product_stock_levels ps on ps.product_id = p.id
  join public.locations l on l.id = ps.location_id and l.business_id = p.business_id
  union
  select p.id, p.business_id, im.location_id
  from public.products p
  join public.inventory_movements im on im.product_id = p.id
  join public.locations l on l.id = im.location_id and l.business_id = p.business_id
  union
  select p.id, p.business_id, s.location_id
  from public.products p
  join public.sale_items si on si.product_id = p.id
  join public.sales s on s.id = si.sale_id and s.business_id = p.business_id
  join public.locations l on l.id = s.location_id and l.business_id = p.business_id
), candidates as (
  select product_id, business_id,
         array_agg(distinct location_id order by location_id) as locations
  from evidence
  where location_id is not null
  group by product_id, business_id
)
update public.products p
set location_id = c.locations[1]
from candidates c
where p.id = c.product_id
  and p.business_id = c.business_id
  and p.location_id is null
  and cardinality(c.locations) = 1;

with evidence as (
  select p.id as product_id, p.business_id, ps.location_id
  from public.products p
  join public.product_stock_levels ps on ps.product_id = p.id
  join public.locations l on l.id = ps.location_id and l.business_id = p.business_id
  union
  select p.id, p.business_id, im.location_id
  from public.products p
  join public.inventory_movements im on im.product_id = p.id
  join public.locations l on l.id = im.location_id and l.business_id = p.business_id
  union
  select p.id, p.business_id, s.location_id
  from public.products p
  join public.sale_items si on si.product_id = p.id
  join public.sales s on s.id = si.sale_id and s.business_id = p.business_id
  join public.locations l on l.id = s.location_id and l.business_id = p.business_id
), candidates as (
  select product_id, business_id,
         array_agg(distinct location_id order by location_id) as locations
  from evidence
  where location_id is not null
  group by product_id, business_id
)
insert into public.location_ownership_review(
  business_id, entity_type, entity_id, candidate_location_ids,
  classification, reason
)
select p.business_id, 'product', p.id, coalesce(c.locations, '{}'::uuid[]),
       case when cardinality(coalesce(c.locations, '{}'::uuid[])) > 1
            then 'ambiguous' else 'unassigned' end,
       case when cardinality(coalesce(c.locations, '{}'::uuid[])) > 1
            then 'Historical stock, movement or sale references span multiple locations'
            else 'No reliable single-location evidence exists for this legacy product' end
from public.products p
left join candidates c on c.product_id = p.id and c.business_id = p.business_id
where p.location_id is null
on conflict (entity_type, entity_id) do nothing;

-- Customer ownership is inferred only when all linked historical sales and
-- returns point to exactly one location. Repayment-only or unused customers
-- without reliable location evidence remain unassigned.
with evidence as (
  select c.id as customer_id, c.business_id, s.location_id
  from public.customers c
  join public.sales s on s.customer_id = c.id and s.business_id = c.business_id
  join public.locations l on l.id = s.location_id and l.business_id = c.business_id
  union
  select c.id, c.business_id, s.location_id
  from public.customers c
  join public.returns r on r.customer_id = c.id and r.business_id = c.business_id
  join public.sales s on s.id = r.sale_id and s.business_id = c.business_id
  join public.locations l on l.id = s.location_id and l.business_id = c.business_id
  union
  select c.id, c.business_id, s.location_id
  from public.customers c
  join public.customer_ledger_entries le on le.customer_id = c.id and le.business_id = c.business_id
  join public.sales s on s.id = le.sale_id and s.business_id = c.business_id
  join public.locations l on l.id = s.location_id and l.business_id = c.business_id
  where le.sale_id is not null
), candidates as (
  select customer_id, business_id,
         array_agg(distinct location_id order by location_id) as locations
  from evidence
  where location_id is not null
  group by customer_id, business_id
)
update public.customers c
set location_id = candidates.locations[1]
from candidates
where c.id = candidates.customer_id
  and c.business_id = candidates.business_id
  and c.location_id is null
  and cardinality(candidates.locations) = 1;

with evidence as (
  select c.id as customer_id, c.business_id, s.location_id
  from public.customers c
  join public.sales s on s.customer_id = c.id and s.business_id = c.business_id
  join public.locations l on l.id = s.location_id and l.business_id = c.business_id
  union
  select c.id, c.business_id, s.location_id
  from public.customers c
  join public.returns r on r.customer_id = c.id and r.business_id = c.business_id
  join public.sales s on s.id = r.sale_id and s.business_id = c.business_id
  join public.locations l on l.id = s.location_id and l.business_id = c.business_id
  union
  select c.id, c.business_id, s.location_id
  from public.customers c
  join public.customer_ledger_entries le on le.customer_id = c.id and le.business_id = c.business_id
  join public.sales s on s.id = le.sale_id and s.business_id = c.business_id
  join public.locations l on l.id = s.location_id and l.business_id = c.business_id
  where le.sale_id is not null
), candidates as (
  select customer_id, business_id,
         array_agg(distinct location_id order by location_id) as locations
  from evidence
  where location_id is not null
  group by customer_id, business_id
)
insert into public.location_ownership_review(
  business_id, entity_type, entity_id, candidate_location_ids,
  classification, reason
)
select c.business_id, 'customer', c.id, coalesce(candidates.locations, '{}'::uuid[]),
       case when cardinality(coalesce(candidates.locations, '{}'::uuid[])) > 1
            then 'ambiguous' else 'unassigned' end,
       case when cardinality(coalesce(candidates.locations, '{}'::uuid[])) > 1
            then 'Historical customer transactions span multiple locations'
            else 'No reliable single-location evidence exists for this legacy customer' end
from public.customers c
left join candidates on candidates.customer_id = c.id and candidates.business_id = c.business_id
where c.location_id is null
on conflict (entity_type, entity_id) do nothing;

drop index if exists public.products_business_sku_uq;
create unique index if not exists products_location_sku_uq
  on public.products (business_id, location_id, lower(sku))
  where deleted_at is null and location_id is not null;

create index if not exists products_business_location_updated_idx
  on public.products (business_id, location_id, updated_at desc);

create index if not exists customers_business_location_updated_idx
  on public.customers (business_id, location_id, updated_at desc);

create index if not exists location_ownership_review_pending_idx
  on public.location_ownership_review (business_id, entity_type, classification)
  where reviewed_at is null;

-- Service-role API wrapper used by catalog_list. Set the actor explicitly
-- because the Edge Function calls Postgres with its service-role client.
create or replace function public.fulus_api_require_location_access(
  target_user_id uuid,
  target_business_id uuid,
  target_location_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);
  perform public.require_location_access(target_business_id, target_location_id);
end;
$function$;

revoke all on function public.fulus_api_require_location_access(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.fulus_api_require_location_access(uuid, uuid, uuid)
  to service_role;

-- Reassert the product catalog mutation contract with location ownership.
-- Dynamic patching preserves the deployed OCC/idempotency/photo/stock contract
-- while failing the migration if any expected source fragment has drifted.
do $patch$
declare
  v_definition text;
  v_patched text;
  v_old text;
  v_new text;
begin
  v_definition := pg_catalog.pg_get_functiondef(
    'public.cloud_catalog_mutate(uuid,uuid,uuid,text,text,text,uuid,jsonb,bigint,text)'::regprocedure
  );
  v_patched := v_definition;

  v_old := 'begin' || E'\n  if target_operation_id is null';
  v_new := 'begin' || E'\n  perform set_config(''request.jwt.claim.sub'', target_user_id::text, true);' ||
    E'\n  if target_operation_id is null';
  v_patched := replace(v_patched, v_old, v_new);

  v_old := E'  if target_id is not null then\n    case target_entity';
  v_new := E'  if target_entity = ''products'' and target_id is not null then\n' ||
    E'    select p.location_id into initial_location_id from public.products p\n' ||
    E'    where p.id = target_id and p.business_id = target_business_id for update;\n' ||
    E'    if initial_location_id is null then\n' ||
    E'      raise exception using errcode = ''42501'', message = ''Product location ownership is unresolved'';\n' ||
    E'    end if;\n' ||
    E'    perform public.require_location_access(target_business_id, initial_location_id);\n' ||
    E'    if target_operation = ''upsert'' and target_item ? ''location_id''\n' ||
    E'       and nullif(target_item->>''location_id'', '''')::uuid is distinct from initial_location_id then\n' ||
    E'      raise exception using errcode = ''42501'', message = ''Product ownership cannot be moved by catalog update'';\n' ||
    E'    end if;\n' ||
    E'  end if;\n' ||
    E'  if target_id is not null then\n    case target_entity';
  v_patched := replace(v_patched, v_old, v_new);

  v_old := E'      when ''products'' then\n        if target_id is null then\n          insert into public.products(\n            business_id,name,sku,barcode,category_id,supplier_id,\n            cost_price,selling_price,low_stock_threshold,is_active,photo_path\n          )\n          values(\n            target_business_id,trim(target_item->>''name''),target_item->>''sku'',';
  v_new := E'      when ''products'' then\n        if target_id is null then\n' ||
    E'          initial_location_id := nullif(target_item->>''location_id'','''')::uuid;\n' ||
    E'          if initial_location_id is null then\n' ||
    E'            raise exception using errcode = ''22023'', message = ''Product location_id is required'';\n' ||
    E'          end if;\n' ||
    E'          perform public.require_location_access(target_business_id, initial_location_id);\n' ||
    E'          insert into public.products(\n' ||
    E'            business_id,location_id,name,sku,barcode,category_id,supplier_id,\n' ||
    E'            cost_price,selling_price,low_stock_threshold,is_active,photo_path\n' ||
    E'          )\n' ||
    E'          values(\n' ||
    E'            target_business_id,initial_location_id,trim(target_item->>''name''),target_item->>''sku'',';
  v_patched := replace(v_patched, v_old, v_new);

  if v_patched = v_definition then
    raise exception 'cloud_catalog_mutate location ownership patch did not apply';
  end if;
  if position('business_id,location_id,name,sku,barcode' in v_patched) = 0
     or position('require_location_access(target_business_id, initial_location_id)' in v_patched) = 0
     or position('set_config(''request.jwt.claim.sub''' in v_patched) = 0 then
    raise exception 'cloud_catalog_mutate location ownership contract is incomplete';
  end if;

  execute v_patched;
end;
$patch$;

-- Location-owned customer create contract. Legacy overloads remain available
-- only for historical internal compatibility; the current Edge API uses this
-- location-required wrapper.
create or replace function public.fulus_api_create_customer(
  target_user_id uuid,
  target_business_id uuid,
  target_location_id uuid,
  target_name text,
  target_phone text,
  target_email text,
  target_address text,
  target_credit_limit numeric,
  target_notes text,
  target_device_id uuid,
  target_operation_id text,
  target_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  idem public.idempotency_keys%rowtype;
  customer_id uuid;
  response jsonb;
begin
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);
  if not public.has_permission(target_business_id, 'customers.manage') then
    raise exception using errcode='42501', message='Customer management permission required';
  end if;
  perform public.require_location_access(target_business_id, target_location_id);
  if not exists (
    select 1 from public.devices d
    where d.id = target_device_id
      and d.business_id = target_business_id
      and d.registered_by = target_user_id
      and d.status = 'active'
  ) then
    raise exception using errcode='42501', message='Device is not registered or active';
  end if;
  if target_name is null or length(trim(target_name)) = 0 then
    raise exception using errcode='22023', message='Customer name required';
  end if;
  if target_operation_id is null or length(trim(target_operation_id)) = 0 then
    raise exception using errcode='22023', message='Customer operation_id required';
  end if;

  insert into public.idempotency_keys(
    business_id, device_id, user_id, key, operation_type, request_hash
  ) values (
    target_business_id, target_device_id, target_user_id, target_operation_id,
    'customer.create', target_request_hash
  ) on conflict (business_id, key) do nothing;

  select * into idem
  from public.idempotency_keys
  where business_id = target_business_id and key = target_operation_id
  for update;

  if idem.device_id is distinct from target_device_id
     or idem.user_id is distinct from target_user_id then
    raise exception using errcode='P0009',
      message='Operation id was already used from a different device or account';
  end if;
  if idem.operation_type <> 'customer.create'
     or idem.request_hash <> target_request_hash then
    raise exception using errcode='P0009',
      message='Operation id was already used with a different request';
  end if;
  if idem.completed_at is not null and idem.response_body is not null then
    return idem.response_body;
  end if;

  insert into public.customers(
    business_id, location_id, name, phone, email, address,
    credit_limit, notes
  ) values (
    target_business_id, target_location_id, trim(target_name),
    nullif(trim(target_phone), ''), nullif(trim(target_email), ''),
    nullif(trim(target_address), ''),
    greatest(coalesce(target_credit_limit, 0), 0), nullif(trim(target_notes), '')
  ) returning id into customer_id;

  perform public._fulus_append_change(
    target_business_id, 'customer', customer_id, 'upsert',
    (select to_jsonb(c) from public.customers c where c.id = customer_id)
  );

  response := jsonb_build_object('data', jsonb_build_object(
    'status', 'applied', 'customer_id', customer_id, 'entity_id', customer_id,
    'server_authoritative', true
  ));
  update public.idempotency_keys
  set response_status = 201, response_body = response, completed_at = now()
  where id = idem.id;
  return response;
end;
$function$;

revoke all on function public.fulus_api_create_customer(
  uuid, uuid, uuid, text, text, text, text, numeric, text, uuid, text, text
) from public, anon, authenticated;
grant execute on function public.fulus_api_create_customer(
  uuid, uuid, uuid, text, text, text, text, numeric, text, uuid, text, text
) to service_role;

-- Customer update is bound to its immutable owner location and retains OCC,
-- durable idempotency, and canonical change-feed publication.
create or replace function public.fulus_api_update_customer(
  target_user_id uuid,
  target_business_id uuid,
  target_device_id uuid,
  target_operation_id text,
  target_customer_id uuid,
  target_location_id uuid,
  target_name text,
  target_phone text,
  target_email text,
  target_address text,
  target_notes text,
  target_credit_limit numeric,
  target_is_active boolean,
  target_base_cursor bigint,
  target_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  idem public.idempotency_keys%rowtype;
  customer_row public.customers%rowtype;
  response jsonb;
begin
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);
  if not public.has_permission(target_business_id, 'customers.manage') then
    raise exception using errcode='42501', message='Customer management permission required';
  end if;
  if not exists (
    select 1 from public.devices
    where id = target_device_id
      and business_id = target_business_id
      and registered_by = target_user_id
      and status = 'active'
  ) then
    raise exception using errcode='42501', message='Device is not registered or active';
  end if;
  if target_name is null or length(trim(target_name)) = 0 then
    raise exception using errcode='22023', message='Customer name required';
  end if;

  insert into public.idempotency_keys(
    business_id, device_id, user_id, key, operation_type, request_hash
  ) values (
    target_business_id, target_device_id, target_user_id, target_operation_id,
    'customer.update', target_request_hash
  ) on conflict (business_id, key) do nothing;

  select * into idem
  from public.idempotency_keys
  where business_id = target_business_id and key = target_operation_id
  for update;

  if idem.device_id is distinct from target_device_id
     or idem.user_id is distinct from target_user_id
     or idem.operation_type <> 'customer.update'
     or idem.request_hash <> target_request_hash then
    raise exception using errcode='P0009',
      message='Operation id was already used with a different request';
  end if;
  if idem.completed_at is not null and idem.response_body is not null then
    return idem.response_body;
  end if;

  select * into customer_row
  from public.customers
  where id = target_customer_id and business_id = target_business_id
  for update;
  if not found then
    raise exception using errcode='P0002', message='Customer not found';
  end if;
  if customer_row.location_id is null
     or customer_row.location_id is distinct from target_location_id then
    raise exception using errcode='42501', message='Customer is not owned by the requested location';
  end if;
  perform public.require_location_access(target_business_id, customer_row.location_id);

  if target_base_cursor is not null and exists (
    select 1 from public.sync_changes
    where business_id = target_business_id
      and entity_type = 'customer'
      and entity_id = target_customer_id
      and sequence > target_base_cursor
  ) then
    raise exception using errcode='P0008',
      message='SYNC_CONFLICT: Customer changed on another device after this edit was created';
  end if;

  update public.customers
  set name = trim(target_name),
      phone = nullif(trim(target_phone), ''),
      email = nullif(trim(target_email), ''),
      address = nullif(trim(target_address), ''),
      notes = nullif(trim(target_notes), ''),
      credit_limit = greatest(coalesce(target_credit_limit, 0), 0),
      is_active = coalesce(target_is_active, true),
      updated_at = now()
  where id = target_customer_id and business_id = target_business_id
  returning * into customer_row;

  perform public._fulus_append_change(
    target_business_id, 'customer', customer_row.id, 'upsert', to_jsonb(customer_row)
  );
  response := jsonb_build_object('data', jsonb_build_object(
    'entity_id', customer_row.id, 'customer_id', customer_row.id,
    'status', 'applied', 'server_authoritative', true
  ));
  update public.idempotency_keys
  set response_status = 200, response_body = response, completed_at = now()
  where id = idem.id;
  return response;
end;
$function$;

revoke all on function public.fulus_api_update_customer(
  uuid, uuid, uuid, text, uuid, uuid, text, text, text, text, text, numeric, boolean, bigint, text
) from public, anon, authenticated;
grant execute on function public.fulus_api_update_customer(
  uuid, uuid, uuid, text, uuid, uuid, text, text, text, text, text, numeric, boolean, bigint, text
) to service_role;



-- Employee restore must not bootstrap other locations' products, customers,
-- or their ledger history. Patch the existing snapshot builder in-place so
-- its unrelated schema sections and authorization invariants remain intact.
do $employee_restore_patch$
declare
  v_definition text;
  v_patched text;
  v_old text;
  v_new text;
begin
  v_definition := pg_catalog.pg_get_functiondef(
    'public.build_fulus_employee_restore_snapshot(uuid,uuid)'::regprocedure
  );
  v_patched := v_definition;

  v_old := E'      SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id)\n      FROM public.products t\n      WHERE t.business_id = p_business_id\n    ), ''[]''::jsonb),\n    ''categories''';
  v_new := E'      SELECT jsonb_agg(scoped.row_json ORDER BY scoped.row_json->>''id'')\n' ||
    E'      FROM (\n' ||
    E'        SELECT to_jsonb(t) AS row_json\n' ||
    E'        FROM public.products t\n' ||
    E'        WHERE t.business_id = p_business_id\n' ||
    E'          AND t.location_id = v_location_id\n' ||
    E'        UNION ALL\n' ||
    E'        SELECT to_jsonb(p) || pg_catalog.jsonb_build_object(\n' ||
    E'          ''name'', ''Historical product'', ''sku'', ''historical-'' || p.id::text,\n' ||
    E'          ''barcode'', null, ''category_id'', null, ''supplier_id'', null,\n' ||
    E'          ''cost_price'', 0, ''selling_price'', 0, ''low_stock_threshold'', 0,\n' ||
    E'          ''photo_path'', null, ''location_id'', null, ''deleted_at'', pg_catalog.now(),\n' ||
    E'          ''is_active'', false\n' ||
    E'        )\n' ||
    E'        FROM public.products p\n' ||
    E'        WHERE p.business_id = p_business_id\n' ||
    E'          AND p.location_id IS DISTINCT FROM v_location_id\n' ||
    E'          AND p.id IN (\n' ||
    E'            SELECT si.product_id FROM public.sale_items si\n' ||
    E'            JOIN public.sales s ON s.id = si.sale_id\n' ||
    E'            WHERE s.business_id = p_business_id AND s.location_id = v_location_id\n' ||
    E'              AND si.product_id IS NOT NULL\n' ||
    E'            UNION\n' ||
    E'            SELECT im.product_id FROM public.inventory_movements im\n' ||
    E'            WHERE im.business_id = p_business_id AND im.location_id = v_location_id\n' ||
    E'          )\n' ||
    E'      ) scoped\n' ||
    E'    ), ''[]''::jsonb),\n' ||
    E'    ''categories''';
  v_patched := replace(v_patched, v_old, v_new);

  v_old := E'      SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id)\n      FROM public.customers t\n      WHERE t.business_id = p_business_id\n    ), ''[]''::jsonb),\n\n    -- Operational history';
  v_new := E'      SELECT jsonb_agg(scoped.row_json ORDER BY scoped.row_json->>''id'')\n' ||
    E'      FROM (\n' ||
    E'        SELECT to_jsonb(t) AS row_json\n' ||
    E'        FROM public.customers t\n' ||
    E'        WHERE t.business_id = p_business_id AND t.location_id = v_location_id\n' ||
    E'        UNION ALL\n' ||
    E'        SELECT to_jsonb(c) || pg_catalog.jsonb_build_object(\n' ||
    E'          ''name'', ''Historical customer'', ''phone'', null, ''email'', null,\n' ||
    E'          ''address'', null, ''notes'', null, ''location_id'', null,\n' ||
    E'          ''deleted_at'', pg_catalog.now(), ''is_active'', false,\n' ||
    E'          ''credit_limit'', 0, ''outstanding_balance'', 0\n' ||
    E'        )\n' ||
    E'        FROM public.customers c\n' ||
    E'        WHERE c.business_id = p_business_id\n' ||
    E'          AND c.location_id IS DISTINCT FROM v_location_id\n' ||
    E'          AND c.id IN (\n' ||
    E'            SELECT s.customer_id FROM public.sales s\n' ||
    E'            WHERE s.business_id = p_business_id AND s.location_id = v_location_id\n' ||
    E'              AND s.customer_id IS NOT NULL\n' ||
    E'            UNION\n' ||
    E'            SELECT r.customer_id FROM public.returns r\n' ||
    E'            JOIN public.sales s ON s.id = r.sale_id\n' ||
    E'            WHERE s.business_id = p_business_id AND s.location_id = v_location_id\n' ||
    E'              AND r.customer_id IS NOT NULL\n' ||
    E'          )\n' ||
    E'      ) scoped\n' ||
    E'    ), ''[]''::jsonb),\n\n    -- Operational history';
  v_patched := replace(v_patched, v_old, v_new);

  v_old := E'        WHERE psl_product.business_id = p_business_id\n      )';
  v_new := E'        WHERE psl_product.business_id = p_business_id\n          AND psl_product.location_id = v_location_id\n      )';
  v_patched := replace(v_patched, v_old, v_new);

  v_old := E'      FROM public.customer_ledger_entries t\n      WHERE t.business_id = p_business_id\n    ), ''[]''::jsonb),';
  v_new := E'      FROM public.customer_ledger_entries t\n      WHERE t.business_id = p_business_id\n        AND t.customer_id IN (\n          SELECT c.id FROM public.customers c\n          WHERE c.business_id = p_business_id\n            AND c.location_id = v_location_id\n        )\n    ), ''[]''::jsonb),';
  v_patched := replace(v_patched, v_old, v_new);

  v_old := E'      FROM public.employees t\n      WHERE t.business_id = p_business_id\n        AND t.auth_user_id = p_user_id\n        AND t.is_active = true';
  v_new := E'      FROM public.employees t\n      WHERE t.business_id = p_business_id\n        AND t.auth_user_id = p_user_id\n        AND t.location_id = v_location_id\n        AND t.is_active = true';
  v_patched := replace(v_patched, v_old, v_new);

  if v_patched = v_definition
     or (
       length(v_patched) - length(replace(v_patched, 'AND t.location_id = v_location_id', ''))
     ) / length('AND t.location_id = v_location_id') < 3
     or position('AND psl_product.location_id = v_location_id' in v_patched) = 0
     or position('AND t.customer_id IN' in v_patched) = 0
     or position('Historical product' in v_patched) = 0
     or position('Historical customer' in v_patched) = 0 then
    raise exception 'employee restore location ownership patch did not apply completely';
  end if;
  execute v_patched;
end;
$employee_restore_patch$;

-- Ownership can be filled for a legacy null row after explicit review, but
-- once assigned it cannot be silently transferred by a normal update.
create or replace function public.guard_location_owned_record()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'UPDATE' and old.location_id is not null
     and new.location_id is distinct from old.location_id then
    raise exception using errcode = '42501',
      message = 'Location ownership cannot be changed after assignment';
  end if;

  if new.location_id is not null
     and (tg_op = 'INSERT' or new.location_id is distinct from old.location_id)
     and not exists (
       select 1 from public.locations l
       where l.id = new.location_id
         and l.business_id = new.business_id
         and l.status = 'active'
     ) then
    raise exception using errcode = '22023',
      message = 'Location must be active and belong to the record business';
  end if;
  return new;
end;
$function$;

drop trigger if exists products_location_owner_guard on public.products;
create trigger products_location_owner_guard
before insert or update of location_id, business_id on public.products
for each row execute function public.guard_location_owned_record();

drop trigger if exists customers_location_owner_guard on public.customers;
create trigger customers_location_owner_guard
before insert or update of location_id, business_id on public.customers
for each row execute function public.guard_location_owned_record();

drop policy if exists products_select_member on public.products;
create policy products_select_member on public.products
for select using (
  has_permission(business_id, 'catalog.read')
  and (
    is_business_admin(business_id)
    or (location_id is not null and is_location_member(location_id))
  )
);

drop policy if exists products_manage_catalog on public.products;
create policy products_manage_catalog on public.products
for insert with check (
  has_permission(business_id, 'catalog.manage')
  and location_id is not null
  and (is_business_admin(business_id) or is_location_member(location_id))
);

drop policy if exists products_update_catalog on public.products;
create policy products_update_catalog on public.products
for update using (
  has_permission(business_id, 'catalog.manage')
  and (
    is_business_admin(business_id)
    or (location_id is not null and is_location_member(location_id))
  )
) with check (
  has_permission(business_id, 'catalog.manage')
  and location_id is not null
  and (is_business_admin(business_id) or is_location_member(location_id))
);


drop policy if exists product_stock_levels_select_member on public.product_stock_levels;
create policy product_stock_levels_select_member on public.product_stock_levels
for select using (
  exists (
    select 1 from public.products p
    where p.id = product_stock_levels.product_id
      and has_permission(p.business_id, 'inventory.read')
      and (
        is_business_admin(p.business_id)
        or (
          p.location_id is not null
          and p.location_id = product_stock_levels.location_id
          and is_location_member(p.location_id)
        )
      )
  )
);

drop policy if exists ledger_read on public.customer_ledger_entries;
create policy ledger_read on public.customer_ledger_entries
for select using (
  has_permission(business_id, 'customers.read')
  and exists (
    select 1 from public.customers c
    where c.id = customer_ledger_entries.customer_id
      and c.business_id = customer_ledger_entries.business_id
      and (
        is_business_admin(c.business_id)
        or (c.location_id is not null and is_location_member(c.location_id))
      )
  )
);

drop policy if exists customers_read on public.customers;
create policy customers_read on public.customers
for select using (
  has_permission(business_id, 'customers.read')
  and (
    is_business_admin(business_id)
    or (location_id is not null and is_location_member(location_id))
  )
);


drop policy if exists sales_read on public.sales;
create policy sales_read on public.sales
for select using (
  has_permission(business_id, 'sales.read')
  and (
    is_business_admin(business_id)
    or (location_id is not null and is_location_member(location_id))
  )
);

drop policy if exists sale_items_read on public.sale_items;
create policy sale_items_read on public.sale_items
for select using (
  exists (
    select 1 from public.sales s
    where s.id = sale_items.sale_id
      and has_permission(s.business_id, 'sales.read')
      and (
        is_business_admin(s.business_id)
        or (s.location_id is not null and is_location_member(s.location_id))
      )
  )
);

drop policy if exists returns_read on public.returns;
create policy returns_read on public.returns
for select using (
  has_permission(business_id, 'sales.read')
  and exists (
    select 1 from public.sales s
    where s.id = returns.sale_id
      and (
        is_business_admin(s.business_id)
        or (s.location_id is not null and is_location_member(s.location_id))
      )
  )
);

drop policy if exists return_items_read on public.return_items;
create policy return_items_read on public.return_items
for select using (
  exists (
    select 1
    from public.returns r
    join public.sales s on s.id = r.sale_id
    where r.id = return_items.return_id
      and has_permission(r.business_id, 'sales.read')
      and (
        is_business_admin(s.business_id)
        or (s.location_id is not null and is_location_member(s.location_id))
      )
  )
);

drop policy if exists inventory_movements_select_member on public.inventory_movements;
create policy inventory_movements_select_member on public.inventory_movements
for select using (
  has_permission(business_id, 'inventory.read')
  and (
    is_business_admin(business_id)
    or (
      location_id is not null
      and is_location_member(location_id)
      and exists (
        select 1 from public.products p
        where p.id = inventory_movements.product_id
          and p.business_id = inventory_movements.business_id
          and p.location_id = inventory_movements.location_id
      )
    )
  )
);

drop policy if exists employees_read_access on public.employees;
create policy employees_read_access on public.employees
for select using (
  (
    (
      has_permission(business_id, 'employees.read')
      or has_permission(business_id, 'employees.manage')
    )
    and (
      is_business_admin(business_id)
      or (location_id is not null and is_location_member(location_id))
    )
  )
  or ((select auth.uid()) = auth_user_id)
);

revoke all on function public.guard_location_owned_record() from public, anon, authenticated;


-- Active roster entries require an explicit location. Existing inactive/null
-- legacy rows remain available for controlled recovery, but cannot be created
-- or updated into an active unassigned roster entry.
do $employee_patch$
declare
  v_definition text;
  v_patched text;
  v_old text;
  v_new text;
begin
  v_definition := pg_catalog.pg_get_functiondef(
    'public.fulus_api_mutate_employee(uuid,uuid,uuid,text,text,uuid,text,text,text,text,text,numeric,text,text,date,uuid,boolean,bigint,text)'::regprocedure
  );
  v_patched := v_definition;

  v_old := E'  if target_operation = ''create'' and target_location_id is not null then\n' ||
    E'    perform public.require_location_access(target_business_id, target_location_id);\n' ||
    E'  end if;';
  v_new := E'  if target_operation = ''create'' then\n' ||
    E'    if target_location_id is null then\n' ||
    E'      raise exception using errcode = ''22023'', message = ''Employee location_id is required'';\n' ||
    E'    end if;\n' ||
    E'    perform public.require_location_access(target_business_id, target_location_id);\n' ||
    E'  end if;';
  v_patched := replace(v_patched, v_old, v_new);

  v_old := E'    if target_location_id is not null then\n' ||
    E'      perform public.require_location_access(target_business_id, target_location_id);\n' ||
    E'    elsif employee_row.location_id is not null then\n' ||
    E'      perform public.require_location_access(target_business_id, employee_row.location_id);\n' ||
    E'    end if;';
  v_new := E'    if target_location_id is null then\n' ||
    E'      raise exception using errcode = ''22023'', message = ''Employee location_id is required'';\n' ||
    E'    end if;\n' ||
    E'    if employee_row.location_id is not null then\n' ||
    E'      perform public.require_location_access(target_business_id, employee_row.location_id);\n' ||
    E'    end if;\n' ||
    E'    perform public.require_location_access(target_business_id, target_location_id);';
  v_patched := replace(v_patched, v_old, v_new);

  if v_patched = v_definition
     or position('if employee_row.location_id is not null then' in v_patched) = 0 then
    raise exception 'employee location ownership patch did not apply';
  end if;
  if position('Employee location_id is required' in v_patched) = 0 then
    raise exception 'employee location ownership contract is incomplete';
  end if;
  execute v_patched;
end;
$employee_patch$;


-- Customer repayment has no client-supplied location argument; derive the
-- authoritative customer owner on the server and authorize that location.
do $repayment_patch$
declare
  v_definition text;
  v_patched text;
  v_old text;
  v_new text;
begin
  v_definition := pg_catalog.pg_get_functiondef(
    'public.fulus_api_record_customer_repayment(uuid,uuid,uuid,numeric,text,text,text,uuid)'::regprocedure
  );
  v_patched := v_definition;

  v_old := 'declare idem public.idempotency_keys%rowtype; request_hash text; result jsonb;';
  v_new := 'declare idem public.idempotency_keys%rowtype; request_hash text; result jsonb; customer_location_id uuid;';
  v_patched := replace(v_patched, v_old, v_new);

  v_old := E' perform set_config(''request.jwt.claim.sub'',target_user_id::text,true);\n result:=public.record_customer_repayment';
  v_new := E' perform set_config(''request.jwt.claim.sub'',target_user_id::text,true);\n' ||
    E' select c.location_id into customer_location_id from public.customers c\n' ||
    E' where c.id=target_customer_id and c.business_id=target_business_id;\n' ||
    E' if customer_location_id is null then\n' ||
    E'   raise exception using errcode=''42501'',message=''Customer location ownership is unresolved'';\n' ||
    E' end if;\n' ||
    E' perform public.require_location_access(target_business_id,customer_location_id);\n' ||
    E' result:=public.record_customer_repayment';
  v_patched := replace(v_patched, v_old, v_new);

  if v_patched = v_definition
     or position('customer_location_id uuid' in v_patched) = 0
     or position('require_location_access(target_business_id,customer_location_id)' in v_patched) = 0 then
    raise exception 'customer repayment location authorization patch did not apply';
  end if;
  execute v_patched;
end;
$repayment_patch$;

-- Database-level guards protect mutation paths that bypass the mobile UI.
-- Legacy rows with unresolved ownership are intentionally not valid for new
-- transactional references; existing historical rows are not rewritten.
create or replace function public.guard_location_transaction_references()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_customer_location uuid;
  v_product_location uuid;
  v_sale_location uuid;
begin
  if tg_table_name = 'sales' then
    if new.customer_id is not null
       and (tg_op = 'INSERT' or new.customer_id is distinct from old.customer_id
            or new.location_id is distinct from old.location_id) then
      select c.location_id into v_customer_location
      from public.customers c
      where c.id = new.customer_id and c.business_id = new.business_id;
      if v_customer_location is null
         or v_customer_location is distinct from new.location_id then
        raise exception using errcode = '42501',
          message = 'Customer is not owned by the sale location';
      end if;
    end if;
    return new;
  elsif tg_table_name = 'sale_items' then
    if new.product_id is null then return new; end if;
    select s.location_id into v_sale_location
    from public.sales s where s.id = new.sale_id;
    select p.location_id into v_product_location
    from public.products p where p.id = new.product_id;
    if v_product_location is null
       or v_sale_location is null
       or v_product_location is distinct from v_sale_location then
      raise exception using errcode = '42501',
        message = 'Product is not owned by the sale location';
    end if;
    return new;
  elsif tg_table_name = 'product_stock_levels' then
    select p.location_id into v_product_location
    from public.products p where p.id = new.product_id;
    if v_product_location is null
       or v_product_location is distinct from new.location_id then
      raise exception using errcode = '42501',
        message = 'Stock location does not match product owner location';
    end if;
    return new;
  elsif tg_table_name = 'inventory_movements' then
    select p.location_id into v_product_location
    from public.products p where p.id = new.product_id;
    if v_product_location is null
       or v_product_location is distinct from new.location_id then
      raise exception using errcode = '42501',
        message = 'Movement location does not match product owner location';
    end if;
    return new;
  elsif tg_table_name = 'returns' then
    if new.customer_id is null then return new; end if;
    select s.location_id into v_sale_location
    from public.sales s where s.id = new.sale_id;
    select c.location_id into v_customer_location
    from public.customers c where c.id = new.customer_id;
    if v_customer_location is null
       or v_sale_location is null
       or v_customer_location is distinct from v_sale_location then
      raise exception using errcode = '42501',
        message = 'Customer is not owned by the return sale location';
    end if;
    return new;
  elsif tg_table_name = 'customer_ledger_entries' then
    select c.location_id into v_customer_location
    from public.customers c where c.id = new.customer_id;
    if v_customer_location is null then
      raise exception using errcode = '42501',
        message = 'Customer location ownership is unresolved';
    end if;
    if new.sale_id is not null then
      select s.location_id into v_sale_location
      from public.sales s where s.id = new.sale_id;
      if v_sale_location is distinct from v_customer_location then
        raise exception using errcode = '42501',
          message = 'Customer ledger sale belongs to another location';
      end if;
    end if;
    return new;
  end if;
  return new;
end;
$function$;

drop trigger if exists sales_customer_location_guard on public.sales;
create trigger sales_customer_location_guard
before insert or update of customer_id, location_id on public.sales
for each row execute function public.guard_location_transaction_references();

drop trigger if exists sale_items_product_location_guard on public.sale_items;
create trigger sale_items_product_location_guard
before insert or update of product_id, sale_id on public.sale_items
for each row execute function public.guard_location_transaction_references();

drop trigger if exists product_stock_location_guard on public.product_stock_levels;
create trigger product_stock_location_guard
before insert or update of product_id, location_id on public.product_stock_levels
for each row execute function public.guard_location_transaction_references();

drop trigger if exists inventory_movement_product_location_guard on public.inventory_movements;
create trigger inventory_movement_product_location_guard
before insert or update of product_id, location_id on public.inventory_movements
for each row execute function public.guard_location_transaction_references();

drop trigger if exists returns_customer_location_guard on public.returns;
create trigger returns_customer_location_guard
before insert or update of customer_id, sale_id on public.returns
for each row execute function public.guard_location_transaction_references();

drop trigger if exists customer_ledger_location_guard on public.customer_ledger_entries;
create trigger customer_ledger_location_guard
before insert or update of customer_id, sale_id on public.customer_ledger_entries
for each row execute function public.guard_location_transaction_references();

revoke all on function public.guard_location_transaction_references() from public, anon, authenticated;

-- Existing employees already have location_id; this index supports scoped
-- roster reads without changing employee identity/membership relationships.
create index if not exists employees_business_location_updated_idx
  on public.employees (business_id, location_id, updated_at desc);
