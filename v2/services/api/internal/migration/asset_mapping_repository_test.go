package migration

import (
	"context"
	"database/sql"
	"errors"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestGetAssetMappingsRejectsUnverifiedMigration(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })

	mock.ExpectQuery("SELECT status FROM vault_migrations").
		WithArgs("migration", "vault").
		WillReturnRows(sqlmock.NewRows([]string{"status"}).AddRow("uploading"))

	_, err = NewPostgresRepository(databaseHandle).GetAssetMappings(
		context.Background(), "vault", "migration",
	)
	if !errors.Is(err, ErrMigrationNotVerified) {
		t.Fatalf("GetAssetMappings() error = %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestGetAssetMappingsReturnsNotFoundOutsideVault(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })

	mock.ExpectQuery("SELECT status FROM vault_migrations").
		WithArgs("migration", "other-vault").
		WillReturnError(sql.ErrNoRows)

	_, err = NewPostgresRepository(databaseHandle).GetAssetMappings(
		context.Background(), "other-vault", "migration",
	)
	if !errors.Is(err, ErrMigrationNotFound) {
		t.Fatalf("GetAssetMappings() error = %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestGetAssetMappingsReturnsDeterministicFilenameOrder(t *testing.T) {
	databaseHandle, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("create SQL mock: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })

	mock.ExpectQuery("SELECT status FROM vault_migrations").
		WithArgs("migration", "vault").
		WillReturnRows(sqlmock.NewRows([]string{"status"}).AddRow("verified"))
	mock.ExpectQuery("SELECT item.source_filename, item.asset_id, item.byte_size, item.sha256").
		WithArgs("migration", "vault").
		WillReturnRows(sqlmock.NewRows([]string{"source_filename", "asset_id", "byte_size", "sha256"}).
			AddRow("photo-0001.jpg", "asset-a", int64(20), stringsOf("a", 64)).
			AddRow("photo-0002.jpg", "asset-b", int64(20), stringsOf("a", 64)))

	mappings, err := NewPostgresRepository(databaseHandle).GetAssetMappings(
		context.Background(), "vault", "migration",
	)
	if err != nil || len(mappings) != 2 || mappings[0].SourceFilename != "photo-0001.jpg" {
		t.Fatalf("GetAssetMappings() = %#v, error = %v", mappings, err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
