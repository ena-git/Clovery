package migration

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"sync"
	"testing"
	"time"
)

const (
	resolutionAccountID = "11111111-1111-4111-8111-111111111111"
	resolutionVaultID   = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
	resolutionMigration = "22222222-2222-4222-8222-222222222222"
	resolutionEntryA    = "33333333-3333-4333-8333-333333333333"
	resolutionEntryB    = "44444444-4444-4444-8444-444444444444"
)

func TestPostgresMigrationResolutionCases(t *testing.T) {
	tests := []struct {
		name            string
		existing        []resolutionTestEntry
		staged          []resolutionTestEntry
		wantJournalRows int
		wantSyncRows    int
		wantInserted    int
		wantDuplicates  int
		wantConflicts   int
	}{
		{
			name: "empty Vault import",
			staged: []resolutionTestEntry{
				{sourceID: resolutionEntryA, payload: `{"id":"` + resolutionEntryA + `","text":"first"}`},
			},
			wantJournalRows: 1,
			wantSyncRows:    1,
			wantInserted:    1,
		},
		{
			name: "same ID and content already in Vault",
			existing: []resolutionTestEntry{
				{sourceID: resolutionEntryA, payload: `{"id":"` + resolutionEntryA + `","text":"same"}`},
			},
			staged: []resolutionTestEntry{
				{sourceID: resolutionEntryA, payload: `{"text":"same","id":"` + resolutionEntryA + `"}`},
			},
			wantJournalRows: 1,
			wantDuplicates:  1,
		},
		{
			name: "different ID and same active content",
			existing: []resolutionTestEntry{
				{sourceID: resolutionEntryA, payload: `{"id":"` + resolutionEntryA + `","text":"same"}`},
			},
			staged: []resolutionTestEntry{
				{sourceID: resolutionEntryB, payload: `{"id":"` + resolutionEntryB + `","text":"same"}`},
			},
			wantJournalRows: 1,
			wantDuplicates:  1,
		},
		{
			name: "same ID and different content",
			existing: []resolutionTestEntry{
				{sourceID: resolutionEntryA, payload: `{"id":"` + resolutionEntryA + `","text":"old"}`},
			},
			staged: []resolutionTestEntry{
				{sourceID: resolutionEntryA, payload: `{"id":"` + resolutionEntryA + `","text":"new"}`},
			},
			wantJournalRows: 2,
			wantSyncRows:    1,
			wantInserted:    1,
			wantConflicts:   1,
		},
		{
			name: "two staged rows with same active content",
			staged: []resolutionTestEntry{
				{sourceID: resolutionEntryB, payload: `{"id":"` + resolutionEntryB + `","text":"same"}`},
				{sourceID: resolutionEntryA, payload: `{"id":"` + resolutionEntryA + `","text":"same"}`},
			},
			wantJournalRows: 1,
			wantSyncRows:    1,
			wantInserted:    1,
			wantDuplicates:  1,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			databaseHandle := openMigrationIntegrationDatabase(t)
			seedMigrationOwner(t, databaseHandle, resolutionAccountID, resolutionVaultID)
			seedExistingResolutionEntries(t, databaseHandle, test.existing)
			service := stageResolutionMigration(t, databaseHandle, test.staged)

			report, err := service.Verify(
				context.Background(), resolutionAccountID, resolutionVaultID, resolutionMigration,
			)
			if err != nil {
				t.Fatalf("Verify() error = %v", err)
			}
			if report.InsertedEntries != test.wantInserted ||
				report.DuplicateEntries != test.wantDuplicates ||
				report.ConflictCopies != test.wantConflicts {
				t.Fatalf("Verify() report = %#v", report)
			}
			assertResolutionDatabaseState(
				t, databaseHandle, len(test.staged), test.wantJournalRows, test.wantSyncRows,
			)

			secondReport, err := service.Verify(
				context.Background(), resolutionAccountID, resolutionVaultID, resolutionMigration,
			)
			if err != nil || secondReport.InsertedEntries != report.InsertedEntries ||
				secondReport.DuplicateEntries != report.DuplicateEntries ||
				secondReport.ConflictCopies != report.ConflictCopies {
				t.Fatalf("second Verify() report = %#v, error = %v", secondReport, err)
			}
			assertResolutionDatabaseState(
				t, databaseHandle, len(test.staged), test.wantJournalRows, test.wantSyncRows,
			)
		})
	}
}

