-- Make supplier payables business-wide canonical financial records. Mobile
-- clients write only through the idempotent Fulus API RPC below.

alter table public.suppliers
  add column if not exists outstanding_balance numeric not null default 0
    check (outstanding_balance >= 0);

create table if not exists public.supplier_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  location_id uuid not null references public.locations(id) on delete restrict,
  stock_movement_id uuid references public.inventory_movements(id) on delete restrict,
  cash_drawer_shift_id uuid references public.cash_drawer_shifts(id) on delete restrict,
  entry_type text not null check (entry_type in ('stock_purchase_on_credit', 'payment_made')),
  amount numeric not null check (amount > 0),
  balance_after numeric not null check (balance_after >= 0),
  operation_id text not null,
  payment_method text,
  note text,
  created_by uuid references auth.users(id) on delete set null,
  device_id uuid references public.devices(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (business_id, operation_id)
);

create index if not exists supplier_ledger_entries_business_location_created_idx
  on public.supplier_ledger_entries (business_id, location_id, created_at desc);
create index if not exists supplier_ledger_entries_supplier_created_idx
  on public.supplier_ledger_entries (business_id, supplier_id, created_at desc);
create unique index if not exists supplier_ledger_entries_stock_movement_uidx
  on public.supplier_ledger_entries (business_id, stock_movement_id)
  where entry_type = 'stock_purchase_on_credit' and stock_movement_id is not null;

alter table public.supplier_ledger_entries enable row level security;
revoke all on public.supplier_ledger_entries from anon, authenticated;
grant select on public.supplier_ledger_entries to service_role;

create or replace function public.record_supplier_ledger_entry(
  target_business_id uuid,
  target_supplier_id uuid,
  target_location_id uuid,
  target_entry_type text,
  target_amount numeric,
  target_operation_id text,
  target_payment_method text default null,
  target_note text default null,
  target_stock_movement_id uuid default null,
  target_cash_drawer_shift_id uuid default null,
  target_created_at timestamptz default null,
  target_device_id uuid default null
) returns jsonb
language plpgsql security definer set search_path = ''
as $function$
declare
  actor uuid := auth.uid();
  supplier_row public.suppliers%rowtype;
  shift_row public.cash_drawer_shifts%rowtype;
  movement_row public.inventory_movements%rowtype;
  ledger_row public.supplier_ledger_entries%rowtype;
  new_balance numeric;
  excess_amount numeric := 0;
  event_time timestamptz := coalesce(target_created_at, now());
