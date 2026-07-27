package migration

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestVerifyCountMismatchCommitsReportErrorWithoutImporting(t *testing.T) {
	testVerifyValidationFailure(t, Report{
		ExpectedEntries:        2,
		ImportedEntries:        1,
		ExpectedAssets:         1,
		ExpectedDeletedEntries: 0,
		ImportedDeletedEntries: 1,
		ExpectedBytes:          40,
		VerifiedBytes:          20,
	})
}

func TestVerifyRejectsMissingPhotoBeforeImportingJournalEntries(t *testing.T) {
	testVerifyValidationFailure(t, Report{
		ExpectedEntries: 1,
		ImportedEntries: 1,
		ExpectedAssets:  1,
		VerifiedAssets:  0,
		ExpectedBytes:   40,
		VerifiedBytes:   20,
	})
}

func testVerifyValidationFailure(t *testing.T, report Report) {
	t.Helper()
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	repository := NewPostgresRepository(databaseHandle)
	migrationID := "11111111-1111-4111-8111-111111111111"
	vaultID := "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
	manifestBytes := []byte(`{"format_version":1}`)
	manifestDigest := sha256.Sum256(manifestBytes)

	mock.ExpectBegin()
	mock.ExpectQuery("SELECT status FROM vault_migrations").
		WithArgs(migrationID, vaultID).
		WillReturnRows(sqlmock.NewRows([]string{"status"}).AddRow("uploading"))
	mock.ExpectQuery("SELECT migration.id, migration.status").
		WithArgs(migrationID, vaultID).
		WillReturnRows(migrationReportRows(migrationID, report))
	mock.ExpectQuery("SELECT manifest_bytes, manifest_sha256 FROM vault_migrations").
		WithArgs(migrationID, vaultID).
		WillReturnRows(sqlmock.NewRows([]string{"manifest_bytes", "manifest_sha256"}).
			AddRow(manifestBytes, hex.EncodeToString(manifestDigest[:])))
	mock.ExpectExec("UPDATE vault_migrations SET last_errors").
		WithArgs(migrationID, "count_or_size_mismatch").
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	_, err = repository.Verify(context.Background(), vaultID, migrationID)
	if !errors.Is(err, ErrVerificationFailed) {
		t.Fatalf("Verify() error = %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func migrationReportRows(migrationID string, report Report) *sqlmock.Rows {
	return sqlmock.NewRows([]string{
		"id", "status", "expected_entries", "imported_entries", "inserted_entries",
		"duplicate_entries", "conflict_copies", "expected_deleted_entries",
		"imported_deleted_entries", "expected_assets", "verified_assets",
		"expected_bytes", "verified_bytes", "errors", "verified_at",
	}).AddRow(
		migrationID, "uploading", report.ExpectedEntries, report.ImportedEntries,
		report.InsertedEntries, report.DuplicateEntries, report.ConflictCopies,
		report.ExpectedDeletedEntries, report.ImportedDeletedEntries,
		report.ExpectedAssets, report.VerifiedAssets, report.ExpectedBytes,
		report.VerifiedBytes, []byte(`[]`), nil,
	)
}
