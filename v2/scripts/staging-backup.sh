#!/bin/sh

set -eu
umask 077

v2_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$v2_root/scripts/lib/staging-env.sh"
. "$v2_root/scripts/lib/staging-checksum.sh"
. "$v2_root/scripts/lib/staging-path.sh"

fail() {
  echo "staging backup failed: $1" >&2
  exit 1
}

[ "$#" -eq 2 ] || fail "usage: staging-backup.sh ENV_FILE BACKUP_ROOT"
environment_file=$1
backup_root=$2
repository_root=$(CDPATH= cd -- "$v2_root/.." && pwd -P)

"$v2_root/scripts/staging-preflight.sh" "$environment_file" migration >/dev/null
backup_root=$(staging_external_directory "$backup_root" "$repository_root") || \
  fail "backup root must be an existing directory outside the Git repository"

database_url=$(staging_env_require "$environment_file" DATABASE_URL) || exit 1
release_sha=$(staging_env_require "$environment_file" CLOVERY_RELEASE_SHA) || exit 1
database_name=$(staging_database_name "$database_url") || fail "unable to determine database name"

pg_dump_bin=${PG_DUMP_BIN:-pg_dump}
psql_bin=${PSQL_BIN:-psql}
command -v "$pg_dump_bin" >/dev/null 2>&1 || fail "pg_dump is unavailable"
command -v "$psql_bin" >/dev/null 2>&1 || fail "psql is unavailable"

chmod 700 "$backup_root"
pending_directory=$(mktemp -d "$backup_root/.pending.XXXXXX")
chmod 700 "$pending_directory"
cleanup_pending() {
  [ -z "${pending_directory:-}" ] || rm -rf -- "$pending_directory"
}
trap cleanup_pending EXIT HUP INT TERM

dump_path="$pending_directory/database.dump"
"$pg_dump_bin" --format=custom --no-owner --no-privileges --file="$dump_path" "$database_url"
chmod 600 "$dump_path"

dump_sha256=$(staging_sha256 "$dump_path") || fail "unable to calculate dump checksum"
printf '%s  %s\n' "$dump_sha256" "database.dump" >"$pending_directory/database.dump.sha256"

migration_state=$("$psql_bin" "$database_url" -X -A -t -F '|' -v ON_ERROR_STOP=1 \
  -c "SELECT COALESCE(MAX(version), 0), COALESCE(bool_or(dirty), false) FROM schema_migrations;")
migration_version=${migration_state%%|*}
migration_dirty=${migration_state#*|}
[ -n "$migration_version" ] || fail "migration version query returned no value"
[ -n "$migration_dirty" ] || fail "migration state query returned no value"
[ "$migration_dirty" = "f" ] || fail "database migration state is dirty"

created_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
directory_stamp=$(date -u '+%Y%m%dT%H%M%SZ')
short_sha=$(printf '%s' "$release_sha" | cut -c1-12)
final_directory="$backup_root/$directory_stamp-$short_sha"
[ ! -e "$final_directory" ] || fail "backup destination already exists"

cat >"$pending_directory/metadata.env" <<EOF
backup_format=1
created_at=$created_at
release_sha=$release_sha
database_name=$database_name
migration_version=$migration_version
migration_dirty=$migration_dirty
dump_sha256=$dump_sha256
EOF
chmod 600 "$pending_directory/database.dump.sha256" "$pending_directory/metadata.env"
mv "$pending_directory" "$final_directory"
pending_directory=
trap - EXIT HUP INT TERM

printf '%s\n' "$final_directory"
