revoke execute on function public.create_location(uuid,text,text,text,text,text) from public;
revoke execute on function public.create_location(uuid,text,text,text,text,text) from anon;
revoke execute on function public.create_location(uuid,text,text,text,text,text) from authenticated;
revoke execute on function public.emit_location_sync_change() from public;
revoke execute on function public.emit_location_sync_change() from anon;
revoke execute on function public.emit_location_sync_change() from authenticated;
