#!/bin/sh

set -eu
umask 077

v2_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$v2_root/scripts/lib/staging-checksum.sh"
. "$v2_root/scripts/lib/staging-path.sh"

fail() {
  echo "account bootstrap backup failed: $1" >&2
  exit 1
}

[ "$#" -eq 2 ] || fail "usage: backup-before-account-bootstrap.sh DATABASE_URL OUTPUT_DIRECTORY"
database_url=$1
output_directory=$2
repository_root=$(CDPATH= cd -- "$v2_root/.." && pwd -P)

case "$database_url" in
  postgres://?*/*|postgresql://?*/*) ;;
  *) fail "DATABASE_URL must use PostgreSQL" ;;
esac
output_directory=$(staging_external_directory "$output_directory" "$repository_root") || \
  fail "output directory must exist outside the Git repository"

pg_dump_bin=${PG_DUMP_BIN:-pg_dump}
psql_bin=${PSQL_BIN:-psql}
command -v "$pg_dump_bin" >/dev/null 2>&1 || fail "pg_dump is unavailable"
command -v "$psql_bin" >/dev/null 2>&1 || fail "psql is unavailable"

dump_path="$output_directory/clovery-before-1.1.0.dump"
checksum_path="$dump_path.sha256"
metadata_path="$output_directory/clovery-before-1.1.0.metadata.env"
for path in "$dump_path" "$checksum_path" "$metadata_path"; do
  [ ! -e "$path" ] || fail "refusing to overwrite existing release evidence"
done

pending_directory=$(mktemp -d "$output_directory/.clovery-backup.XXXXXX")
chmod 700 "$pending_directory"
cleanup_pending() {
  [ -z "${pending_directory:-}" ] || rm -rf -- "$pending_directory"
}
trap cleanup_pending EXIT HUP INT TERM

pending_dump="$pending_directory/database.dump"
"$pg_dump_bin" --format=custom --no-owner --no-privileges --file="$pending_dump" "$database_url"
chmod 600 "$pending_dump"

sql_scalar() {
  query=$1
  "$psql_bin" "$database_url" -X -A -t -v ON_ERROR_STOP=1 -c "$query" | tr -d '[:space:]'
}

dump_sha256=$(staging_sha256 "$pending_dump") || fail "unable to calculate dump checksum"
server_version=$(sql_scalar "/* account-upgrade:server-version */ SHOW server_version_num;")
migration_state=$(sql_scalar "/* account-upgrade:backup-migration-state */ SELECT COALESCE(MAX(version), 0) || '|' || CASE WHEN COALESCE(bool_or(dirty), false) THEN 't' ELSE 'f' END FROM schema_migrations;")
migration_version=${migration_state%%|*}
migration_dirty=${migration_state#*|}
[ -n "$server_version" ] || fail "PostgreSQL server version query returned no value"
[ -n "$migration_version" ] || fail "migration version query returned no value"
[ "$migration_dirty" = "f" ] || fail "database migration state is dirty"
[ "$migration_version" = "15" ] || fail "pre-upgrade database must be at migration version 15"

account_count=$(sql_scalar "/* account-upgrade:account-count */ SELECT COUNT(*) FROM clovery_accounts;")
vault_count=$(sql_scalar "/* account-upgrade:vault-count */ SELECT COUNT(*) FROM vaults;")
entitlement_count=$(sql_scalar "/* account-upgrade:entitlement-count */ SELECT COUNT(*) FROM entitlements;")
for count in "$account_count" "$vault_count" "$entitlement_count"; do
  printf '%s\n' "$count" | grep -Eq '^[0-9]+$' || fail "baseline row count is invalid"
done

pg_dump_version=$("$pg_dump_bin" --version | tr '\n' ' ' | sed 's/[[:space:]]*$//')
created_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
cat >"$pending_directory/metadata.env" <<EOF
backup_format=1
created_at=$created_at
pg_dump_version=$pg_dump_version
postgres_server_version_num=$server_version
migration_version=$migration_version
migration_dirty=$migration_dirty
baseline_account_count=$account_count
baseline_vault_count=$vault_count
baseline_entitlement_count=$entitlement_count
dump_sha256=$dump_sha256
EOF
printf '%s  %s\n' "$dump_sha256" "clovery-before-1.1.0.dump" >"$pending_directory/database.dump.sha256"
chmod 600 "$pending_directory/metadata.env" "$pending_directory/database.dump.sha256"

mv "$pending_dump" "$dump_path"
mv "$pending_directory/database.dump.sha256" "$checksum_path"
mv "$pending_directory/metadata.env" "$metadata_path"
rmdir "$pending_directory"
pending_directory=
trap - EXIT HUP INT TERM

printf '%s\n' "$dump_path"
