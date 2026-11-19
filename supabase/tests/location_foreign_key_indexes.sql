-- Contract tests for indexes backing location foreign keys flagged by the live advisor.
do $$
declare
  missing text[];
begin
  select array_agg(expected.index_name order by expected.index_name)
    into missing
  from (values
    ('customers_location_id_idx'),
    ('products_location_id_idx'),
    ('location_ownership_review_reviewed_by_idx')
  ) as expected(index_name)
  where not exists (
    select 1
    from pg_indexes i
    where i.schemaname = 'public'
      and i.indexname = expected.index_name
  );

  if missing is not null then
    raise exception 'Missing location foreign-key indexes: %', array_to_string(missing, ', ');
  end if;
end;
$$;

select 'PASS: location foreign-key indexes exist' as result;
