-- Canonical supplier payable ledger: operation idempotency, drawer attribution,
-- balance projection, sync feed, and full restore visibility.
begin;

create temporary table _supplier_ledger_ids (
  user_id uuid not null,
  business_id uuid not null,
  location_id uuid not null,
  role_id uuid not null,
  device_id uuid not null,
  supplier_id uuid not null,
  product_id uuid not null,
  movement_id uuid not null,
  shift_id uuid not null
) on commit drop;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at
)
values (
  gen_random_uuid(), '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'supplier-ledger@example.test', 'x', now()
);

insert into public.businesses (name) values ('Supplier Ledger Contract Business');
insert into public.roles (business_id, name, is_system)
select id, 'owner', true from public.businesses
where name = 'Supplier Ledger Contract Business';
insert into public.locations (business_id, name, status)
select id, 'Supplier Ledger Location', 'active' from public.businesses
where name = 'Supplier Ledger Contract Business';
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id from public.roles r
join public.permissions p on p.code = 'finance.manage'
where r.name = 'owner'
  and r.business_id = (select id from public.businesses where name = 'Supplier Ledger Contract Business');
insert into public.business_memberships (business_id, user_id, role_id, status, joined_at)
select b.id, u.id, r.id, 'active', now()
from public.businesses b
join public.roles r on r.business_id = b.id and r.name = 'owner'
cross join auth.users u
where b.name = 'Supplier Ledger Contract Business'
  and u.email = 'supplier-ledger@example.test';
insert into public.location_memberships (business_id, location_id, user_id, status)
select b.id, l.id, u.id, 'active'
from public.businesses b
join public.locations l on l.business_id = b.id
cross join auth.users u
where b.name = 'Supplier Ledger Contract Business'
  and l.name = 'Supplier Ledger Location'
  and u.email = 'supplier-ledger@example.test';
insert into public.devices (
  business_id, registered_by, device_client_id, device_name,
  platform, app_version, status, last_seen_at
)
select b.id, u.id, 'supplier-ledger-device', 'Supplier Ledger Device',
       'test', 'test', 'active', now()
from public.businesses b cross join auth.users u
where b.name = 'Supplier Ledger Contract Business'
  and u.email = 'supplier-ledger@example.test';
insert into public.suppliers (business_id, name)
select id, 'Contract Supplier' from public.businesses
where name = 'Supplier Ledger Contract Business';
insert into public.products (
  business_id, location_id, name, sku, supplier_id, cost_price, selling_price
)
select b.id, l.id, 'Contract Item', 'SUPPLIER-LEDGER-ITEM', s.id, 10, 20
from public.businesses b
join public.suppliers s on s.business_id = b.id
join public.locations l on l.business_id = b.id
where b.name = 'Supplier Ledger Contract Business'
  and s.name = 'Contract Supplier'
  and l.name = 'Supplier Ledger Location';
insert into public.inventory_movements (
  business_id, product_id, location_id, quantity_delta, reason, operation_id, user_id
)
select b.id, p.id, l.id, 5, 'supplier ledger contract fixture',
       'supplier-ledger-stock-in', u.id
from public.businesses b
join public.products p on p.business_id = b.id
join public.locations l on l.business_id = b.id
cross join auth.users u
where b.name = 'Supplier Ledger Contract Business'
  and p.sku = 'SUPPLIER-LEDGER-ITEM'
  and l.name = 'Supplier Ledger Location'
  and u.email = 'supplier-ledger@example.test';
insert into public.cash_drawer_shifts (
  business_id, cashier_user_id, location_id, opened_at, opening_cash, open_operation_id
)
select b.id, u.id, l.id, now(), 100, 'supplier-ledger-shift-open'
from public.businesses b
join public.locations l on l.business_id = b.id
cross join auth.users u
where b.name = 'Supplier Ledger Contract Business'
  and l.name = 'Supplier Ledger Location'
  and u.email = 'supplier-ledger@example.test';

