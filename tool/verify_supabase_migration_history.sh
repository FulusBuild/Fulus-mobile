#!/usr/bin/env bash
set -euo pipefail

: "${SUPABASE_ACCESS_TOKEN:?SUPABASE_ACCESS_TOKEN is required}"
: "${SUPABASE_PROJECT_ID:?SUPABASE_PROJECT_ID is required}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
migration_dir="$repo_root/supabase/migrations"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

local_file="$tmp_dir/local.tsv"
remote_file="$tmp_dir/remote.tsv"

find "$migration_dir" -maxdepth 1 -type f -name '*.sql' -printf '%f\n' |
  sed -E 's/\.sql$//' |
  awk -F_ '{version=$1; $1=""; sub(/^_/,""); print version "\t" $0}' |
  sort > "$local_file"

curl --fail --silent --show-error --location \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Accept: application/json" \
  "https://api.supabase.com/v1/projects/${SUPABASE_PROJECT_ID}/database/migrations" |
  jq -r '.[] | [.version, .name] | @tsv' |
  sort > "$remote_file"

if ! diff -u "$remote_file" "$local_file"; then
  echo "::error::Production Supabase migration history does not exactly match the repository migration chain."
  echo "::error::Do not run supabase db push until the history is repaired."
  exit 1
fi

echo "Production migration history matches repository: $(wc -l < "$local_file") migrations."
