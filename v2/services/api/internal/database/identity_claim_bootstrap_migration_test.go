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
				"login_intent_id UUID NOT NULL UNIQUE",
				"CREATE TABLE account_bootstrap_jobs",
				"account_id UUID PRIMARY KEY",
				"vault_id UUID NOT NULL UNIQUE",
				"CREATE INDEX identity_claims_expires_at_idx",
			},
		},
		{
			name:      "rollback",
			migration: "000016_identity_claim_bootstrap.down.sql",
			fragments: []string{
				"DROP TABLE IF EXISTS account_bootstrap_jobs;",
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
}
