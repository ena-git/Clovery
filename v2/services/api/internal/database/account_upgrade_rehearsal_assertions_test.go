package database

import (
	"database/sql"
	"testing"
)

type rehearsalCounts struct {
	accounts           int
	vaults             int
	passwords          int
	externalIdentities int
	federationIntents  int
	journalEntries     int
	migrationEntries   int
	entitlements       int
}

func (rehearsal *accountUpgradeRehearsal) assertPreUpgradeData(t *testing.T) {
	t.Helper()
	rehearsal.assertMigrationVersion(t, 15)
	rehearsal.assertLegacyCounts(t, rehearsalCounts{
		accounts:           1,
		vaults:             1,
		passwords:          1,
		externalIdentities: 1,
		federationIntents:  1,
		journalEntries:     2,
		migrationEntries:   1,
		entitlements:       2,
	})
	rehearsal.assertLegacyRelationships(t)
	rehearsal.assertRelationExists(t, "identity_claims", false)
	rehearsal.assertRelationExists(t, "account_bootstrap_jobs", false)
	rehearsal.assertColumnExists(t, "migration_entries", "resolution", false)
	rehearsal.assertColumnExists(t, "journal_entries", "dedup_sha256", false)
}

func (rehearsal *accountUpgradeRehearsal) assertPostUpgradeData(t *testing.T) {
	t.Helper()
	rehearsal.assertMigrationVersion(t, 17)
	rehearsal.assertLegacyCounts(t, rehearsalCounts{
		accounts:           1,
		vaults:             1,
		passwords:          1,
		externalIdentities: 1,
		federationIntents:  1,
		journalEntries:     2,
		migrationEntries:   1,
		entitlements:       2,
	})
	rehearsal.assertLegacyRelationships(t)
	rehearsal.assertRelationExists(t, "identity_claims", true)
	rehearsal.assertRelationExists(t, "account_bootstrap_jobs", true)
	rehearsal.assertColumnExists(t, "migration_entries", "resolution", true)
	rehearsal.assertColumnExists(t, "journal_entries", "dedup_sha256", true)
	rehearsal.assertResolutionDefaults(t)
	rehearsal.assertUpgradeConstraints(t)
}

func (rehearsal *accountUpgradeRehearsal) assertLegacyCounts(t *testing.T, expected rehearsalCounts) {
	t.Helper()
	queries := []struct {
		name string
		want int
		sql  string
	}{
		{name: "accounts", want: expected.accounts, sql: "SELECT COUNT(*) FROM clovery_accounts"},
		{name: "vaults", want: expected.vaults, sql: "SELECT COUNT(*) FROM vaults"},
		{name: "passwords", want: expected.passwords, sql: "SELECT COUNT(*) FROM password_credentials"},
		{name: "external identities", want: expected.externalIdentities, sql: "SELECT COUNT(*) FROM external_identities"},
		{name: "federation intents", want: expected.federationIntents, sql: "SELECT COUNT(*) FROM federation_intents"},
		{name: "journal entries", want: expected.journalEntries, sql: "SELECT COUNT(*) FROM journal_entries"},
		{name: "migration entries", want: expected.migrationEntries, sql: "SELECT COUNT(*) FROM migration_entries"},
		{name: "entitlements", want: expected.entitlements, sql: "SELECT COUNT(*) FROM entitlements"},
	}
	for _, query := range queries {
		var count int
		if err := rehearsal.database.QueryRow(query.sql).Scan(&count); err != nil {
			t.Fatalf("count %s: %v", query.name, err)
		}
		if count != query.want {
			t.Fatalf("%s count = %d, want %d", query.name, count, query.want)
		}
	}
}

