-- Pin the search_path on every remaining SECURITY DEFINER function that is
-- callable only by service_role. These functions are backend boundaries/internal
-- helpers, and all application relations they touch are schema-qualified.

alter function public._fulus_append_change(uuid,text,uuid,text,jsonb) set search_path = '';
alter function public._fulus_catalog_change(uuid,text,uuid,text,jsonb) set search_path = '';
alter function public.build_fulus_restore_snapshot(uuid,uuid) set search_path = '';
alter function public.can_manage_role_permission(uuid,uuid,uuid) set search_path = '';
alter function public.change_member_role(uuid,uuid,uuid,uuid) set search_path = '';
alter function public.claim_staff_invite(text,uuid) set search_path = '';
alter function public.create_staff_invite(uuid,uuid,text,integer,uuid) set search_path = '';
alter function public.fulus_catalog_sync_change_trigger() set search_path = '';
alter function public.handle_new_user() set search_path = '';
alter function public.has_permission(uuid,text) set search_path = '';
alter function public.is_business_admin(uuid) set search_path = '';
alter function public.is_business_member(uuid) set search_path = '';
alter function public.is_business_owner(uuid) set search_path = '';
alter function public.is_location_member(uuid) set search_path = '';
alter function public.prune_sync_changes() set search_path = '';
alter function public.register_device(uuid,uuid,text,text,text,text) set search_path = '';
alter function public.revoke_device(uuid,uuid,uuid) set search_path = '';
alter function public.set_inventory_quantity(uuid,uuid,uuid,integer,text,text,uuid) set search_path = '';
alter function public.set_member_status(uuid,uuid,text,uuid) set search_path = '';
alter function public.set_role_permission(uuid,uuid,uuid,boolean,uuid) set search_path = '';