insert into _supplier_ledger_ids
select u.id, b.id, l.id, r.id, d.id, s.id, p.id, m.id, c.id
from auth.users u
join public.businesses b on b.name = 'Supplier Ledger Contract Business'
join public.locations l on l.business_id = b.id and l.name = 'Supplier Ledger Location'
join public.roles r on r.business_id = b.id and r.name = 'owner'
join public.devices d on d.business_id = b.id and d.device_client_id = 'supplier-ledger-device'
join public.suppliers s on s.business_id = b.id and s.name = 'Contract Supplier'
join public.products p on p.business_id = b.id and p.sku = 'SUPPLIER-LEDGER-ITEM'
join public.inventory_movements m on m.business_id = b.id and m.operation_id = 'supplier-ledger-stock-in'
join public.cash_drawer_shifts c on c.business_id = b.id and c.open_operation_id = 'supplier-ledger-shift-open'
where u.email = 'supplier-ledger@example.test';

do $$
declare
  ids _supplier_ledger_ids%rowtype;
  purchase_result jsonb;
  replay_result jsonb;
  payment_result jsonb;
  excess_result jsonb;
  snapshot jsonb;
  ledger_count integer;
  sync_count integer;
  balance numeric;
begin
  select * into strict ids from _supplier_ledger_ids;

  purchase_result := public.fulus_api_record_supplier_ledger_entry(
    ids.user_id, ids.business_id, ids.supplier_id, ids.location_id,
    'stock_purchase_on_credit', 100.25, 'supplier-ledger-credit-1',
    null, 'stock on account', ids.movement_id, null, now(), ids.device_id
  );
  replay_result := public.fulus_api_record_supplier_ledger_entry(
    ids.user_id, ids.business_id, ids.supplier_id, ids.location_id,
    'stock_purchase_on_credit', 100.25, 'supplier-ledger-credit-1',
    null, 'stock on account', ids.movement_id, null, now(), ids.device_id
  );
  if purchase_result->>'ledger_id' is distinct from replay_result->>'ledger_id'
     or replay_result->>'status' <> 'applied' then
    raise exception 'Supplier purchase replay did not return its original canonical entry';
  end if;

  payment_result := public.fulus_api_record_supplier_ledger_entry(
    ids.user_id, ids.business_id, ids.supplier_id, ids.location_id,
    'payment_made', 40, 'supplier-ledger-payment-1',
    'cash', 'cash payment', null, ids.shift_id, now(), ids.device_id
  );
  if (payment_result->>'new_balance')::numeric <> 60.25 then
    raise exception 'Supplier balance after cash payment should be 60.25, got %', payment_result->>'new_balance';
  end if;
  if not exists (
    select 1 from public.supplier_ledger_entries e
    where e.id = (payment_result->>'ledger_id')::uuid
      and e.cash_drawer_shift_id = ids.shift_id
      and e.location_id = ids.location_id
  ) then
    raise exception 'Cash supplier payment lost its drawer or location attribution';
  end if;

  excess_result := public.fulus_api_record_supplier_ledger_entry(
    ids.user_id, ids.business_id, ids.supplier_id, ids.location_id,
    'payment_made', 70, 'supplier-ledger-payment-excess',
    'bank_transfer', 'overpayment', null, null, now(), ids.device_id
  );
  if (excess_result->>'new_balance')::numeric <> 0
     or (excess_result->>'excess_amount')::numeric <> 9.75 then
    raise exception 'Supplier overpayment should clamp balance to zero and report 9.75 excess';
  end if;

  select outstanding_balance into balance from public.suppliers where id = ids.supplier_id;
  if balance <> 0 then raise exception 'Supplier balance projection is %, expected zero', balance; end if;
  select count(*) into ledger_count from public.supplier_ledger_entries where supplier_id = ids.supplier_id;
  if ledger_count <> 3 then raise exception 'Expected three unique ledger rows, found %', ledger_count; end if;
  select count(*) into sync_count from public.sync_changes
  where business_id = ids.business_id and entity_type = 'supplier_ledger'
    and operation = 'upsert';
  if sync_count <> 3 then raise exception 'Expected three supplier ledger sync events, found %', sync_count; end if;

  snapshot := public.build_fulus_restore_snapshot(ids.business_id, ids.user_id);
  if not (snapshot->'supplier_ledger_entries' @> jsonb_build_array(
    jsonb_build_object('operation_id', 'supplier-ledger-payment-1')
  )) then
    raise exception 'Full restore snapshot omitted canonical supplier ledger history';
  end if;
end;
$$;

select 'PASS: supplier ledger idempotency, balance, drawer attribution, feed, and restore contracts' as result;
rollback;
