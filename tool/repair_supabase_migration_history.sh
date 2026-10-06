#!/usr/bin/env bash
set -euo pipefail

: "${SUPABASE_ACCESS_TOKEN:?SUPABASE_ACCESS_TOKEN is required}"
: "${SUPABASE_PROJECT_ID:?SUPABASE_PROJECT_ID is required}"
: "${SUPABASE_DB_PASSWORD:?SUPABASE_DB_PASSWORD is required}"

legacy_a="20261005130616"
legacy_b="20261005130721"
current_a="20261005093000"
current_b="20261005131000"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

curl --fail --silent --show-error --location \
  -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
  -H "Accept: application/json" \
  "https://api.supabase.com/v1/projects/${SUPABASE_PROJECT_ID}/database/migrations" |
  jq -r '.[] | [.version, .name] | @tsv' |
  sort > "$tmp_file"

has() {
  awk -v v="$1" '$1 == v { print 1; exit }' "$tmp_file"
}

has_legacy_a="$(has "$legacy_a")"
has_legacy_b="$(has "$legacy_b")"
has_current_a="$(has "$current_a")"
has_current_b="$(has "$current_b")"

if [[ -z "$has_legacy_a" && -z "$has_legacy_b" ]]; then
  if [[ -n "$has_current_a" && -n "$has_current_b" ]]; then
    echo "Production money-normalizer migration history is already repaired."
    exit 0
  fi
  echo "No known legacy money-normalizer history found; no repair required."
  exit 0
fi

if [[ -z "$has_legacy_a" || -z "$has_legacy_b" ]]; then
  echo "::error::Production contains only part of the known legacy money-normalizer migration pair."
  echo "::error::Refusing automatic migration-history repair."
  cat "$tmp_file"
  exit 1
fi

if [[ -n "$has_current_a" || -n "$has_current_b" ]]; then
  echo "::error::Production contains both legacy and current money-normalizer migration IDs."
  echo "::error::Refusing automatic migration-history repair."
  cat "$tmp_file"
  exit 1
fi

echo "Repairing known legacy money-normalizer IDs:"
echo "  $legacy_a -> $current_a"
echo "  $legacy_b -> $current_b"
echo "This changes migration history only; it does not execute either migration."

cd "$repo_root"
supabase link --project-ref "${SUPABASE_PROJECT_ID}" --password "${SUPABASE_DB_PASSWORD}" >/dev/null
supabase migration repair "$legacy_b" "$legacy_a" --status reverted
supabase migration repair "$current_a" "$current_b" --status applied

echo "Legacy money-normalizer migration history repaired."
