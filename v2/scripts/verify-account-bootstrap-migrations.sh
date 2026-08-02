#!/bin/sh

set -eu

v2_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$v2_root/scripts/lib/staging-env.sh"
. "$v2_root/scripts/lib/staging-path.sh"

fail() {
  echo "account bootstrap migration verification failed: $1" >&2
  exit 1
}

[ "$#" -eq 2 ] || fail "usage: verify-account-bootstrap-migrations.sh DATABASE_URL BASELINE_METADATA"
database_url=$1
baseline_metadata=$2
repository_root=$(CDPATH= cd -- "$v2_root/.." && pwd -P)

case "$database_url" in
  postgres://?*/*|postgresql://?*/*) ;;
  *) fail "DATABASE_URL must use PostgreSQL" ;;
esac
[ -r "$baseline_metadata" ] || fail "baseline metadata is not readable"
baseline_directory=$(dirname "$baseline_metadata")
staging_external_directory "$baseline_directory" "$repository_root" >/dev/null || \
  fail "baseline metadata must be outside the Git repository"

expected_accounts=$(staging_env_require "$baseline_metadata" baseline_account_count) || exit 1
expected_vaults=$(staging_env_require "$baseline_metadata" baseline_vault_count) || exit 1
expected_entitlements=$(staging_env_require "$baseline_metadata" baseline_entitlement_count) || exit 1
baseline_migration_version=$(staging_env_require "$baseline_metadata" migration_version) || exit 1
baseline_migration_dirty=$(staging_env_require "$baseline_metadata" migration_dirty) || exit 1
[ "$baseline_migration_version" = "15" ] || fail "baseline metadata must come from migration version 15"
[ "$baseline_migration_dirty" = "f" ] || fail "baseline metadata records a dirty migration"
for count in "$expected_accounts" "$expected_vaults" "$expected_entitlements"; do
  printf '%s\n' "$count" | grep -Eq '^[0-9]+$' || fail "baseline metadata contains an invalid row count"
done

psql_bin=${PSQL_BIN:-psql}
command -v "$psql_bin" >/dev/null 2>&1 || fail "psql is unavailable"

sql_scalar() {
  query=$1
  "$psql_bin" "$database_url" -X -A -t -v ON_ERROR_STOP=1 -c "$query" | tr -d '[:space:]'
}

expect_value() {
  check_name=$1
  query=$2
  expected=$3
  actual=$(sql_scalar "$query")
  [ "$actual" = "$expected" ] || fail "$check_name"
}

expect_value "schema version must be 17 and clean" \
  "/* account-upgrade:verify-migration-state */ SELECT COALESCE(MAX(version), 0) || '|' || CASE WHEN COALESCE(bool_or(dirty), false) THEN 't' ELSE 'f' END FROM schema_migrations;" \
  "17|f"
expect_value "identity claim digest column is missing" \
  "/* account-upgrade:identity-digest */ SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'identity_claims' AND column_name = 'token_sha256';" \
  "1"
expect_value "identity claims contain a raw-token column" \
  "/* account-upgrade:raw-token */ SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'identity_claims' AND column_name LIKE '%token%' AND column_name <> 'token_sha256';" \
  "0"
expect_value "account bootstrap account/Vault uniqueness is missing" \
  "/* account-upgrade:bootstrap-uniqueness */ SELECT COUNT(*) FROM pg_constraint WHERE conrelid = 'account_bootstrap_jobs'::regclass AND conname IN ('account_bootstrap_jobs_pkey', 'account_bootstrap_jobs_vault_id_key');" \
  "2"
expect_value "migration resolution constraints are incomplete" \
  "/* account-upgrade:resolution-constraints */ SELECT COUNT(*) FROM pg_constraint WHERE conrelid = 'migration_entries'::regclass AND conname IN ('migration_entries_resolution_check', 'migration_entries_dedup_sha256_format', 'migration_entries_resolution_target_check');" \
  "3"
expect_value "migration resolution index is missing" \
  "/* account-upgrade:resolution-index */ SELECT COUNT(*) FROM pg_indexes WHERE schemaname = current_schema() AND indexname = 'journal_entries_vault_dedup_sha_idx';" \
  "1"
expect_value "account row count differs from the pre-upgrade baseline" \
  "/* account-upgrade:account-count */ SELECT COUNT(*) FROM clovery_accounts;" \
  "$expected_accounts"
expect_value "Vault row count differs from the pre-upgrade baseline" \
  "/* account-upgrade:vault-count */ SELECT COUNT(*) FROM vaults;" \
  "$expected_vaults"
expect_value "entitlement row count differs from the pre-upgrade baseline" \
  "/* account-upgrade:entitlement-count */ SELECT COUNT(*) FROM entitlements;" \
  "$expected_entitlements"
expect_value "orphan external identities exist" \
  "/* account-upgrade:orphan-identities */ SELECT COUNT(*) FROM external_identities AS identity LEFT JOIN clovery_accounts AS account ON account.id = identity.account_id WHERE account.id IS NULL;" \
  "0"
expect_value "orphan Vaults exist" \
  "/* account-upgrade:orphan-vaults */ SELECT COUNT(*) FROM vaults AS vault LEFT JOIN clovery_accounts AS account ON account.id = vault.owner_account_id WHERE account.id IS NULL;" \
  "0"

echo "account bootstrap migration verification: PASS"
