package migration

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"testing"
	"time"
)

func TestPostgresServiceImportsLegacySourceIDIdempotently(t *testing.T) {
	databaseHandle := openMigrationIntegrationDatabase(t)
	const accountID = "11111111-1111-4111-8111-111111111111"
	const vaultID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
	const migrationID = "22222222-2222-4222-8222-222222222222"
	const sourceEntryID = "new-1720000000000"
	payload := json.RawMessage(`{"id":"new-1720000000000","text":"journal"}`)
	payloadDigest := sha256.Sum256(payload)
	entriesFile := append(append([]byte{'['}, payload...), ']')
	entriesFileDigest := sha256.Sum256(entriesFile)
	deletedIDsFileDigest := sha256.Sum256([]byte(`[]`))
	manifestBytes, err := json.Marshal(bundleManifest{
		FormatVersion: 1,
		ExportedAt:    time.Now().UTC().Format(time.RFC3339Nano),
		EntriesFile:   "entries.json",
		EntriesSHA256: hex.EncodeToString(entriesFileDigest[:]),
		EntryCount:    1,
		Entries: []bundleManifestEntry{
			{EntryID: sourceEntryID, SHA256: hex.EncodeToString(payloadDigest[:]), Bytes: int64(len(payload))},
		},
		DeletedIDsFile:   "deleted_ids.json",
		DeletedIDsSHA256: hex.EncodeToString(deletedIDsFileDigest[:]),
		DeletedIDs:       []string{},
		Photos:           []bundleManifestPhoto{},
		Sources:          []string{"localStorage"},
	})
	if err != nil {
		t.Fatalf("encode migration manifest: %v", err)
	}
	manifestDigest := sha256.Sum256(manifestBytes)
	seedMigrationOwner(t, databaseHandle, accountID, vaultID)
	repository := NewPostgresRepository(databaseHandle)
	service, err := NewService(&stubMigrationVaults{}, repository)
	if err != nil {
		t.Fatalf("create migration service: %v", err)
	}
	if _, err := service.Create(context.Background(), accountID, vaultID, CreateRequest{
		MigrationID: migrationID, FormatVersion: 1, Source: "v1_bundle",
		EntryCount: 1, TotalBytes: int64(len(payload)),
		ManifestSHA256: hex.EncodeToString(manifestDigest[:]),
		ManifestBase64: base64.StdEncoding.EncodeToString(manifestBytes),
	}); err != nil {
		t.Fatalf("Create() error = %v", err)
	}
	input := EntryInput{
		EntryID: sourceEntryID, Payload: payload, SHA256: hex.EncodeToString(payloadDigest[:]),
	}
	if err := service.AddEntry(context.Background(), accountID, vaultID, migrationID, input); err != nil {
		t.Fatalf("first AddEntry() error = %v", err)
	}
	if err := service.AddEntry(context.Background(), accountID, vaultID, migrationID, input); err != nil {
		t.Fatalf("idempotent AddEntry() error = %v", err)
	}

	var internalEntryID, storedSourceID string
	if err := databaseHandle.QueryRow(
		"SELECT entry_id, source_entry_id FROM migration_entries WHERE migration_id = $1",
		migrationID,
	).Scan(&internalEntryID, &storedSourceID); err != nil {
		t.Fatalf("load staged legacy entry: %v", err)
	}
	if internalEntryID == sourceEntryID || storedSourceID != sourceEntryID {
		t.Fatalf("entry_id = %q, source_entry_id = %q", internalEntryID, storedSourceID)
	}
	if _, err := service.Verify(context.Background(), accountID, vaultID, migrationID); err != nil {
		t.Fatalf("Verify() error = %v", err)
	}
	var importedID string
	if err := databaseHandle.QueryRow(
		"SELECT id FROM journal_entries WHERE vault_id = $1 AND imported_by_migration_id = $2",
		vaultID, migrationID,
	).Scan(&importedID); err != nil || importedID != internalEntryID {
		t.Fatalf("imported ID = %q, error = %v", importedID, err)
	}
}

