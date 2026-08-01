package database

import (
	"database/sql"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/jackc/pgx/v5/stdlib"
)

const (
	rehearsalAccountID          = "81000000-0000-4000-8000-000000000001"
	rehearsalVaultID            = "82000000-0000-4000-8000-000000000001"
	rehearsalMigrationID        = "83000000-0000-4000-8000-000000000001"
	rehearsalImportedEntryID    = "84000000-0000-4000-8000-000000000001"
	rehearsalLocalEntryID       = "84000000-0000-4000-8000-000000000002"
	rehearsalMigrationOperation = "85000000-0000-4000-8000-000000000001"
	rehearsalIntentID           = "86000000-0000-4000-8000-000000000001"
	rehearsalAppAccountToken    = "87000000-0000-4000-8000-000000000001"
)

type accountUpgradeRehearsal struct {
	database       *sql.DB
	databaseURL    string
	migrationsPath string
	schemaName     string
}

func openAccountUpgradeRehearsal(t *testing.T) *accountUpgradeRehearsal {
	t.Helper()
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		t.Skip("DATABASE_URL is required for account upgrade rehearsal")
	}

	schemaName := fmt.Sprintf("clovery_account_upgrade_%d_%d", os.Getpid(), time.Now().UnixNano())
	adminDatabase, err := sql.Open("pgx", databaseURL)
	if err != nil {
		t.Fatalf("open account upgrade admin database: %v", err)
	}
	t.Cleanup(func() { _ = adminDatabase.Close() })
	if _, err := adminDatabase.Exec("CREATE SCHEMA " + schemaName); err != nil {
		t.Fatalf("create account upgrade schema: %v", err)
	}
	t.Cleanup(func() { _, _ = adminDatabase.Exec("DROP SCHEMA IF EXISTS " + schemaName + " CASCADE") })

	schemaURL := withSearchPath(t, databaseURL, schemaName)
	rehearsal := &accountUpgradeRehearsal{
		databaseURL:    schemaURL,
		migrationsPath: migrationDirectory(t),
		schemaName:     schemaName,
	}
	rehearsal.migrateTo(t, 15)
	rehearsal.database, err = sql.Open("pgx", schemaURL)
	if err != nil {
		t.Fatalf("open account upgrade database: %v", err)
	}
	t.Cleanup(func() { _ = rehearsal.database.Close() })
	if err := rehearsal.database.Ping(); err != nil {
		t.Fatalf("ping account upgrade database: %v", err)
	}
	return rehearsal
}

func (rehearsal *accountUpgradeRehearsal) migrateTo(t *testing.T, version uint) {
	t.Helper()
	migrateTestSchemaToVersion(t, rehearsal.databaseURL, rehearsal.migrationsPath, version)
}

func migrateTestSchemaToVersion(t *testing.T, databaseURL string, migrationsPath string, version uint) {
	t.Helper()
	sourceURL := (&url.URL{Scheme: "file", Path: filepath.Clean(migrationsPath)}).String()
	runner, err := migrate.New(sourceURL, databaseURL)
	if err != nil {
		t.Fatalf("initialize account upgrade migration runner: %v", err)
	}
	defer func() {
		sourceErr, databaseErr := runner.Close()
		if sourceErr != nil {
			t.Errorf("close account upgrade migration source: %v", sourceErr)
		}
		if databaseErr != nil {
			t.Errorf("close account upgrade migration database: %v", databaseErr)
		}
	}()

	if err := runner.Migrate(version); err != nil && !errors.Is(err, migrate.ErrNoChange) {
		t.Fatalf("migrate account upgrade schema to %d: %v", version, err)
	}
}

