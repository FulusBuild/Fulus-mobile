-- Harden product-image storage to the same catalog authorization boundary as product mutations.
-- Direct Storage writes are client-facing, so membership alone is not sufficient.

drop policy if exists "product images update for business members" on storage.objects;
drop policy if exists "product images delete for business members" on storage.objects;

drop policy if exists "product images upload for business members" on storage.objects;
create policy "product images upload for catalog managers"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'product-images'
  and public.has_permission(
    split_part(name, '/', 1)::uuid,
    'catalog.manage'
  )
);

