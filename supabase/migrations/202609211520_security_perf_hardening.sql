-- Phase 5 hardening: keep the new expense-category RLS policy set
-- explicit per operation and close two legacy public SECURITY DEFINER RPC gaps.

drop policy if exists expense_categories_manage on public.expense_categories;
drop policy if exists expense_categories_member_select on public.expense_categories;

create policy expense_categories_member_select on public.expense_categories
  for select using (
    exists (
      select 1 from public.business_memberships bm
      where bm.business_id = expense_categories.business_id
        and bm.user_id = (select auth.uid())
        and bm.status = 'active'
    )
  );

create policy expense_categories_insert on public.expense_categories
  for insert with check (
    public.has_permission(business_id, 'finance.manage')
  );

create policy expense_categories_update on public.expense_categories
  for update using (
    public.has_permission(business_id, 'finance.manage')
  ) with check (
    public.has_permission(business_id, 'finance.manage')
  );

create policy expense_categories_delete on public.expense_categories
  for delete using (
    public.has_permission(business_id, 'finance.manage')
  );

revoke execute on function public.create_location(uuid,text,text,text,text,text)
  from anon, authenticated;

revoke execute on function public.emit_location_sync_change()
  from anon, authenticated;
