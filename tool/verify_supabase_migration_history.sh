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

remote_count="$(wc -l < "$remote_file")"
local_count="$(wc -l < "$local_file")"

if [ "$remote_count" -gt "$local_count" ]; then
  echo "::error::Production Supabase migration history contains migrations that are not present in the repository."
  echo "::error::Do not run supabase db push until the history is repaired."
  exit 1
fi

if ! head -n "$remote_count" "$local_file" | diff -u "$remote_file" -; then
  echo "::error::Production Supabase migration history is not an exact prefix of the repository migration chain."
  echo "::error::Do not run supabase db push until the history is repaired."
  exit 1
fi

if [ "$remote_count" -lt "$local_count" ]; then
  echo "Production migration history is a valid prefix: $remote_count applied, $((local_count - remote_count)) pending."
else
  echo "Production migration history matches repository: $local_count migrations."
fi
