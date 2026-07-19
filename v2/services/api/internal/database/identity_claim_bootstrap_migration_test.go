package database

import (
	"path/filepath"
	"strings"
	"testing"
)

func TestIdentityClaimBootstrapMigrationDefinesPersistenceContract(t *testing.T) {
	migrations := migrationDirectory(t)

	tests := []struct {
		name      string
		migration string
		fragments []string
	}{
		{
			name:      "forward",
			migration: "000016_identity_claim_bootstrap.up.sql",
			fragments: []string{
				"CREATE TABLE identity_claims",
				"token_sha256 CHAR(64) NOT NULL UNIQUE",
				"CONSTRAINT identity_claims_token_sha256_format_check",
				"CHECK (token_sha256 ~ '^[a-f0-9]{64}$')",
				"login_intent_id UUID NOT NULL UNIQUE",
				"CONSTRAINT vaults_id_owner_account_id_key UNIQUE (id, owner_account_id)",
				"CONSTRAINT vault_migrations_id_vault_id_key UNIQUE (id, vault_id)",
				"CREATE TABLE account_bootstrap_jobs",
				"account_id UUID PRIMARY KEY",
				"vault_id UUID NOT NULL UNIQUE",
				"CONSTRAINT account_bootstrap_jobs_vault_owner_fkey",
				"FOREIGN KEY (vault_id, account_id)",
				"REFERENCES vaults(id, owner_account_id)",
				"CONSTRAINT account_bootstrap_jobs_migration_vault_fkey",
				"FOREIGN KEY (migration_id, vault_id)",
				"REFERENCES vault_migrations(id, vault_id)",
				"ON DELETE SET NULL (migration_id)",
				"CONSTRAINT account_bootstrap_jobs_complete_state_check",
				"CONSTRAINT account_bootstrap_jobs_attention_state_check",
				"CONSTRAINT account_bootstrap_jobs_attention_error_check",
				"CREATE INDEX identity_claims_expires_at_idx",
			},
		},
		{
			name:      "rollback",
			migration: "000016_identity_claim_bootstrap.down.sql",
			fragments: []string{
				"DROP TABLE IF EXISTS account_bootstrap_jobs;",
				"ALTER TABLE vault_migrations DROP CONSTRAINT IF EXISTS vault_migrations_id_vault_id_key;",
				"ALTER TABLE vaults DROP CONSTRAINT IF EXISTS vaults_id_owner_account_id_key;",
				"DROP TABLE IF EXISTS identity_claims;",
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			migration := readMigration(t, filepath.Join(migrations, test.migration))
			for _, fragment := range test.fragments {
				if !strings.Contains(migration, fragment) {
					t.Errorf("migration is missing %q", fragment)
				}
			}
		})
	}

	down := readMigration(t, filepath.Join(migrations, "000016_identity_claim_bootstrap.down.sql"))
	rollbackOrder := []string{
		"DROP TABLE IF EXISTS account_bootstrap_jobs;",
		"ALTER TABLE vault_migrations DROP CONSTRAINT IF EXISTS vault_migrations_id_vault_id_key;",
		"ALTER TABLE vaults DROP CONSTRAINT IF EXISTS vaults_id_owner_account_id_key;",
		"DROP TABLE IF EXISTS identity_claims;",
	}
	previousPosition := -1
	for _, fragment := range rollbackOrder {
		position := strings.Index(down, fragment)
		if position <= previousPosition {
			t.Fatalf("rollback fragment %q is out of order", fragment)
		}
		previousPosition = position
	}
}
