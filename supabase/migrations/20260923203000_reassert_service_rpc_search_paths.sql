-- Final security-definer search_path pin for the service RPCs that were
-- reintroduced by earlier schema migrations with search_path=public.
--
-- Keep this migration intentionally narrow: ALTER FUNCTION changes only the
-- function-level GUC and preserves the hardened function body, including the
-- row locks added by the optimistic-concurrency hardening migration.

alter function public.fulus_api_update_customer(
  uuid,uuid,uuid,text,uuid,text,text,text,text,text,numeric,boolean,bigint,text
) set search_path = '';

alter function public.fulus_api_update_expense(
  uuid,uuid,uuid,text,uuid,uuid,numeric,text,text,timestamptz,text,bigint,text
) set search_path = '';
