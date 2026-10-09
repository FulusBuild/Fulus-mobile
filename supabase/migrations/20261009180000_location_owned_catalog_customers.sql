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

-- Only auto-assign when every observed location reference agrees. References
-- include stock, movements and historical sales. A product used in multiple
-- locations remains unassigned for explicit review.
with evidence as (
  select p.id as product_id, p.business_id, ps.location_id
  from public.products p
  join public.product_stock_levels ps on ps.product_id = p.id
  union
  select p.id, p.business_id, im.location_id
  from public.products p
  join public.inventory_movements im on im.product_id = p.id
  union
  select p.id, p.business_id, s.location_id
  from public.products p
  join public.sale_items si on si.product_id = p.id
  join public.sales s on s.id = si.sale_id
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
  union
  select p.id, p.business_id, im.location_id
  from public.products p
  join public.inventory_movements im on im.product_id = p.id
  union
  select p.id, p.business_id, s.location_id
  from public.products p
  join public.sale_items si on si.product_id = p.id
  join public.sales s on s.id = si.sale_id
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
  union
  select c.id, c.business_id, s.location_id
  from public.customers c
  join public.returns r on r.customer_id = c.id and r.business_id = c.business_id
  join public.sales s on s.id = r.sale_id and s.business_id = c.business_id
  union
  select c.id, c.business_id, s.location_id
  from public.customers c
  join public.customer_ledger_entries le on le.customer_id = c.id and le.business_id = c.business_id
  join public.sales s on s.id = le.sale_id and s.business_id = c.business_id
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
  union
  select c.id, c.business_id, s.location_id
  from public.customers c
  join public.returns r on r.customer_id = c.id and r.business_id = c.business_id
  join public.sales s on s.id = r.sale_id and s.business_id = c.business_id
  union
  select c.id, c.business_id, s.location_id
  from public.customers c
  join public.customer_ledger_entries le on le.customer_id = c.id and le.business_id = c.business_id
  join public.sales s on s.id = le.sale_id and s.business_id = c.business_id
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

drop policy if exists customers_read on public.customers;
create policy customers_read on public.customers
for select using (
  has_permission(business_id, 'customers.read')
  and (
    is_business_admin(business_id)
    or (location_id is not null and is_location_member(location_id))
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

-- Existing employees already have location_id; this index supports scoped
-- roster reads without changing employee identity/membership relationships.
create index if not exists employees_business_location_updated_idx
  on public.employees (business_id, location_id, updated_at desc);
