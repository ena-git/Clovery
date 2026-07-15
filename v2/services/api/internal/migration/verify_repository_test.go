package migration

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestVerifyLocksEveryEntryBeforeCollisionCheck(t *testing.T) {
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
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "status", "expected_entries", "imported_entries", "expected_assets",
			"expected_deleted_entries", "imported_deleted_entries", "verified_assets",
			"expected_bytes", "verified_bytes", "errors", "verified_at",
		}).AddRow(migrationID, "uploading", 1, 1, 0, 0, 0, 0, 20, 20, []byte(`[]`), nil))
	mock.ExpectQuery("SELECT manifest_bytes, manifest_sha256 FROM vault_migrations").
		WithArgs(migrationID, vaultID).
		WillReturnRows(sqlmock.NewRows([]string{"manifest_bytes", "manifest_sha256"}).
			AddRow(manifestBytes, hex.EncodeToString(manifestDigest[:])))
	mock.ExpectExec("pg_advisory_xact_lock.*migration_entries.*ORDER BY entry_id").
		WithArgs(vaultID, migrationID).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectQuery("SELECT COUNT.*migration_entries source").
		WithArgs(migrationID, vaultID).
		WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(0))
	mock.ExpectExec("INSERT INTO journal_entries").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec("INSERT INTO sync_changes").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec("UPDATE vault_migrations SET status = 'verified'").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec("INSERT INTO audit_events").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	if _, err := repository.Verify(context.Background(), vaultID, migrationID); err != nil {
		t.Fatalf("Verify() error = %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestVerifyCountMismatchCommitsReportErrorWithoutImporting(t *testing.T) {
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
		WillReturnRows(sqlmock.NewRows([]string{"status"}).AddRow("uploading"))
	mock.ExpectQuery("SELECT migration.id, migration.status").
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "status", "expected_entries", "imported_entries", "expected_assets",
			"expected_deleted_entries", "imported_deleted_entries", "verified_assets",
			"expected_bytes", "verified_bytes", "errors", "verified_at",
		}).AddRow(migrationID, "uploading", 2, 1, 1, 0, 1, 0, 40, 20, []byte(`[]`), nil))
	mock.ExpectQuery("SELECT manifest_bytes, manifest_sha256 FROM vault_migrations").
		WillReturnRows(sqlmock.NewRows([]string{"manifest_bytes", "manifest_sha256"}).
			AddRow(manifestBytes, hex.EncodeToString(manifestDigest[:])))
	mock.ExpectExec("UPDATE vault_migrations SET last_errors").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	_, err = repository.Verify(context.Background(), vaultID, migrationID)
	if !errors.Is(err, ErrVerificationFailed) {
		t.Fatalf("Verify() error = %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestVerifyRejectsMissingPhotoBeforeImportingJournalEntries(t *testing.T) {
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
		WillReturnRows(sqlmock.NewRows([]string{"status"}).AddRow("uploading"))
	mock.ExpectQuery("SELECT migration.id, migration.status").
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "status", "expected_entries", "imported_entries", "expected_assets",
			"expected_deleted_entries", "imported_deleted_entries", "verified_assets",
			"expected_bytes", "verified_bytes", "errors", "verified_at",
		}).AddRow(migrationID, "uploading", 1, 1, 1, 0, 0, 0, 40, 20, []byte(`[]`), nil))
	mock.ExpectQuery("SELECT manifest_bytes, manifest_sha256 FROM vault_migrations").
		WillReturnRows(sqlmock.NewRows([]string{"manifest_bytes", "manifest_sha256"}).
			AddRow(manifestBytes, hex.EncodeToString(manifestDigest[:])))
	mock.ExpectExec("UPDATE vault_migrations SET last_errors").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	_, err = repository.Verify(context.Background(), vaultID, migrationID)
	if !errors.Is(err, ErrVerificationFailed) {
		t.Fatalf("Verify() error = %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestVerifyRollsBackWhenImportedRowsDoNotMatchStagedEntries(t *testing.T) {
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
		WillReturnRows(sqlmock.NewRows([]string{"status"}).AddRow("uploading"))
	mock.ExpectQuery("SELECT migration.id, migration.status").
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "status", "expected_entries", "imported_entries", "expected_assets",
			"expected_deleted_entries", "imported_deleted_entries", "verified_assets",
			"expected_bytes", "verified_bytes", "errors", "verified_at",
		}).AddRow(migrationID, "uploading", 1, 1, 0, 0, 0, 0, 20, 20, []byte(`[]`), nil))
	mock.ExpectQuery("SELECT manifest_bytes, manifest_sha256 FROM vault_migrations").
		WillReturnRows(sqlmock.NewRows([]string{"manifest_bytes", "manifest_sha256"}).
			AddRow(manifestBytes, hex.EncodeToString(manifestDigest[:])))
	mock.ExpectExec("pg_advisory_xact_lock").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectQuery("SELECT COUNT.*migration_entries source").
		WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(0))
	mock.ExpectExec("INSERT INTO journal_entries").WillReturnResult(sqlmock.NewResult(0, 0))
	mock.ExpectRollback()
	mock.ExpectExec("UPDATE vault_migrations").WillReturnResult(sqlmock.NewResult(0, 1))

	_, err = repository.Verify(context.Background(), vaultID, migrationID)
	if !errors.Is(err, ErrEntryCollision) {
		t.Fatalf("Verify() error = %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