begin
  if actor is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if not public.has_permission(target_business_id, 'finance.manage') then
    raise exception using errcode = '42501', message = 'Finance permission required';
  end if;
  perform public.require_location_access(target_business_id, target_location_id);
  if target_operation_id is null or length(trim(target_operation_id)) = 0 then
    raise exception using errcode = '22023', message = 'operation_id is required';
  end if;
  if target_amount is null or target_amount <= 0 then
    raise exception using errcode = '22013', message = 'Supplier ledger amount must be positive';
  end if;
  if target_entry_type not in ('stock_purchase_on_credit', 'payment_made') then
    raise exception using errcode = '22023', message = 'Unsupported supplier ledger entry type';
  end if;
  if target_device_id is not null and not exists (
    select 1 from public.devices d
    where d.id = target_device_id and d.business_id = target_business_id
      and d.status = 'active'
  ) then
    raise exception using errcode = '42501', message = 'Device is not active for this business';
  end if;

  select * into supplier_row
  from public.suppliers s
  where s.id = target_supplier_id and s.business_id = target_business_id
    and s.deleted_at is null
  for update;
  if not found then
    raise exception using errcode = '22023', message = 'Supplier does not belong to this business';
  end if;

  if target_entry_type = 'stock_purchase_on_credit' then
    if target_stock_movement_id is null then
      raise exception using errcode = '22023', message = 'On-account stock purchase requires its stock movement';
    end if;
    select * into movement_row
    from public.inventory_movements m
    where m.id = target_stock_movement_id
      and m.business_id = target_business_id
      and m.location_id = target_location_id
    for share;
    if not found then
      raise exception using errcode = '22023', message = 'Stock movement is not available at this location';
    end if;
    if movement_row.quantity_delta <= 0 then
      raise exception using errcode = '22023', message = 'On-account supplier credit must reference a stock-in movement';
    end if;
  elsif target_cash_drawer_shift_id is not null then
    if lower(trim(coalesce(target_payment_method, ''))) <> 'cash' then
      raise exception using errcode = '22023', message = 'Only cash payments can be assigned to a cash drawer';
    end if;
    select * into shift_row
    from public.cash_drawer_shifts c
    where c.id = target_cash_drawer_shift_id
      and c.business_id = target_business_id
      and c.location_id = target_location_id
      and c.closed_at is null
    for update;
    if not found then
      raise exception using errcode = '22023', message = 'Cash drawer is not open at this location';
    end if;
  end if;

  select * into ledger_row
  from public.supplier_ledger_entries e
  where e.business_id = target_business_id and e.operation_id = target_operation_id;
  if found then
    return jsonb_build_object(
      'status', 'already_applied', 'ledger_id', ledger_row.id,
      'new_balance', ledger_row.balance_after, 'excess_amount', 0,
      'server_authoritative', true
    );
  end if;

  if target_entry_type = 'stock_purchase_on_credit' then
    new_balance := round(supplier_row.outstanding_balance + target_amount, 2);
  else
    new_balance := round(greatest(supplier_row.outstanding_balance - target_amount, 0), 2);
    excess_amount := round(greatest(target_amount - supplier_row.outstanding_balance, 0), 2);
  end if;

  update public.suppliers
  set outstanding_balance = new_balance, updated_at = now()
  where id = target_supplier_id and business_id = target_business_id;

  insert into public.supplier_ledger_entries (
    business_id, supplier_id, location_id, stock_movement_id,
    cash_drawer_shift_id, entry_type, amount, balance_after, operation_id,
    payment_method, note, created_by, device_id, created_at
  ) values (
    target_business_id, target_supplier_id, target_location_id,
    target_stock_movement_id, target_cash_drawer_shift_id, target_entry_type,
    target_amount, new_balance, target_operation_id,
    nullif(trim(target_payment_method), ''), nullif(trim(target_note), ''),
    actor, target_device_id, event_time
  ) returning * into ledger_row;

  perform public._fulus_append_change(
    target_business_id, 'supplier_ledger', ledger_row.id, 'upsert',
    jsonb_build_object(
      'id', ledger_row.id,
      'supplier_id', ledger_row.supplier_id,
      'location_id', ledger_row.location_id,
      'stock_movement_id', ledger_row.stock_movement_id,
      'cash_drawer_shift_id', ledger_row.cash_drawer_shift_id,
      'entry_type', ledger_row.entry_type,
      'amount', ledger_row.amount,
      'balance_after', ledger_row.balance_after,
      'operation_id', ledger_row.operation_id,
      'payment_method', ledger_row.payment_method,
      'note', ledger_row.note,
      'created_by', ledger_row.created_by,
      'device_id', ledger_row.device_id,
      'created_at', ledger_row.created_at
    )
  );

  return jsonb_build_object(
    'status', 'applied', 'ledger_id', ledger_row.id,
    'new_balance', new_balance, 'excess_amount', excess_amount,
    'server_authoritative', true
  );
end;
$function$;

revoke all on function public.record_supplier_ledger_entry(uuid,uuid,uuid,text,numeric,text,text,text,uuid,uuid,timestamptz,uuid)
  from public, anon, authenticated;
grant execute on function public.record_supplier_ledger_entry(uuid,uuid,uuid,text,numeric,text,text,text,uuid,uuid,timestamptz,uuid)
  to service_role;

create or replace function public.fulus_api_record_supplier_ledger_entry(
  target_user_id uuid,
  target_business_id uuid,
  target_supplier_id uuid,
  target_location_id uuid,
  target_entry_type text,
  target_amount numeric,
  target_operation_id text,
  target_payment_method text,
  target_note text,
  target_stock_movement_id uuid,
  target_cash_drawer_shift_id uuid,
  target_created_at timestamptz,
  target_device_id uuid
) returns jsonb
language plpgsql security definer set search_path = ''
as $function$
declare
  idem public.idempotency_keys%rowtype;
  request_hash text;
  result jsonb;