func TestPostgresMigrationResolutionFailureWritesNoVaultRows(t *testing.T) {
	databaseHandle := openMigrationIntegrationDatabase(t)
	seedMigrationOwner(t, databaseHandle, resolutionAccountID, resolutionVaultID)
	service := stageResolutionMigration(t, databaseHandle, []resolutionTestEntry{
		{sourceID: resolutionEntryA, payload: `{"id":"` + resolutionEntryA + `","text":"safe"}`},
	})
	if _, err := databaseHandle.Exec(
		"UPDATE vault_migrations SET manifest_bytes = $2 WHERE id = $1",
		resolutionMigration, []byte(`{"tampered":true}`),
	); err != nil {
		t.Fatalf("tamper manifest: %v", err)
	}

	_, err := service.Verify(
		context.Background(), resolutionAccountID, resolutionVaultID, resolutionMigration,
	)
	if !errors.Is(err, ErrIntegrityMismatch) {
		t.Fatalf("Verify() error = %v", err)
	}
	assertResolutionDatabaseState(t, databaseHandle, 0, 0, 0)
}

func TestPostgresMigrationResolutionConcurrentVerifyCommitsOnce(t *testing.T) {
	databaseHandle := openMigrationIntegrationDatabase(t)
	seedMigrationOwner(t, databaseHandle, resolutionAccountID, resolutionVaultID)
	service := stageResolutionMigration(t, databaseHandle, []resolutionTestEntry{
		{sourceID: resolutionEntryA, payload: `{"id":"` + resolutionEntryA + `","text":"once"}`},
	})

	start := make(chan struct{})
	errorsFound := make(chan error, 2)
	var waitGroup sync.WaitGroup
	for range 2 {
		waitGroup.Add(1)
		go func() {
			defer waitGroup.Done()
			<-start
			_, err := service.Verify(
				context.Background(), resolutionAccountID, resolutionVaultID, resolutionMigration,
			)
			errorsFound <- err
		}()
	}
	close(start)
	waitGroup.Wait()
	close(errorsFound)
	for err := range errorsFound {
		if err != nil {
			t.Fatalf("concurrent Verify() error = %v", err)
		}
	}
	assertResolutionDatabaseState(t, databaseHandle, 1, 1, 1)
}

type resolutionTestEntry struct {
	sourceID string
	payload  string
}

func seedExistingResolutionEntries(
	t *testing.T,
	databaseHandle *sql.DB,
	entries []resolutionTestEntry,
) {
	t.Helper()
	for index, entry := range entries {
		canonical, err := canonicalJSON(json.RawMessage(entry.payload))
		if err != nil {
			t.Fatalf("canonicalize existing payload: %v", err)
		}
		if _, err := databaseHandle.Exec(
			`INSERT INTO journal_entries (
				id, vault_id, revision, payload, updated_at
			) VALUES ($1, $2, 1, $3::jsonb, $4)`,
			entry.sourceID, resolutionVaultID, canonical,
			time.Date(2026, 7, 19, 8, index, 0, 0, time.UTC),
		); err != nil {
			t.Fatalf("seed existing resolution entry: %v", err)
		}
	}
}

