package database

import (
	"database/sql"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"
)

const (
	bootstrapAccountA   = "10000000-0000-4000-8000-000000000001"
	bootstrapAccountB   = "10000000-0000-4000-8000-000000000002"
	bootstrapVaultA     = "20000000-0000-4000-8000-000000000001"
	bootstrapVaultB     = "20000000-0000-4000-8000-000000000002"
	bootstrapMigrationA = "30000000-0000-4000-8000-000000000001"
	bootstrapMigrationB = "30000000-0000-4000-8000-000000000002"
)

func TestIdentityClaimBootstrapMigrationEnforcesDatabaseContract(t *testing.T) {
	database, schemaURL, schemaName := openIdentityClaimBootstrapDatabase(t)
	seedIdentityClaimBootstrapOwners(t, database)

	t.Run("rejects malformed identity claim digests", func(t *testing.T) {
		tests := []struct {
			name     string
			claimID  string
			intentID string
			digest   string
		}{
			{
				name:     "short",
				claimID:  "40000000-0000-4000-8000-000000000001",
				intentID: "50000000-0000-4000-8000-000000000001",
				digest:   strings.Repeat("a", 63),
			},
			{
				name:     "uppercase",
				claimID:  "40000000-0000-4000-8000-000000000002",
				intentID: "50000000-0000-4000-8000-000000000002",
				digest:   strings.Repeat("A", 64),
			},
			{
				name:     "non_hex",
				claimID:  "40000000-0000-4000-8000-000000000003",
				intentID: "50000000-0000-4000-8000-000000000003",
				digest:   strings.Repeat("a", 63) + "g",
			},
		}
		for _, test := range tests {
			t.Run(test.name, func(t *testing.T) {
				insertFederationIntent(t, database, test.intentID)
				expectDatabaseRejection(t, database, `
					INSERT INTO identity_claims (
						id, token_sha256, provider, issuer, subject, login_intent_id, expires_at
					) VALUES ($1, $2, 'apple', 'https://appleid.apple.com', $3, $4, NOW() + INTERVAL '10 minutes')
				`, test.claimID, test.digest, test.claimID, test.intentID)
			})
		}
	})

	t.Run("rejects cross-account vault pairing", func(t *testing.T) {
		expectDatabaseRejection(t, database, `
			INSERT INTO account_bootstrap_jobs (account_id, vault_id, source_kind)
			VALUES ($1, $2, 'new_install')
		`, bootstrapAccountA, bootstrapVaultB)
	})

	t.Run("rejects migration from another vault", func(t *testing.T) {
		expectDatabaseRejection(t, database, `
			INSERT INTO account_bootstrap_jobs (account_id, vault_id, source_kind, migration_id)
			VALUES ($1, $2, 'legacy_local', $3)
		`, bootstrapAccountA, bootstrapVaultA, bootstrapMigrationB)
	})

	t.Run("rejects complete status with pending stages", func(t *testing.T) {
		expectDatabaseRejection(t, database, `
			INSERT INTO account_bootstrap_jobs (account_id, vault_id, source_kind, status)
			VALUES ($1, $2, 'new_install', 'complete')
		`, bootstrapAccountA, bootstrapVaultA)
	})

	t.Run("rejects inconsistent needs-attention state", func(t *testing.T) {
		tests := []struct {
			name  string
			query string
		}{
			{
				name: "without attention stage",
				query: `
					INSERT INTO account_bootstrap_jobs (
						account_id, vault_id, source_kind, status, last_error_code
					) VALUES ($1, $2, 'legacy_local', 'needs_attention', 'migration_failed')
				`,
			},
			{
				name: "without error code",
				query: `
					INSERT INTO account_bootstrap_jobs (
						account_id, vault_id, source_kind, migration_state, status
					) VALUES ($1, $2, 'legacy_local', 'needs_attention', 'needs_attention')
				`,
			},
			{
				name: "with unstable error code",
				query: `
					INSERT INTO account_bootstrap_jobs (
						account_id, vault_id, source_kind, migration_state, status, last_error_code
					) VALUES ($1, $2, 'legacy_local', 'needs_attention', 'needs_attention', 'Migration-Failed')
				`,
			},
			{
				name: "attention stage under running status",
				query: `
					INSERT INTO account_bootstrap_jobs (
						account_id, vault_id, source_kind, migration_state, status, last_error_code
					) VALUES ($1, $2, 'legacy_local', 'needs_attention', 'running', 'migration_failed')
				`,
			},
		}
		for _, test := range tests {
			t.Run(test.name, func(t *testing.T) {
				expectDatabaseRejection(t, database, test.query, bootstrapAccountA, bootstrapVaultA)
			})
		}
	})

	t.Run("migration deletion preserves vault ownership", func(t *testing.T) {
		if _, err := database.Exec(`
			INSERT INTO account_bootstrap_jobs (account_id, vault_id, source_kind, migration_id, status)
			VALUES ($1, $2, 'legacy_local', $3, 'running')
		`, bootstrapAccountA, bootstrapVaultA, bootstrapMigrationA); err != nil {
			t.Fatalf("insert valid bootstrap job: %v", err)
		}
		if _, err := database.Exec("DELETE FROM vault_migrations WHERE id = $1", bootstrapMigrationA); err != nil {
			t.Fatalf("delete bootstrap migration: %v", err)
		}
		var migrationID sql.NullString
		var vaultID string
		if err := database.QueryRow(`
			SELECT migration_id, vault_id FROM account_bootstrap_jobs WHERE account_id = $1
		`, bootstrapAccountA).Scan(&migrationID, &vaultID); err != nil {
			t.Fatalf("read bootstrap job after migration deletion: %v", err)
		}
		if migrationID.Valid || vaultID != bootstrapVaultA {
			t.Fatalf("migration deletion left migration=%v vault=%s", migrationID, vaultID)
		}
	})

	t.Run("rollback removes migration 16 objects and supports reapply", func(t *testing.T) {
		migrations := migrationDirectory(t)
		if err := Apply(schemaURL, migrations, Down); err != nil {
			t.Fatalf("roll back identity bootstrap migration: %v", err)
		}
		assertIdentityBootstrapTables(t, database, false)
		assertSupportingConstraintCount(t, database, schemaName, 0)

		if err := Apply(schemaURL, migrations, Up); err != nil {
			t.Fatalf("reapply identity bootstrap migration: %v", err)
		}
		assertIdentityBootstrapTables(t, database, true)
		assertSupportingConstraintCount(t, database, schemaName, 2)
	})
}