begin
  if not exists (
    select 1 from public.devices d
    where d.id = target_device_id and d.business_id = target_business_id
      and d.registered_by = target_user_id and d.status = 'active'
  ) then
    raise exception using errcode = '42501', message = 'Device is not registered or active';
  end if;
  request_hash := md5(jsonb_build_object(
    'supplier_id', target_supplier_id, 'location_id', target_location_id,
    'entry_type', target_entry_type, 'amount', target_amount,
    'payment_method', target_payment_method, 'note', target_note,
    'stock_movement_id', target_stock_movement_id,
    'cash_drawer_shift_id', target_cash_drawer_shift_id,
    'created_at', target_created_at, 'device_id', target_device_id
  )::text);
  insert into public.idempotency_keys(
    business_id, device_id, user_id, key, operation_type, request_hash
  ) values (
    target_business_id, target_device_id, target_user_id, target_operation_id,
    'supplier_ledger.create', request_hash
  ) on conflict (business_id, key) do nothing;
  select * into idem from public.idempotency_keys
  where business_id = target_business_id and key = target_operation_id
  for update;
  if idem.device_id is distinct from target_device_id
     or idem.user_id is distinct from target_user_id then
    raise exception using errcode = 'P0009', message = 'Operation id was already used from a different device or account';
  end if;
  if idem.operation_type <> 'supplier_ledger.create'
     or idem.request_hash <> request_hash then
    raise exception using errcode = 'P0009', message = 'Operation id was already used with a different request';
  end if;
  if idem.completed_at is not null and idem.response_body is not null then
    return idem.response_body;
  end if;
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);
  result := public.record_supplier_ledger_entry(
    target_business_id, target_supplier_id, target_location_id,
    target_entry_type, target_amount, target_operation_id,
    target_payment_method, target_note, target_stock_movement_id,
    target_cash_drawer_shift_id, target_created_at, target_device_id
  );
  update public.idempotency_keys
  set response_status = 200, response_body = result, completed_at = now()
  where id = idem.id;
  return result;
end;
$function$;

revoke all on function public.fulus_api_record_supplier_ledger_entry(uuid,uuid,uuid,uuid,text,numeric,text,text,text,uuid,uuid,timestamptz,uuid)
  from public, anon, authenticated;
grant execute on function public.fulus_api_record_supplier_ledger_entry(uuid,uuid,uuid,uuid,text,numeric,text,text,text,uuid,uuid,timestamptz,uuid)
  to service_role;

-- Add supplier entries to both full-owner and employee-location snapshots.
do $restore$
declare
  v_def text;
  v_old text;
  v_new text;
  v_owner_function regprocedure;
begin
  -- Production may expose a routing wrapper while the full owner snapshot
  -- implementation lives in the *_full function. Fresh migration-chain
  -- databases still define the original function directly, so support both.
  v_owner_function := coalesce(
    to_regprocedure('public.build_fulus_restore_snapshot_full(uuid,uuid)'),
    to_regprocedure('public.build_fulus_restore_snapshot(uuid,uuid)')
  );
  if v_owner_function is null then
    raise exception 'Owner restore snapshot function is missing';
  end if;
  v_def := pg_get_functiondef(v_owner_function);
  v_old := '''cash_drawer_shifts'', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.cash_drawer_shifts t where t.business_id = p_business_id), ''[]''::jsonb),';
  v_new := v_old || E'\n    ''supplier_ledger_entries'', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.supplier_ledger_entries t where t.business_id = p_business_id), ''[]''::jsonb),';
  if position(v_old in v_def) = 0 then raise exception 'Owner restore snapshot cash drawer section changed; patch supplier ledger export explicitly'; end if;
  v_def := replace(v_def, v_old, v_new);
  v_old := '''server_schema_optional_sections_omitted'', jsonb_build_array(''supplier_ledger_entries'',''tax_remittances''),';
  v_new := '''server_schema_optional_sections_omitted'', jsonb_build_array(''tax_remittances''),';
  if position(v_old in v_def) = 0 then raise exception 'Owner restore snapshot optional-section note changed'; end if;
  v_def := replace(v_def, v_old, v_new);
  execute v_def;

  v_def := pg_get_functiondef('public.build_fulus_employee_restore_snapshot(uuid,uuid)'::regprocedure);
  v_old := E'''cash_drawer_shifts'', coalesce((\n      SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id)\n      FROM public.cash_drawer_shifts t\n      WHERE t.business_id = p_business_id\n        AND t.location_id = v_location_id\n    ), ''[]''::jsonb),';
  v_new := v_old || E'\n    ''supplier_ledger_entries'', coalesce((\n      SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id)\n      FROM public.supplier_ledger_entries t\n      WHERE t.business_id = p_business_id\n        AND t.location_id = v_location_id\n    ), ''[]''::jsonb),';
  if position(v_old in v_def) = 0 then raise exception 'Employee restore snapshot cash drawer section changed; patch supplier ledger export explicitly'; end if;
  v_def := replace(v_def, v_old, v_new);
  execute v_def;
