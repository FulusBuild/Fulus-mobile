-- Cover the remaining production foreign keys reported by the performance advisor.
create index if not exists staff_invites_claimed_by_idx
  on public.staff_invites(claimed_by);
create index if not exists staff_invites_created_by_idx
  on public.staff_invites(created_by);
create index if not exists staff_invites_role_idx
  on public.staff_invites(business_id, role_id);
