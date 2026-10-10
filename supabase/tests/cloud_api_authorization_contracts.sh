#!/usr/bin/env bash
set -euo pipefail

reporting="supabase/functions/fulus-reporting-api/index.ts"
inventory_migration="supabase/migrations/20261003110000_enforce_inventory_set_permission.sql"
diagnostics="supabase/functions/fulus-diagnostics/index.ts"

grep -F 'target_permission:"reports.read"' "$reporting" >/dev/null
grep -F '.eq("registered_by",u.user.id)' "$reporting" >/dev/null
grep -F "public.has_permission(target_business_id, 'inventory.adjust')" "$inventory_migration" >/dev/null
grep -F 'DIAGNOSTIC_EVENT_TOO_LARGE' "$diagnostics" >/dev/null
grep -F '.eq("registered_by", ud.user.id)' "$diagnostics" >/dev/null
# Location-filtered sync must resolve a ledger entry's sale location when
# customer ownership is legacy/shared, then fall back to explicit customer owner.
grep -F 'payload?.sale_id === "string" ? [payload.sale_id] : []' supabase/functions/fulus-api/index.ts >/dev/null
grep -F 'const saleLocationId = saleId ? saleLocationBySaleId.get(saleId) : undefined;' supabase/functions/fulus-api/index.ts >/dev/null
# Customers share the location-scoped catalog read contract, but remain on their
# dedicated customer mutation RPCs rather than the generic catalog writer.
grep -F 'const readableEntities = ["products", "customers", "categories", "suppliers"];' supabase/functions/fulus-api/index.ts >/dev/null
grep -F 'action === "catalog_list" ? readableEntities : mutableEntities' supabase/functions/fulus-api/index.ts >/dev/null
grep -F 'entity === "customers" ? "customers.read" : "catalog.read"' supabase/functions/fulus-api/index.ts >/dev/null

echo "PASS: cloud API authorization contracts are present"

# Client-facing Cloud API error responses must not expose raw Postgres/Supabase
# messages. Server-side logging of error.message is allowed for diagnostics.
# Match a real object property named exactly "message", not fields such as
# "error_message" used for structured server-side logging.
if grep -RIn --include='*.ts' -E '(^|[[:space:]{,])message:[[:space:]]*(error|err)\.message' supabase/functions; then
  echo "Cloud API source exposes raw database error messages to clients"
  exit 1
fi

# Legacy ownership review is exposed only through administrator-gated API
# actions and an actor-validating, service-role-only transactional RPC.
grep -F 'action === "location_ownership_review_list" || action === "location_ownership_review_resolve"' supabase/functions/fulus-api/index.ts >/dev/null
grep -F 'role?.name !== "owner" && role?.name !== "admin"' supabase/functions/fulus-api/index.ts >/dev/null
grep -F 'fulus_api_resolve_location_ownership' supabase/functions/fulus-api/index.ts >/dev/null
grep -F "grant execute on function public.fulus_api_resolve_location_ownership(uuid, uuid, uuid, uuid)" supabase/migrations/20261010200000_add_location_ownership_review_resolution.sql >/dev/null
grep -F "Selected location must be active and belong to the same business" supabase/migrations/20261010200000_add_location_ownership_review_resolution.sql >/dev/null