end;
$restore$;

-- Supplier restore rows add balance_after, which must use the same strict
-- decimal-string JSON contract as other money fields. Preserve the existing
-- snapshot traversal behavior and extend only its money-key allowlist.
create or replace function public._fulus_money_wire_row_jsonb(p_value jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  if p_value is null
     or pg_catalog.jsonb_typeof(p_value) <> 'object' then
    return p_value;
  end if;

  select coalesce(
    pg_catalog.jsonb_object_agg(
      section.key,
      case
        when section.key = any (array[
          'amount','amount_remitted','balance_after','new_balance',
          'credit_limit','outstanding_balance','opening_cash','closing_cash',
          'cash_difference','subtotal','whole_cart_discount','discount','tax',
          'total','amount_paid','cash_tendered','cash_change','tendered_amount',
          'unit_price','cost_price_at_sale','line_total','line_discount',
          'cost_price','selling_price','refund_amount','salary'
        ]::text[])
        and pg_catalog.jsonb_typeof(section.value) = 'number'
        then pg_catalog.to_jsonb(
          pg_catalog.to_char(
            (section.value #>> '{}')::numeric,
            'FM999999999999999999999999999999990.00'
          )
        )
        else section.value
      end
    ), '{}'::jsonb
  ) into v_result
  from pg_catalog.jsonb_each(p_value) as section(key, value);

  return v_result;
end;
$function$;

revoke all on function public._fulus_money_wire_row_jsonb(jsonb) from public;

create or replace function public._fulus_money_wire_jsonb(p_value jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_result jsonb;
  v_money_keys constant text[] := array[
    'amount','amount_remitted','balance_after','new_balance','credit_limit',
    'outstanding_balance','opening_cash','closing_cash','cash_difference',
    'subtotal','whole_cart_discount','discount','tax','total','amount_paid',
    'cash_tendered','cash_change','tendered_amount','unit_price',
    'cost_price_at_sale','line_total','line_discount','cost_price',
    'selling_price','refund_amount','salary'
  ];
  v_money_sections constant text[] := array[
    'products','customers','suppliers','sales','expenses','income_records',
    'returns','cash_ledger','cash_drawer_shifts','sale_items','sale_payments',
    'return_items','customer_ledger_entries','supplier_ledger_entries',
    'tax_remittances','employees'
  ];
begin
  if p_value is null then return null; end if;
  if pg_catalog.jsonb_typeof(p_value) <> 'object' then return p_value; end if;

  if p_value ?| v_money_keys then
    v_result := public._fulus_money_wire_row_jsonb(p_value);
  else
    v_result := p_value;
  end if;

  select coalesce(
    pg_catalog.jsonb_object_agg(
      section.key,
      case
        when section.key = any(v_money_sections)
          and pg_catalog.jsonb_typeof(section.value) = 'array'
        then (
          select coalesce(
            pg_catalog.jsonb_agg(
              case
                when pg_catalog.jsonb_typeof(element.value) = 'object'
                  and element.value ?| v_money_keys
                then public._fulus_money_wire_row_jsonb(element.value)
                else element.value
              end order by element.ordinality
            ), '[]'::jsonb
          )
          from pg_catalog.jsonb_array_elements(section.value)
            with ordinality as element(value, ordinality)
        )
        else section.value
      end
    ), '{}'::jsonb
  ) into v_result
  from pg_catalog.jsonb_each(v_result) as section(key, value);

  return v_result;
end;
$function$;