func (rehearsal *accountUpgradeRehearsal) seedPreUpgradeData(t *testing.T) {
	t.Helper()
	statements := []string{
		`INSERT INTO clovery_accounts (id) VALUES ('` + rehearsalAccountID + `')`,
		`INSERT INTO account_login_ids (account_id, normalized_id, status)
		 VALUES ('` + rehearsalAccountID + `', 'legacy_owner', 'active')`,
		`INSERT INTO password_credentials (account_id, password_hash)
		 VALUES ('` + rehearsalAccountID + `', '$argon2id$rehearsal')`,
		`INSERT INTO vaults (id, owner_account_id, status)
		 VALUES ('` + rehearsalVaultID + `', '` + rehearsalAccountID + `', 'active')`,
		`INSERT INTO external_identities (account_id, provider, issuer, subject)
		 VALUES ('` + rehearsalAccountID + `', 'apple', 'https://appleid.apple.com', 'legacy-apple-subject')`,
		`INSERT INTO federation_intents (id, purpose, provider, nonce_hash, expires_at)
		 VALUES ('` + rehearsalIntentID + `', 'login', 'apple', decode(repeat('11', 32), 'hex'), NOW() + INTERVAL '10 minutes')`,
		`INSERT INTO vault_migrations (
			id, vault_id, format_version, source,
			expected_entry_count, expected_deleted_count, expected_asset_count, expected_total_bytes,
			manifest_sha256, manifest, manifest_bytes, status, created_at
		 ) VALUES (
			'` + rehearsalMigrationID + `', '` + rehearsalVaultID + `', 1, 'v1_bundle',
			1, 0, 0, 128, repeat('a', 64), '{}'::jsonb, decode('00', 'hex'), 'verified', NOW()
		 )`,
		`INSERT INTO migration_entries (
			migration_id, entry_id, operation_id, payload, deleted_at, sha256, byte_size, source_entry_id
		 ) VALUES (
			'` + rehearsalMigrationID + `', '` + rehearsalImportedEntryID + `', '` + rehearsalMigrationOperation + `',
			'{"text":"legacy import"}'::jsonb, NULL, repeat('b', 64), 128, 'legacy-entry-1'
		 )`,
		`INSERT INTO journal_entries (id, vault_id, revision, payload, deleted_at, updated_at, imported_by_migration_id)
		 VALUES
			('` + rehearsalImportedEntryID + `', '` + rehearsalVaultID + `', 1, '{"text":"legacy import"}'::jsonb, NULL, NOW(), '` + rehearsalMigrationID + `'),
			('` + rehearsalLocalEntryID + `', '` + rehearsalVaultID + `', 3, '{"text":"local entry"}'::jsonb, NULL, NOW(), NULL)`,
		`INSERT INTO store_purchase_chains (storefront, original_transaction_id, account_id)
		 VALUES
			('apple', 'legacy-chain-active', '` + rehearsalAccountID + `'),
			('apple', 'legacy-chain-revoked', '` + rehearsalAccountID + `')`,
		`INSERT INTO store_transactions (
			storefront, transaction_id, account_id, original_transaction_id, product_id,
			environment, purchase_at, revoked_at, app_account_token, verification_metadata, status
		 ) VALUES
			('apple', 'legacy-tx-active', '` + rehearsalAccountID + `', 'legacy-chain-active',
			 'com.clovery.app.board.lifetime', 'production', NOW() - INTERVAL '30 days', NULL,
			 '` + rehearsalAppAccountToken + `', '{"source":"rehearsal"}'::jsonb, 'active'),
			('apple', 'legacy-tx-revoked', '` + rehearsalAccountID + `', 'legacy-chain-revoked',
			 'com.clovery.app.board.revoked-fixture', 'production', NOW() - INTERVAL '60 days', NOW() - INTERVAL '5 days',
			 '` + rehearsalAppAccountToken + `', '{"source":"rehearsal"}'::jsonb, 'revoked')`,
		`INSERT INTO entitlements (
			account_id, product_id, state, revoked_at, source_storefront, source_transaction_id, source_purchase_at
		 ) VALUES
			('` + rehearsalAccountID + `', 'com.clovery.app.board.lifetime', 'active', NULL,
			 'apple', 'legacy-tx-active', NOW() - INTERVAL '30 days'),
			('` + rehearsalAccountID + `', 'com.clovery.app.board.revoked-fixture', 'revoked', NOW() - INTERVAL '5 days',
			 'apple', 'legacy-tx-revoked', NOW() - INTERVAL '60 days')`,
	}
	for index, statement := range statements {
		if _, err := rehearsal.database.Exec(statement); err != nil {
			t.Fatalf("seed account upgrade statement %d: %v", index+1, err)
		}
	}
}

func (rehearsal *accountUpgradeRehearsal) applyAccountUpgrade(t *testing.T) {
	t.Helper()
	rehearsal.migrateTo(t, 17)
}

func (rehearsal *accountUpgradeRehearsal) rollbackAccountUpgrade(t *testing.T) {
	t.Helper()
	rehearsal.migrateTo(t, 15)
}

func (rehearsal *accountUpgradeRehearsal) reapplyAccountUpgrade(t *testing.T) {
	t.Helper()
	rehearsal.migrateTo(t, 17)
	rehearsal.migrateTo(t, 17)
}
