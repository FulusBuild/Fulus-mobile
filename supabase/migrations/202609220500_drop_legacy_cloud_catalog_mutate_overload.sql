-- Remove the obsolete catalog mutation overload.
-- The live API contract uses the bigint base-cursor argument so optimistic
-- concurrency cannot silently fall back to the legacy no-cursor signature.
drop function if exists public.cloud_catalog_mutate(uuid, uuid, uuid, text, text, text, uuid, jsonb, text);
