#!/bin/sh

set -eu
umask 077

v2_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$v2_root/scripts/lib/staging-env.sh"
. "$v2_root/scripts/lib/staging-checksum.sh"
. "$v2_root/scripts/lib/staging-path.sh"

fail() {
  echo "staging restore drill failed: $1" >&2
  exit 1
}

[ "$#" -eq 3 ] || fail "usage: staging-restore-drill.sh STAGING_ENV BACKUP_DIRECTORY RESTORE_ENV"
staging_environment=$1
backup_directory=$2
restore_environment=$3
repository_root=$(CDPATH= cd -- "$v2_root/.." && pwd -P)

"$v2_root/scripts/staging-preflight.sh" "$staging_environment" runtime >/dev/null
[ -d "$backup_directory" ] || fail "backup directory does not exist"
backup_directory=$(staging_external_directory "$backup_directory" "$repository_root") || \
  fail "backup directory must be outside the Git repository"
[ -r "$restore_environment" ] || fail "restore environment file is not readable"

source_database_url=$(staging_env_require "$staging_environment" DATABASE_URL) || exit 1
staging_release_sha=$(staging_env_require "$staging_environment" CLOVERY_RELEASE_SHA) || exit 1
restore_database_url=$(staging_env_require "$restore_environment" RESTORE_DATABASE_URL) || exit 1
restore_environment_name=$(staging_env_require "$restore_environment" RESTORE_DRILL_ENVIRONMENT) || exit 1
restore_confirmation=$(staging_env_require "$restore_environment" CLOVERY_ALLOW_RESTORE_DRILL) || exit 1

[ "$restore_environment_name" = "staging" ] || fail "RESTORE_DRILL_ENVIRONMENT must be staging"
[ "$restore_confirmation" = "yes" ] || fail "CLOVERY_ALLOW_RESTORE_DRILL=yes is required"
[ "$source_database_url" != "$restore_database_url" ] || fail "restore database must differ from the source"

case "$restore_database_url" in
  postgres://?*/*|postgresql://?*/*) ;;
  *) fail "RESTORE_DATABASE_URL must use PostgreSQL" ;;
esac
staging_database_requires_tls "$restore_database_url" || fail "RESTORE_DATABASE_URL must require TLS"

restore_database_name=$(staging_database_name "$restore_database_url") || fail "unable to determine restore database name"
source_database_name=$(staging_database_name "$source_database_url") || fail "unable to determine source database name"
[ "$source_database_name" != "$restore_database_name" ] || fail "restore database name matches the source database"
case "$restore_database_name" in
  *_restore|*_restore_drill) ;;
  *) fail "restore database name must end in _restore or _restore_drill" ;;
esac

dump_path="$backup_directory/database.dump"
checksum_path="$backup_directory/database.dump.sha256"
metadata_path="$backup_directory/metadata.env"
[ -r "$dump_path" ] || fail "database dump is missing"
[ -r "$checksum_path" ] || fail "database checksum is missing"
[ -r "$metadata_path" ] || fail "backup metadata is missing"

expected_checksum=$(awk 'NR == 1 { print $1 }' "$checksum_path")
actual_checksum=$(staging_sha256 "$dump_path") || fail "unable to calculate dump checksum"
[ "$actual_checksum" = "$expected_checksum" ] || fail "database dump checksum does not match"
backup_release_sha=$(staging_env_require "$metadata_path" release_sha) || exit 1
[ "$backup_release_sha" = "$staging_release_sha" ] || fail "backup release SHA does not match staging"

pg_restore_bin=${PG_RESTORE_BIN:-pg_restore}
psql_bin=${PSQL_BIN:-psql}
migrate_bin=${CLOVERY_MIGRATE_BIN:-$v2_root/services/api/clovery-migrate}
command -v "$pg_restore_bin" >/dev/null 2>&1 || fail "pg_restore is unavailable"
command -v "$psql_bin" >/dev/null 2>&1 || fail "psql is unavailable"
[ -x "$migrate_bin" ] || fail "CLOVERY_MIGRATE_BIN must point to the migration binary"

"$pg_restore_bin" --exit-on-error --clean --if-exists --no-owner --no-privileges \
  --dbname="$restore_database_url" "$dump_path"

DATABASE_URL="$restore_database_url" MIGRATIONS_PATH="$v2_root/services/api/migrations" \
  "$migrate_bin" up

integrity_json=$("$psql_bin" "$restore_database_url" -X -A -t -v ON_ERROR_STOP=1 -c \
  "SELECT json_build_object('accounts',(SELECT count(*) FROM clovery_accounts),'vaults',(SELECT count(*) FROM vaults),'journal_entries',(SELECT count(*) FROM journal_entries),'assets',(SELECT count(*) FROM vault_assets),'transactions',(SELECT count(*) FROM store_transactions),'entitlements',(SELECT count(*) FROM entitlements))::text;")
[ -n "$integrity_json" ] || fail "restore integrity query returned no evidence"

created_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
directory_stamp=$(date -u '+%Y%m%dT%H%M%SZ')
evidence_path="$backup_directory/restore-evidence-$directory_stamp.env"
[ ! -e "$evidence_path" ] || fail "restore evidence destination already exists"

cat >"$evidence_path" <<EOF
restore_evidence_format=1
created_at=$created_at
release_sha=$backup_release_sha
restore_database=$restore_database_name
dump_sha256=$actual_checksum
integrity_json=$integrity_json
EOF
chmod 600 "$evidence_path"

printf '%s\n' "$evidence_path"
