-- Staff access is keyed by invitation email during the simplified
-- onboarding flow. Keep the owner-side lookup inexpensive as the roster grows.
create index if not exists staff_invites_business_email_idx
  on public.staff_invites (business_id, invited_email);