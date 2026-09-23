-- Harden remaining SECURITY DEFINER API overloads whose bodies use fully
-- qualified application objects but previously retained search_path=public.
-- This removes search-path shadowing from the callable production wrappers.
alter function public.fulus_api_revoke_own_device(uuid, uuid, uuid)
  set search_path = '';

alter function public.fulus_api_update_customer(
  uuid, uuid, uuid, text, uuid, text, text, text, text, text, numeric, boolean, bigint, text
) set search_path = '';

alter function public.fulus_api_update_customer(
  uuid, uuid, uuid, text, uuid, text, text, text, text, text, numeric, boolean, text
) set search_path = '';

alter function public.fulus_api_update_expense(
  uuid, uuid, uuid, text, uuid, uuid, numeric, text, text, timestamptz, text, bigint, text
) set search_path = '';

alter function public.fulus_api_update_expense(
  uuid, uuid, uuid, text, uuid, uuid, numeric, text, text, timestamptz, text, text
) set search_path = '';

alter function public.fulus_api_update_expense(
  uuid, uuid, uuid, text, uuid, uuid, numeric, text, text, timestamptz, text
) set search_path = '';

alter function public.fulus_api_create_location(
  uuid, uuid, text, text, text, text, text, text
) set search_path = '';

alter function public.fulus_api_create_location(
  uuid, uuid, text, text, text, text, text, text, text
) set search_path = '';

alter function public.fulus_api_create_location(
  uuid, uuid, text, text, text, text, text, text, text
) set search_path = '';