func (rehearsal *accountUpgradeRehearsal) assertLegacyRelationships(t *testing.T) {
	t.Helper()
	var accountID string
	var vaultID string
	var importedMigrationID sql.NullString
	var activeEntitlements int
	if err := rehearsal.database.QueryRow(`
		SELECT identity.account_id, vault.id
		FROM external_identities AS identity
		JOIN vaults AS vault ON vault.owner_account_id = identity.account_id
		WHERE identity.provider = 'apple' AND identity.subject = 'legacy-apple-subject'
	`).Scan(&accountID, &vaultID); err != nil {
		t.Fatalf("read Apple account and Vault relationship: %v", err)
	}
	if accountID != rehearsalAccountID || vaultID != rehearsalVaultID {
		t.Fatalf("legacy relationship account=%s vault=%s", accountID, vaultID)
	}
	if err := rehearsal.database.QueryRow(`
		SELECT imported_by_migration_id
		FROM journal_entries
		WHERE id = $1 AND vault_id = $2
	`, rehearsalImportedEntryID, rehearsalVaultID).Scan(&importedMigrationID); err != nil {
		t.Fatalf("read imported journal provenance: %v", err)
	}
	if !importedMigrationID.Valid || importedMigrationID.String != rehearsalMigrationID {
		t.Fatalf("imported journal provenance = %v", importedMigrationID)
	}
	if err := rehearsal.database.QueryRow(`
		SELECT COUNT(*)
		FROM entitlements
		WHERE account_id = $1 AND state = 'active'
	`, rehearsalAccountID).Scan(&activeEntitlements); err != nil {
		t.Fatalf("count active legacy entitlements: %v", err)
	}
	if activeEntitlements != 1 {
		t.Fatalf("active legacy entitlement count = %d, want 1", activeEntitlements)
	}
}

func (rehearsal *accountUpgradeRehearsal) assertResolutionDefaults(t *testing.T) {
	t.Helper()
	var resolution string
	var resolvedEntryID sql.NullString
	if err := rehearsal.database.QueryRow(`
		SELECT resolution, resolved_entry_id
		FROM migration_entries
		WHERE migration_id = $1 AND source_entry_id = 'legacy-entry-1'
	`, rehearsalMigrationID).Scan(&resolution, &resolvedEntryID); err != nil {
		t.Fatalf("read migration resolution defaults: %v", err)
	}
	if resolution != "pending" || resolvedEntryID.Valid {
		t.Fatalf("migration resolution=%s resolved_entry_id=%v", resolution, resolvedEntryID)
	}
}

func (rehearsal *accountUpgradeRehearsal) assertUpgradeConstraints(t *testing.T) {
	t.Helper()
	var count int
	if err := rehearsal.database.QueryRow(`
		SELECT COUNT(*)
		FROM pg_constraint AS constraint_record
		JOIN pg_class AS relation ON relation.oid = constraint_record.conrelid
		JOIN pg_namespace AS namespace ON namespace.oid = relation.relnamespace
		WHERE namespace.nspname = $1
		  AND constraint_record.conname IN (
			'vaults_id_owner_account_id_key',
			'vault_migrations_id_vault_id_key',
			'account_bootstrap_jobs_vault_owner_fkey',
			'account_bootstrap_jobs_migration_vault_fkey',
			'migration_entries_resolution_check',
			'migration_entries_resolution_target_check'
		  )
	`, rehearsal.schemaName).Scan(&count); err != nil {
		t.Fatalf("count account upgrade constraints: %v", err)
	}
	if count != 6 {
		t.Fatalf("account upgrade constraint count = %d, want 6", count)
	}
}

func (rehearsal *accountUpgradeRehearsal) assertMigrationVersion(t *testing.T, expected int) {
	t.Helper()
	var version int
	var dirty bool
	if err := rehearsal.database.QueryRow("SELECT version, dirty FROM schema_migrations").Scan(&version, &dirty); err != nil {
		t.Fatalf("read account upgrade migration version: %v", err)
	}
	if version != expected || dirty {
		t.Fatalf("migration version=%d dirty=%t, want version=%d dirty=false", version, dirty, expected)
	}
}

func (rehearsal *accountUpgradeRehearsal) assertRelationExists(t *testing.T, relation string, expected bool) {
	t.Helper()
	var name sql.NullString
	if err := rehearsal.database.QueryRow("SELECT to_regclass($1)", relation).Scan(&name); err != nil {
		t.Fatalf("resolve relation %s: %v", relation, err)
	}
	if name.Valid != expected {
		t.Fatalf("relation %s exists=%t, want %t", relation, name.Valid, expected)
	}
}

func (rehearsal *accountUpgradeRehearsal) assertColumnExists(t *testing.T, table string, column string, expected bool) {
	t.Helper()
	var exists bool
	if err := rehearsal.database.QueryRow(`
		SELECT EXISTS (
			SELECT 1
			FROM information_schema.columns
			WHERE table_schema = $1 AND table_name = $2 AND column_name = $3
		)
	`, rehearsal.schemaName, table, column).Scan(&exists); err != nil {
		t.Fatalf("resolve column %s.%s: %v", table, column, err)
	}
	if exists != expected {
		t.Fatalf("column %s.%s exists=%t, want %t", table, column, exists, expected)
	}
}
