-- Fulus Cloud Sync — catalog change feed completeness
-- Every direct catalog mutation must emit a canonical change-feed event.
-- The API writes catalog rows directly through the service-role boundary,
-- so application code cannot be relied on to remember to append sync_changes.

create or replace function public.fulus_catalog_sync_change_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  entity_type text;
  row_data jsonb;
begin
  entity_type := case tg_table_name
    when 'products' then 'product'
    when 'categories' then 'category'
    when 'suppliers' then 'supplier'
    when 'expense_categories' then 'expense_category'
    else null
  end;

  if entity_type is null then
    raise exception 'Unsupported catalog sync table: %', tg_table_name;
  end if;

  if tg_op = 'DELETE' then
    perform public._fulus_catalog_change(
      old.business_id,
      entity_type,
      old.id,
      'delete',
      to_jsonb(old)
    );
    return old;
  end if;

  row_data := to_jsonb(new);
  perform public._fulus_catalog_change(
    new.business_id,
    entity_type,
    new.id,
    'upsert',
    row_data
  );
  return new;
end;
$$;

revoke execute on function public.fulus_catalog_sync_change_trigger() from public, anon, authenticated;

drop trigger if exists products_sync_change_trigger on public.products;
create trigger products_sync_change_trigger
after insert or update or delete on public.products
for each row execute function public.fulus_catalog_sync_change_trigger();

drop trigger if exists categories_sync_change_trigger on public.categories;
create trigger categories_sync_change_trigger
after insert or update or delete on public.categories
for each row execute function public.fulus_catalog_sync_change_trigger();

drop trigger if exists suppliers_sync_change_trigger on public.suppliers;
create trigger suppliers_sync_change_trigger
after insert or update or delete on public.suppliers
for each row execute function public.fulus_catalog_sync_change_trigger();

drop trigger if exists expense_categories_sync_change_trigger on public.expense_categories;
create trigger expense_categories_sync_change_trigger
after insert or update or delete on public.expense_categories
for each row execute function public.fulus_catalog_sync_change_trigger();
