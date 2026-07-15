#!/bin/sh

set -eu

v2_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
backup_script="$v2_root/scripts/staging-backup.sh"
restore_script="$v2_root/scripts/staging-restore-drill.sh"
fixture="$v2_root/scripts/testlib/staging-fixture.sh"
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/clovery-staging-data.XXXXXX")
repository_backup_root="$v2_root/.staging-backup-test-$$"
trap 'rm -rf "$temporary_directory" "$repository_backup_root"' EXIT HUP INT TERM

. "$fixture"

fail() {
  echo "staging data-safety test failed: $1" >&2
  exit 1
}

expect_failure() {
  if "$@" >/dev/null 2>&1; then
    fail "command unexpectedly succeeded: $*"
  fi
}

[ -x "$backup_script" ] || fail "missing executable staging-backup.sh"
[ -x "$restore_script" ] || fail "missing executable staging-restore-drill.sh"

environment_file="$temporary_directory/staging.env"
write_staging_environment_fixture "$environment_file"

fake_directory="$temporary_directory/fake-bin"
mkdir -p "$fake_directory"

cat >"$fake_directory/pg_dump" <<'EOF'
#!/bin/sh
set -eu
for argument in "$@"; do
  case "$argument" in
    --file=*) output=${argument#--file=} ;;
  esac
done
[ -n "${output:-}" ]
printf 'clovery-test-dump' >"$output"
EOF

cat >"$fake_directory/psql" <<'EOF'
#!/bin/sh
set -eu
[ "${FAKE_PSQL_FAIL:-false}" != "true" ] || exit 1
case "$*" in
  *schema_migrations*) printf '15|f\n' ;;
  *) printf '{"accounts":2,"vaults":2,"journal_entries":3}\n' ;;
esac
EOF

cat >"$fake_directory/pg_restore" <<EOF
#!/bin/sh
set -eu
printf '%s\n' "\$*" >>"$temporary_directory/pg_restore.calls"
EOF

cat >"$fake_directory/migrate" <<EOF
#!/bin/sh
set -eu
printf '%s\n' "\$*" >>"$temporary_directory/migrate.calls"
EOF

chmod +x "$fake_directory/pg_dump" "$fake_directory/psql" \
  "$fake_directory/pg_restore" "$fake_directory/migrate"

mkdir -p "$repository_backup_root"
expect_failure env PG_DUMP_BIN="$fake_directory/pg_dump" PSQL_BIN="$fake_directory/psql" \
  "$backup_script" "$environment_file" "$repository_backup_root"

failed_backup_root="$temporary_directory/failed-backups"
mkdir -p "$failed_backup_root"
expect_failure env FAKE_PSQL_FAIL=true PG_DUMP_BIN="$fake_directory/pg_dump" \
  PSQL_BIN="$fake_directory/psql" \
  "$backup_script" "$environment_file" "$failed_backup_root"
if find "$failed_backup_root" -maxdepth 1 -name '.pending.*' -print | grep -q .; then
  fail "failed backup left a pending database dump"
fi

backup_root="$temporary_directory/backups"
mkdir -p "$backup_root"
backup_directory=$(PG_DUMP_BIN="$fake_directory/pg_dump" PSQL_BIN="$fake_directory/psql" \
  "$backup_script" "$environment_file" "$backup_root")

[ -d "$backup_directory" ] || fail "backup directory was not created"
[ -f "$backup_directory/database.dump" ] || fail "database dump is missing"
[ -f "$backup_directory/database.dump.sha256" ] || fail "database checksum is missing"
[ -f "$backup_directory/metadata.env" ] || fail "backup metadata is missing"
grep -Fq 'migration_version=15' "$backup_directory/metadata.env" || fail "migration version was not recorded"
if grep -Eq 'strong-password|DATABASE_URL|postgres\.staging' "$backup_directory/metadata.env"; then
  fail "backup metadata contains database credentials or endpoint"
fi

unsafe_restore_environment="$temporary_directory/unsafe-restore.env"
cat >"$unsafe_restore_environment" <<EOF
RESTORE_DRILL_ENVIRONMENT=staging
RESTORE_DATABASE_URL=postgres://clovery:restore-password@restore.staging.clovery.cn:5432/clovery?sslmode=verify-full
CLOVERY_ALLOW_RESTORE_DRILL=yes
EOF
expect_failure "$restore_script" "$environment_file" "$backup_directory" "$unsafe_restore_environment"

tls_bypass_restore_environment="$temporary_directory/tls-bypass-restore.env"
cat >"$tls_bypass_restore_environment" <<EOF
RESTORE_DRILL_ENVIRONMENT=staging
RESTORE_DATABASE_URL=postgres://clovery:restore-password@restore.staging.clovery.cn:5432/clovery_restore?sslmode=disable&note=sslmode=require
CLOVERY_ALLOW_RESTORE_DRILL=yes
EOF
expect_failure env PG_RESTORE_BIN="$fake_directory/pg_restore" PSQL_BIN="$fake_directory/psql" \
  CLOVERY_MIGRATE_BIN="$fake_directory/migrate" \
  "$restore_script" "$environment_file" "$backup_directory" "$tls_bypass_restore_environment"

restore_environment="$temporary_directory/restore.env"
cat >"$restore_environment" <<EOF
RESTORE_DRILL_ENVIRONMENT=staging
RESTORE_DATABASE_URL=postgres://clovery:restore-password@restore.staging.clovery.cn:5432/clovery_restore?sslmode=verify-full
CLOVERY_ALLOW_RESTORE_DRILL=yes
EOF

mismatched_environment="$temporary_directory/mismatched-staging.env"
sed \
  -e 's/5265c62b03b8e53fbe6ebb10c50d5d5d402cef42/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/' \
  -e "s|^CLOVERY_ENV_FILE=.*$|CLOVERY_ENV_FILE=$mismatched_environment|" \
  "$environment_file" >"$mismatched_environment"
expect_failure env PG_RESTORE_BIN="$fake_directory/pg_restore" PSQL_BIN="$fake_directory/psql" \
  CLOVERY_MIGRATE_BIN="$fake_directory/migrate" \
  "$restore_script" "$mismatched_environment" "$backup_directory" "$restore_environment"

PG_RESTORE_BIN="$fake_directory/pg_restore" PSQL_BIN="$fake_directory/psql" \
  CLOVERY_MIGRATE_BIN="$fake_directory/migrate" \
  "$restore_script" "$environment_file" "$backup_directory" "$restore_environment" >/dev/null

[ -s "$temporary_directory/pg_restore.calls" ] || fail "restore command was not executed"
[ -s "$temporary_directory/migrate.calls" ] || fail "migration command was not executed"
restore_evidence=$(find "$backup_directory" -maxdepth 1 -name 'restore-evidence-*.env' -type f | head -1)
[ -n "$restore_evidence" ] || fail "restore evidence is missing"
grep -Fq 'restore_database=clovery_restore' "$restore_evidence" || fail "restore database name was not recorded"
if grep -Eq 'restore-password|RESTORE_DATABASE_URL|restore\.staging' "$restore_evidence"; then
  fail "restore evidence contains credentials or endpoint"
fi

echo "staging backup and restore safety verified"