func TestPostgresServiceImportsManifestBoundDeletedLegacyID(t *testing.T) {
	databaseHandle := openMigrationIntegrationDatabase(t)
	const accountID = "11111111-1111-4111-8111-111111111111"
	const vaultID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
	const migrationID = "22222222-2222-4222-8222-222222222222"
	const sourceEntryID = "new-1710000000000"
	entriesFileDigest := sha256.Sum256([]byte("[]"))
	deletedIDsFile := []byte("[\"new-1710000000000\"]")
	deletedIDsFileDigest := sha256.Sum256(deletedIDsFile)
	manifestBytes, err := json.Marshal(bundleManifest{
		FormatVersion:    1,
		ExportedAt:       time.Now().UTC().Format(time.RFC3339Nano),
		EntriesFile:      "entries.json",
		EntriesSHA256:    hex.EncodeToString(entriesFileDigest[:]),
		Entries:          []bundleManifestEntry{},
		DeletedIDsFile:   "deleted_ids.json",
		DeletedIDsSHA256: hex.EncodeToString(deletedIDsFileDigest[:]),
		DeletedCount:     1,
		DeletedIDs:       []string{sourceEntryID},
		Photos:           []bundleManifestPhoto{},
		Sources:          []string{"localStorage"},
	})
	if err != nil {
		t.Fatalf("encode deleted-entry manifest: %v", err)
	}
	manifestDigest := sha256.Sum256(manifestBytes)
	seedMigrationOwner(t, databaseHandle, accountID, vaultID)
	service, err := NewService(&stubMigrationVaults{}, NewPostgresRepository(databaseHandle))
	if err != nil {
		t.Fatalf("create migration service: %v", err)
	}
	if _, err := service.Create(context.Background(), accountID, vaultID, CreateRequest{
		MigrationID: migrationID, FormatVersion: 1, Source: "v1_bundle", TotalBytes: 2,
		ManifestSHA256: hex.EncodeToString(manifestDigest[:]),
		ManifestBase64: base64.StdEncoding.EncodeToString(manifestBytes),
	}); err != nil {
		t.Fatalf("Create() error = %v", err)
	}
	deletedAt := time.Now().UTC()
	emptyPayload := json.RawMessage("{}")
	emptyPayloadDigest := sha256.Sum256(emptyPayload)
	if err := service.AddEntry(
		context.Background(), accountID, vaultID, migrationID,
		EntryInput{
			EntryID: sourceEntryID, Payload: emptyPayload, DeletedAt: &deletedAt,
			SHA256: hex.EncodeToString(emptyPayloadDigest[:]),
		},
	); err != nil {
		t.Fatalf("AddEntry() error = %v", err)
	}
	if _, err := service.Verify(context.Background(), accountID, vaultID, migrationID); err != nil {
		t.Fatalf("Verify() error = %v", err)
	}
	var storedDeletedAt *time.Time
	if err := databaseHandle.QueryRow(
		"SELECT deleted_at FROM journal_entries WHERE vault_id = $1 AND imported_by_migration_id = $2",
		vaultID, migrationID,
	).Scan(&storedDeletedAt); err != nil || storedDeletedAt == nil {
		t.Fatalf("deleted_at = %v, error = %v", storedDeletedAt, err)
	}
}

func seedMigrationOwner(t *testing.T, databaseHandle *sql.DB, accountID string, vaultID string) {
	t.Helper()
	if _, err := databaseHandle.Exec("INSERT INTO clovery_accounts (id) VALUES ($1)", accountID); err != nil {
		t.Fatalf("seed migration account: %v", err)
	}
	if _, err := databaseHandle.Exec(
		"INSERT INTO vaults (id, owner_account_id, status) VALUES ($1, $2, 'active')", vaultID, accountID,
	); err != nil {
		t.Fatalf("seed migration Vault: %v", err)
	}
}
