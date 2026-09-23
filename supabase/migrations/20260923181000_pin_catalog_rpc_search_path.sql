-- cloud_catalog_mutate is a SECURITY DEFINER backend boundary and all
-- referenced application objects are explicitly schema-qualified.
alter function public.cloud_catalog_mutate(
  uuid,uuid,uuid,text,text,text,uuid,jsonb,bigint,text
) set search_path = '';
