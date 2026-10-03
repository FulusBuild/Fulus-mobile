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

echo "PASS: cloud API authorization contracts are present"

# Client-facing Cloud API error responses must not expose raw Postgres/Supabase
# messages. Server-side logging of error.message is allowed for diagnostics.
if grep -RIn --include='*.ts' -E 'message:[[:space:]]*error\.message|message:[[:space:]]*err\.message' supabase/functions; then
  echo "Cloud API source exposes raw database error messages to clients"
  exit 1
fi
