alter table public.products
  add column if not exists tracks_stock boolean not null default true;
