revoke execute on function public.create_staff_invite(uuid,uuid,text,integer,uuid) from public,anon,authenticated;
revoke execute on function public.claim_staff_invite(text,uuid) from public,anon,authenticated;
revoke execute on function public.set_member_status(uuid,uuid,text,uuid) from public,anon,authenticated;
revoke execute on function public.change_member_role(uuid,uuid,uuid,uuid) from public,anon,authenticated;
revoke execute on function public.set_role_permission(uuid,uuid,uuid,boolean,uuid) from public,anon,authenticated;