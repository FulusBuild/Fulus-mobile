create or replace function public.is_business_admin(target_business_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select exists (
    select 1
    from public.business_memberships bm
    join public.roles r on r.id = bm.role_id
    where bm.business_id = target_business_id
      and bm.user_id = (select auth.uid())
      and bm.status = 'active'
      and r.name in ('owner', 'admin')
  );
$function$;

create or replace function public.is_business_member(target_business_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select exists (
    select 1
    from public.business_memberships bm
    where bm.business_id = target_business_id
      and bm.user_id = (select auth.uid())
      and bm.status = 'active'
  );
$function$;

drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles
for insert to public
with check ((id = (select auth.uid())));

drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles
for select to public
using ((id = (select auth.uid())));

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
for update to public
using ((id = (select auth.uid())))
with check ((id = (select auth.uid())));

drop policy if exists business_memberships_select_member on public.business_memberships;
create policy business_memberships_select_member on public.business_memberships
for select to public
using ((user_id = (select auth.uid())) or is_business_member(business_id));

drop policy if exists location_memberships_select_member on public.location_memberships;
create policy location_memberships_select_member on public.location_memberships
for select to public
using ((user_id = (select auth.uid())) or is_business_member(business_id));

drop policy if exists permissions_select_authenticated on public.permissions;
create policy permissions_select_authenticated on public.permissions
for select to public
using ((select auth.uid()) is not null);
