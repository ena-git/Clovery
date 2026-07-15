package migration

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"testing"
	"time"

	cloverydatabase "github.com/clovery/clovery/services/api/internal/database"
	_ "github.com/jackc/pgx/v5/stdlib"
)

func TestPostgresUploadAndVerifyRaceRemainsRecoverable(t *testing.T) {
	databaseHandle := openMigrationIntegrationDatabase(t)
	const accountID = "11111111-1111-4111-8111-111111111111"
	const vaultID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
	const migrationID = "22222222-2222-4222-8222-222222222222"
	const entryID = "33333333-3333-4333-8333-333333333333"
	entryPayload := json.RawMessage(`{}`)
	entryDigest := sha256.Sum256(entryPayload)
	manifest := []byte(fmt.Sprintf(
		`{"entries":[{"entry_id":%q,"sha256":%q,"bytes":2}],"deleted_ids":[]}`,
		entryID, hex.EncodeToString(entryDigest[:]),
	))
	manifestDigest := sha256.Sum256(manifest)
	if _, err := databaseHandle.Exec("INSERT INTO clovery_accounts (id) VALUES ($1)", accountID); err != nil {
		t.Fatalf("seed migration account: %v", err)
	}
	if _, err := databaseHandle.Exec(
		"INSERT INTO vaults (id, owner_account_id, status) VALUES ($1, $2, 'active')", vaultID, accountID,
	); err != nil {
		t.Fatalf("seed migration Vault: %v", err)
	}
	if _, err := databaseHandle.Exec(`INSERT INTO vault_migrations (
			id, vault_id, format_version, source, expected_entry_count, expected_deleted_count,
			expected_asset_count, expected_total_bytes, manifest_sha256, manifest, manifest_bytes,
			status, created_at
		) VALUES ($1, $2, 1, 'v1_bundle', 1, 0, 0, 2, $3, $4::jsonb, $5, 'uploading', $6)`,
		migrationID, vaultID, hex.EncodeToString(manifestDigest[:]),
		string(manifest), manifest, time.Now().UTC(),
	); err != nil {
		t.Fatalf("seed migration race: %v", err)
	}
	repository := NewPostgresRepository(databaseHandle)
	start := make(chan struct{})
	var waitGroup sync.WaitGroup
	waitGroup.Add(2)
	var addErr, verifyErr error
	go func() {
		defer waitGroup.Done()
		<-start
		addErr = repository.AddEntry(context.Background(), vaultID, migrationID, EntryInput{
			EntryID: entryID, SourceEntryID: entryID, Payload: entryPayload,
			SHA256: hex.EncodeToString(entryDigest[:]),
		})
	}()
	go func() {
		defer waitGroup.Done()
		<-start
		_, verifyErr = repository.Verify(context.Background(), vaultID, migrationID)
	}()
	close(start)
	waitGroup.Wait()
	if addErr != nil {
		t.Fatalf("concurrent AddEntry() error = %v", addErr)
	}
	if verifyErr != nil && !errors.Is(verifyErr, ErrVerificationFailed) {
		t.Fatalf("concurrent Verify() error = %v", verifyErr)
	}
	if _, err := repository.Verify(context.Background(), vaultID, migrationID); err != nil {
		t.Fatalf("final Verify() error = %v", err)
	}
	var imported int
	if err := databaseHandle.QueryRow(
		"SELECT COUNT(*) FROM journal_entries WHERE vault_id = $1 AND imported_by_migration_id = $2",
		vaultID, migrationID,
	).Scan(&imported); err != nil || imported != 1 {
		t.Fatalf("imported entries = %d, error = %v", imported, err)
	}
}