func openIdentityClaimBootstrapDatabase(t *testing.T) (*sql.DB, string, string) {
	t.Helper()
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		t.Skip("DATABASE_URL is required for identity claim bootstrap integration tests")
	}

	schemaName := fmt.Sprintf("clovery_identity_bootstrap_%d_%d", os.Getpid(), time.Now().UnixNano())
	adminDatabase, err := sql.Open("pgx", databaseURL)
	if err != nil {
		t.Fatalf("open identity bootstrap admin database: %v", err)
	}
	t.Cleanup(func() { _ = adminDatabase.Close() })
	if _, err := adminDatabase.Exec("CREATE SCHEMA " + schemaName); err != nil {
		t.Fatalf("create identity bootstrap schema: %v", err)
	}
	t.Cleanup(func() { _, _ = adminDatabase.Exec("DROP SCHEMA IF EXISTS " + schemaName + " CASCADE") })

	schemaURL := withSearchPath(t, databaseURL, schemaName)
	if err := Apply(schemaURL, migrationDirectory(t), Up); err != nil {
		t.Fatalf("apply identity bootstrap migrations: %v", err)
	}
	database, err := sql.Open("pgx", schemaURL)
	if err != nil {
		t.Fatalf("open identity bootstrap database: %v", err)
	}
	t.Cleanup(func() { _ = database.Close() })
	if err := database.Ping(); err != nil {
		t.Fatalf("ping identity bootstrap database: %v", err)
	}
	return database, schemaURL, schemaName
}

