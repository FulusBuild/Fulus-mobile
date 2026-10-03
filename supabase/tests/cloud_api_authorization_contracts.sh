#!/usr/bin/env bash
set -euo pipefail

reporting="supabase/functions/fulus-reporting-api/index.ts"
inventory_migration="supabase/migrations/20261003110000_enforce_inventory_set_permission.sql"

grep -F 'target_permission:"reports.read"' "$reporting" >/dev/null
grep -F '.eq("registered_by",u.user.id)' "$reporting" >/dev/null
grep -F "public.has_permission(target_business_id, 'inventory.adjust')" "$inventory_migration" >/dev/null

echo "PASS: cloud API authorization contracts are present"
