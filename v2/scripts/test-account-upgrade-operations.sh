#!/bin/sh

set -eu

v2_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
backup_script="$v2_root/scripts/backup-before-account-bootstrap.sh"
verify_script="$v2_root/scripts/verify-account-bootstrap-migrations.sh"

fail() {
  echo "account upgrade operations test failed: $1" >&2
  exit 1
}

[ -x "$backup_script" ] || fail "missing executable backup-before-account-bootstrap.sh"
[ -x "$verify_script" ] || fail "missing executable verify-account-bootstrap-migrations.sh"

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/clovery-account-upgrade.XXXXXX")
repository_output="$v2_root/.account-upgrade-test-$$"
trap 'rm -rf "$temporary_directory" "$repository_output"' EXIT HUP INT TERM

expect_failure() {
  if "$@" >/dev/null 2>&1; then
    fail "command unexpectedly succeeded: $*"
  fi
}

fake_bin="$temporary_directory/bin"
evidence_directory="$temporary_directory/evidence"
mkdir -p "$fake_bin" "$evidence_directory" "$repository_output"

cat >"$fake_bin/pg_dump" <<'EOF'
#!/bin/sh
set -eu
if [ "${1:-}" = "--version" ]; then
  echo "pg_dump (PostgreSQL) 17.0"
  exit 0
fi
for argument in "$@"; do
  case "$argument" in
    --file=*) output=${argument#--file=} ;;
  esac
done
[ -n "${output:-}" ]
printf 'account-upgrade-dump' >"$output"
EOF

cat >"$fake_bin/psql" <<'EOF'
#!/bin/sh
set -eu
case "$*" in
  *account-upgrade:server-version*) echo 170000 ;;
  *account-upgrade:backup-migration-state*) echo '15|f' ;;
  *account-upgrade:verify-migration-state*) echo '17|f' ;;
  *account-upgrade:account-count*) echo "${FAKE_ACCOUNT_COUNT:-1}" ;;
  *account-upgrade:vault-count*) echo 1 ;;
  *account-upgrade:entitlement-count*) echo 2 ;;
  *account-upgrade:identity-digest*) echo 1 ;;
  *account-upgrade:raw-token*) echo "${FAKE_RAW_TOKEN_COUNT:-0}" ;;
  *account-upgrade:bootstrap-uniqueness*) echo 2 ;;
  *account-upgrade:resolution-constraints*) echo 3 ;;
  *account-upgrade:resolution-index*) echo 1 ;;
  *account-upgrade:orphan-identities*) echo 0 ;;
  *account-upgrade:orphan-vaults*) echo 0 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$fake_bin/pg_dump" "$fake_bin/psql"

database_url='postgresql://database.fixture.invalid/clovery?sslmode=verify-full'
expect_failure env PG_DUMP_BIN="$fake_bin/pg_dump" PSQL_BIN="$fake_bin/psql" \
  "$backup_script" "$database_url" "$repository_output"

dump_path=$(PG_DUMP_BIN="$fake_bin/pg_dump" PSQL_BIN="$fake_bin/psql" \
  "$backup_script" "$database_url" "$evidence_directory")
metadata_path="$evidence_directory/clovery-before-1.1.0.metadata.env"
checksum_path="$dump_path.sha256"
[ -f "$dump_path" ] || fail "backup dump is missing"
[ -f "$metadata_path" ] || fail "backup metadata is missing"
[ -f "$checksum_path" ] || fail "backup checksum is missing"

file_mode() {
  stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"
}
for path in "$dump_path" "$metadata_path" "$checksum_path"; do
  [ "$(file_mode "$path")" = "600" ] || fail "release evidence mode is not 0600"
done
grep -Fq 'migration_version=15' "$metadata_path" || fail "migration version was not recorded"
grep -Fq 'postgres_server_version_num=170000' "$metadata_path" || fail "server version was not recorded"
grep -Fq 'baseline_entitlement_count=2' "$metadata_path" || fail "baseline counts were not recorded"
if grep -Eq 'database\.fixture\.invalid|DATABASE_URL' "$metadata_path"; then
  fail "backup metadata contains database credentials or endpoint"
fi
expect_failure env PG_DUMP_BIN="$fake_bin/pg_dump" PSQL_BIN="$fake_bin/psql" \
  "$backup_script" "$database_url" "$evidence_directory"

PSQL_BIN="$fake_bin/psql" "$verify_script" "$database_url" "$metadata_path" >/dev/null
expect_failure env FAKE_ACCOUNT_COUNT=2 PSQL_BIN="$fake_bin/psql" \
  "$verify_script" "$database_url" "$metadata_path"
expect_failure env FAKE_RAW_TOKEN_COUNT=1 PSQL_BIN="$fake_bin/psql" \
  "$verify_script" "$database_url" "$metadata_path"

database_runbook="$v2_root/docs/release/ios-1.1.0-database-runbook.md"
rollback_runbook="$v2_root/docs/release/ios-1.1.0-rollback-runbook.md"
grep -Fq 'MIGRATION_WRITES_ENABLED=false' "$database_runbook" || fail "database runbook does not freeze migration writes"
grep -Fq '迁移版本 `15`' "$database_runbook" || fail "database runbook does not lock the baseline version"
grep -Fq '不执行生产 `down` migration' "$rollback_runbook" || fail "rollback runbook does not prohibit destructive downgrade"
grep -Fq '保留版本 `17`' "$rollback_runbook" || fail "rollback runbook does not preserve additive schema"

echo "account upgrade backup and migration verification contracts passed"