func TestPostgresAddEntryRejectsContentOutsideManifest(t *testing.T) {
	databaseHandle := openMigrationIntegrationDatabase(t)
	const accountID = "11111111-1111-4111-8111-111111111111"
	const vaultID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
	const migrationID = "22222222-2222-4222-8222-222222222222"
	const entryID = "33333333-3333-4333-8333-333333333333"
	expectedPayload := json.RawMessage(`{"text":"original"}`)
	expectedDigest := sha256.Sum256(expectedPayload)
	manifest := []byte(fmt.Sprintf(
		`{"entries":[{"entry_id":%q,"sha256":%q,"bytes":%d}],"deleted_ids":[]}`,
		entryID, hex.EncodeToString(expectedDigest[:]), len(expectedPayload),
	))
	manifestDigest := sha256.Sum256(manifest)
	if _, err := databaseHandle.Exec("INSERT INTO clovery_accounts (id) VALUES ($1)", accountID); err != nil {
		t.Fatalf("seed migration account: %v", err)
	}
	if _, err := databaseHandle.Exec(
		"INSERT INTO vaults (id, owner_account_id, status) VALUES ($1, $2, 'active')", vaultID, accountID,
	); err != nil {
		t.Fatalf("seed migration Vault: %v", err)
	}
	if _, err := databaseHandle.Exec(`INSERT INTO vault_migrations (
			id, vault_id, format_version, source, expected_entry_count, expected_deleted_count,
			expected_asset_count, expected_total_bytes, manifest_sha256, manifest, manifest_bytes,
			status, created_at
		) VALUES ($1, $2, 1, 'v1_bundle', 1, 0, 0, $3, $4, $5::jsonb, $6, 'uploading', $7)`,
		migrationID, vaultID, len(expectedPayload), hex.EncodeToString(manifestDigest[:]),
		string(manifest), manifest, time.Now().UTC(),
	); err != nil {
		t.Fatalf("seed manifest-bound migration: %v", err)
	}

	tamperedPayload := json.RawMessage(`{"text":"tampered"}`)
	tamperedDigest := sha256.Sum256(tamperedPayload)
	err := NewPostgresRepository(databaseHandle).AddEntry(
		context.Background(), vaultID, migrationID,
		EntryInput{
			EntryID: entryID, SourceEntryID: entryID, Payload: tamperedPayload,
			SHA256: hex.EncodeToString(tamperedDigest[:]),
		},
	)
	if !errors.Is(err, ErrMigrationMismatch) {
		t.Fatalf("AddEntry() error = %v", err)
	}
}

func openMigrationIntegrationDatabase(t *testing.T) *sql.DB {
	t.Helper()
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		t.Skip("DATABASE_URL is required for migration integration tests")
	}
	const schemaName = "clovery_migration_concurrency_test"
	admin, err := sql.Open("pgx", databaseURL)
	if err != nil {
		t.Fatalf("open migration integration database: %v", err)
	}
	t.Cleanup(func() { _ = admin.Close() })
	_, _ = admin.Exec(fmt.Sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schemaName))
	if _, err := admin.Exec(fmt.Sprintf("CREATE SCHEMA %s", schemaName)); err != nil {
		t.Fatalf("create migration integration schema: %v", err)
	}
	t.Cleanup(func() { _, _ = admin.Exec(fmt.Sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schemaName)) })

	schemaURL := migrationIntegrationDatabaseURL(t, databaseURL, schemaName)
	if err := cloverydatabase.Apply(schemaURL, migrationMigrationsPath(t), cloverydatabase.Up); err != nil {
		t.Fatalf("apply migration integration migrations: %v", err)
	}
	databaseHandle, err := sql.Open("pgx", schemaURL)
	if err != nil {
		t.Fatalf("open migrated migration database: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	return databaseHandle
}

func migrationIntegrationDatabaseURL(t *testing.T, databaseURL string, schemaName string) string {
	t.Helper()
	parsed, err := url.Parse(databaseURL)
	if err != nil {
		t.Fatalf("parse migration integration database URL: %v", err)
	}
	query := parsed.Query()
	query.Set("search_path", schemaName)
	parsed.RawQuery = query.Encode()
	return parsed.String()
}

func migrationMigrationsPath(t *testing.T) string {
	t.Helper()
	_, currentFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("resolve migration integration test path")
	}
	return filepath.Join(filepath.Dir(currentFile), "..", "..", "migrations")
}