func stageResolutionMigration(
	t *testing.T,
	databaseHandle *sql.DB,
	entries []resolutionTestEntry,
) *Service {
	t.Helper()
	manifestEntries := make([]bundleManifestEntry, 0, len(entries))
	var totalBytes int64
	for _, entry := range entries {
		canonical, err := canonicalJSON(json.RawMessage(entry.payload))
		if err != nil {
			t.Fatalf("canonicalize staged payload: %v", err)
		}
		digest := sha256.Sum256(canonical)
		manifestEntries = append(manifestEntries, bundleManifestEntry{
			EntryID: entry.sourceID,
			SHA256:  hex.EncodeToString(digest[:]),
			Bytes:   int64(len(canonical)),
		})
		totalBytes += int64(len(canonical))
	}
	entriesFileDigest := sha256.Sum256([]byte("[]"))
	deletedIDsFileDigest := sha256.Sum256([]byte("[]"))
	manifestBytes, err := json.Marshal(bundleManifest{
		FormatVersion:    1,
		ExportedAt:       time.Date(2026, 7, 19, 8, 0, 0, 0, time.UTC).Format(time.RFC3339Nano),
		EntriesFile:      "entries.json",
		EntriesSHA256:    hex.EncodeToString(entriesFileDigest[:]),
		EntryCount:       len(entries),
		Entries:          manifestEntries,
		DeletedIDsFile:   "deleted_ids.json",
		DeletedIDsSHA256: hex.EncodeToString(deletedIDsFileDigest[:]),
		DeletedIDs:       []string{},
		Photos:           []bundleManifestPhoto{},
		Sources:          []string{"localStorage"},
	})
	if err != nil {
		t.Fatalf("encode resolution manifest: %v", err)
	}
	manifestDigest := sha256.Sum256(manifestBytes)
	service, err := NewService(&stubMigrationVaults{}, NewPostgresRepository(databaseHandle))
	if err != nil {
		t.Fatalf("create resolution migration service: %v", err)
	}
	if _, err := service.Create(context.Background(), resolutionAccountID, resolutionVaultID, CreateRequest{
		MigrationID: resolutionMigration, FormatVersion: 1, Source: "v1_bundle",
		EntryCount: len(entries), TotalBytes: totalBytes,
		ManifestSHA256: hex.EncodeToString(manifestDigest[:]),
		ManifestBase64: base64.StdEncoding.EncodeToString(manifestBytes),
	}); err != nil {
		t.Fatalf("Create() error = %v", err)
	}
	for _, entry := range entries {
		canonical, _ := canonicalJSON(json.RawMessage(entry.payload))
		digest := sha256.Sum256(canonical)
		if err := service.AddEntry(
			context.Background(), resolutionAccountID, resolutionVaultID, resolutionMigration,
			EntryInput{
				EntryID: entry.sourceID, Payload: canonical,
				SHA256: hex.EncodeToString(digest[:]),
			},
		); err != nil {
			t.Fatalf("AddEntry(%s) error = %v", entry.sourceID, err)
		}
	}
	return service
}

func assertResolutionDatabaseState(
	t *testing.T,
	databaseHandle *sql.DB,
	wantResolvedRows int,
	wantJournalRows int,
	wantSyncRows int,
) {
	t.Helper()
	var resolvedRows int
	if err := databaseHandle.QueryRow(
		`SELECT COUNT(*) FROM migration_entries
		 WHERE migration_id = $1 AND resolution <> 'pending' AND resolved_entry_id IS NOT NULL`,
		resolutionMigration,
	).Scan(&resolvedRows); err != nil {
		t.Fatalf("count resolved staging rows: %v", err)
	}
	var journalRows int
	if err := databaseHandle.QueryRow(
		"SELECT COUNT(*) FROM journal_entries WHERE vault_id = $1", resolutionVaultID,
	).Scan(&journalRows); err != nil {
		t.Fatalf("count journal rows: %v", err)
	}
	var syncRows int
	if err := databaseHandle.QueryRow(
		"SELECT COUNT(*) FROM sync_changes WHERE vault_id = $1", resolutionVaultID,
	).Scan(&syncRows); err != nil {
		t.Fatalf("count sync rows: %v", err)
	}
	if resolvedRows != wantResolvedRows || journalRows != wantJournalRows || syncRows != wantSyncRows {
		t.Fatalf(
			"database state resolved=%d journal=%d sync=%d, want %d/%d/%d",
			resolvedRows, journalRows, syncRows, wantResolvedRows, wantJournalRows, wantSyncRows,
		)
	}
}

func resolutionSummary(report Report) string {
	return fmt.Sprintf(
		"inserted=%d duplicates=%d conflicts=%d",
		report.InsertedEntries, report.DuplicateEntries, report.ConflictCopies,
	)
}
