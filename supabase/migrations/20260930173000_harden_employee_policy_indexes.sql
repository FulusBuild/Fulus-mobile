-- Close the concrete production performance findings introduced by the
-- employee roster surface: avoid per-row auth.uid() evaluation in the
-- employee SELECT policy and add covering indexes for employee/invite and
-- permission-grant foreign keys.

drop policy if exists employees_read_access on public.employees;

create policy employees_read_access
  on public.employees
  for select
  to authenticated
  using (
    public.has_permission(business_id, 'employees.read')
    or public.has_permission(business_id, 'employees.manage')
    or (select auth.uid()) = auth_user_id
  );

create index if not exists employees_auth_user_id_idx
  on public.employees (auth_user_id);

create index if not exists employees_location_id_idx
  on public.employees (location_id);

create index if not exists employees_membership_id_idx
  on public.employees (membership_id);

create index if not exists staff_invites_location_id_idx
  on public.staff_invites (location_id);

create index if not exists business_member_permissions_user_id_idx
  on public.business_member_permissions (user_id);

create index if not exists business_member_permissions_permission_id_idx
  on public.business_member_permissions (permission_id);

create index if not exists business_member_permissions_granted_by_idx
  on public.business_member_permissions (granted_by);
