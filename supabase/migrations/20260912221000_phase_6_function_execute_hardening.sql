-- Phase 6 execute hardening: staff RPCs are callable by authenticated
-- sessions only; the owner helper is internal and not exposed to API callers.
revoke all on function public.create_staff_invite(uuid,uuid,text,integer) from anon;
revoke all on function public.claim_staff_invite(text) from anon;
revoke all on function public.set_member_status(uuid,uuid,text) from anon;
revoke all on function public.change_member_role(uuid,uuid,uuid) from anon;
revoke all on function public.set_role_permission(uuid,uuid,uuid,boolean) from anon;
revoke all on function public.is_business_owner(uuid) from public;