func seedIdentityClaimBootstrapOwners(t *testing.T, database *sql.DB) {
	t.Helper()
	if _, err := database.Exec(`
		INSERT INTO clovery_accounts (id) VALUES ($1), ($2)
	`, bootstrapAccountA, bootstrapAccountB); err != nil {
		t.Fatalf("insert bootstrap accounts: %v", err)
	}
	if _, err := database.Exec(`
		INSERT INTO vaults (id, owner_account_id, status) VALUES
			($1, $2, 'active'),
			($3, $4, 'active')
	`, bootstrapVaultA, bootstrapAccountA, bootstrapVaultB, bootstrapAccountB); err != nil {
		t.Fatalf("insert bootstrap vaults: %v", err)
	}
	if _, err := database.Exec(`
		INSERT INTO vault_migrations (
			id, vault_id, format_version, source,
			expected_entry_count, expected_deleted_count, expected_asset_count, expected_total_bytes,
			manifest_sha256, manifest, manifest_bytes, status, created_at
		) VALUES
			($1, $2, 1, 'v1_bundle', 0, 0, 0, 0, $5, '{}'::jsonb, decode('00', 'hex'), 'uploading', NOW()),
			($3, $4, 1, 'v1_bundle', 0, 0, 0, 0, $5, '{}'::jsonb, decode('00', 'hex'), 'uploading', NOW())
	`, bootstrapMigrationA, bootstrapVaultA, bootstrapMigrationB, bootstrapVaultB, strings.Repeat("a", 64)); err != nil {
		t.Fatalf("insert bootstrap migrations: %v", err)
	}
}

func insertFederationIntent(t *testing.T, database *sql.DB, intentID string) {
	t.Helper()
	if _, err := database.Exec(`
		INSERT INTO federation_intents (id, purpose, provider, nonce_hash, expires_at)
		VALUES ($1, 'login', 'apple', decode(repeat('00', 32), 'hex'), NOW() + INTERVAL '10 minutes')
	`, intentID); err != nil {
		t.Fatalf("insert federation intent: %v", err)
	}
}

func expectDatabaseRejection(t *testing.T, database *sql.DB, query string, arguments ...any) {
	t.Helper()
	if _, err := database.Exec(query, arguments...); err == nil {
		t.Fatal("database accepted invalid identity bootstrap state")
	}
}

func assertIdentityBootstrapTables(t *testing.T, database *sql.DB, expected bool) {
	t.Helper()
	for _, table := range []string{"identity_claims", "account_bootstrap_jobs"} {
		var relation sql.NullString
		if err := database.QueryRow("SELECT to_regclass($1)", table).Scan(&relation); err != nil {
			t.Fatalf("resolve table %s: %v", table, err)
		}
		if relation.Valid != expected {
			t.Fatalf("table %s existence = %t, want %t", table, relation.Valid, expected)
		}
	}
}

func assertSupportingConstraintCount(t *testing.T, database *sql.DB, schemaName string, expected int) {
	t.Helper()
	var count int
	if err := database.QueryRow(`
		SELECT COUNT(*)
		FROM pg_constraint AS constraint_record
		JOIN pg_class AS relation ON relation.oid = constraint_record.conrelid
		JOIN pg_namespace AS namespace ON namespace.oid = relation.relnamespace
		WHERE namespace.nspname = $1
		  AND constraint_record.conname IN (
			'vaults_id_owner_account_id_key',
			'vault_migrations_id_vault_id_key'
		  )
	`, schemaName).Scan(&count); err != nil {
		t.Fatalf("count identity bootstrap supporting constraints: %v", err)
	}
	if count != expected {
		t.Fatalf("supporting constraint count = %d, want %d", count, expected)
	}
}
